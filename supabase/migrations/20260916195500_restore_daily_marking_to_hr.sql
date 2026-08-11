begin;

create or replace function public.save_candidate_daily_performance_entry(
    p_candidate_cycle_id uuid,
    p_performance_date date,
    p_work_delivery_score smallint,
    p_communication_responsibility_score smallint,
    p_reason_code text,
    p_reviewer_comment text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_existing_entry public.daily_performance_entries%rowtype;
    v_reviewer_user_id uuid;
    v_entry_id uuid;
    v_reason_code text;
    v_reviewer_comment text;
    v_requested_daily_total smallint;
    v_new_daily_total smallint;
    v_old_work_delivery_score smallint;
    v_old_communication_responsibility_score smallint;
    v_old_daily_total smallint;
    v_old_reason_code text;
    v_old_reviewer_comment text;
    v_eligible_days integer;
    v_scored_days integer;
    v_daily_average numeric;
    v_daily_component_score numeric;
    v_old_status text;
    v_new_status text;
    v_operation text;
    v_activity_type text;
    v_save_timestamp timestamptz := now();
    v_entry_exists boolean;
    v_has_elevated_access boolean;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'HR_SITE_CONNECT',
                   'HR_SITE_CONNECT_LEAD',
                   'HR_EXECUTIVE_LEAD',
                   'HR_LEAD'
               ]::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance marking access is not available.';
    end if;

    v_reviewer_user_id := public.current_app_user_id();

    if v_reviewer_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'Daily performance marking access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    if p_performance_date is null then
        raise exception 'p_performance_date must not be null.'
            using errcode = '22004';
    end if;

    if p_work_delivery_score is null
       or p_communication_responsibility_score is null then
        raise exception 'Both daily performance scores are required.'
            using errcode = '22004';
    end if;

    if p_work_delivery_score not between -5 and 5 then
        raise exception 'Work delivery score must be between -5 and 5.'
            using errcode = '22003';
    end if;

    if p_communication_responsibility_score not between -5 and 5 then
        raise exception
            'Communication and responsibility score must be between -5 and 5.'
            using errcode = '22003';
    end if;

    if p_performance_date > current_date then
        raise exception 'Daily performance cannot be marked for a future date.'
            using errcode = '22007';
    end if;

    v_reason_code := nullif(upper(btrim(p_reason_code)), '');
    v_reviewer_comment := nullif(btrim(p_reviewer_comment), '');
    v_requested_daily_total :=
        p_work_delivery_score + p_communication_responsibility_score;

    if v_reason_code is not null
       and v_reason_code not in (
           'WORK_COMPLETED',
           'PARTIAL_COMPLETION',
           'QUALITY_ISSUE',
           'DEADLINE_DELAY',
           'BLOCKER_COMMUNICATED',
           'MISSED_UPDATE',
           'STRONG_OWNERSHIP',
           'MEETING_ABSENCE',
           'FALSE_UPDATE',
           'OTHER'
       ) then
        raise exception 'Reason code is not valid.'
            using errcode = '22023';
    end if;

    if char_length(v_reviewer_comment) > 2000 then
        raise exception 'Reviewer comment must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    if (
        v_requested_daily_total <= -5
        or v_requested_daily_total = 10
    ) and v_reason_code is null then
        raise exception 'A reason code is required for this daily score.'
            using errcode = '23514';
    end if;

    if v_requested_daily_total = -10
       and v_reviewer_comment is null then
        raise exception 'A reviewer comment is required for the minimum daily score.'
            using errcode = '23514';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'daily-performance:'
                || p_candidate_cycle_id::text
                || ':'
                || p_performance_date::text,
            0::bigint
        )
    );

    begin
        select
            cpc.candidate_id,
            cpc.pod_id,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.result_status,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at,
            pc.cycle_status
        into strict v_assignment
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        where cpc.id = p_candidate_cycle_id
        for update of cpc;
    exception
        when no_data_found then
            raise exception 'Candidate performance cycle was not found.'
                using errcode = 'P0002';
    end;

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    if not v_has_elevated_access
       and not exists (
           select 1
           from public.pod_memberships pm
           where pm.user_id = v_reviewer_user_id
             and pm.pod_id = v_assignment.pod_id
             and pm.membership_type = 'HR_SITE_CONNECT'
             and public.current_user_has_role('HR_SITE_CONNECT')
             and pm.is_active = true
             and pm.effective_from <= current_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= current_date
             )
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance marking access is not available.';
    end if;

    if p_performance_date < v_assignment.evaluation_start_date
       or p_performance_date > v_assignment.evaluation_end_date then
        raise exception
            'Performance date must be inside the candidate evaluation period.'
            using errcode = '22007';
    end if;

    if extract(isodow from p_performance_date) = 7 then
        raise exception 'Daily performance cannot be marked for Sunday.'
            using errcode = '22007';
    end if;

    if exists (
        select 1
        from public.leave_requests lr
        where lr.candidate_id = v_assignment.candidate_id
          and lr.leave_status = 'APPROVED'
          and p_performance_date between lr.start_date and lr.end_date
          and lower(btrim(lr.leave_type)) <> 'work from home'
    ) then
        raise exception
            'Daily performance cannot be marked during approved leave.'
            using errcode = '22007';
    end if;

    if v_assignment.result_status in (
        'CANDIDATE_REVIEW',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Daily performance cannot be changed for this result status.'
            using errcode = '55000';
    end if;

    if v_assignment.final_score is not null
       or v_assignment.performance_band is not null
       or v_assignment.calculated_at is not null then
        raise exception
            'Daily performance cannot be changed after final calculation.'
            using errcode = '55000';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Daily performance marking is not available for this cycle status.'
            using errcode = '55000';
    end if;

    select dpe.*
    into v_existing_entry
    from public.daily_performance_entries dpe
    where dpe.candidate_cycle_id = p_candidate_cycle_id
      and dpe.performance_date = p_performance_date
    for update;

    v_entry_exists := found;

    if v_entry_exists then
        v_old_work_delivery_score := v_existing_entry.work_delivery_score;
        v_old_communication_responsibility_score :=
            v_existing_entry.communication_responsibility_score;
        v_old_daily_total := v_existing_entry.daily_total;
        v_old_reason_code := v_existing_entry.reason_code;
        v_old_reviewer_comment := v_existing_entry.reviewer_comment;
        v_operation := 'UPDATED';
        v_activity_type := 'DAILY_PERFORMANCE_MARK_UPDATED';

        update public.daily_performance_entries
        set
            work_delivery_score = p_work_delivery_score,
            communication_responsibility_score =
                p_communication_responsibility_score,
            reviewer_user_id = v_reviewer_user_id,
            reason_code = v_reason_code,
            reviewer_comment = v_reviewer_comment,
            submitted_at = v_save_timestamp,
            updated_at = v_save_timestamp
        where id = v_existing_entry.id
        returning
            id,
            daily_total
        into
            v_entry_id,
            v_new_daily_total;
    else
        v_operation := 'CREATED';
        v_activity_type := 'DAILY_PERFORMANCE_MARK_CREATED';

        insert into public.daily_performance_entries (
            candidate_cycle_id,
            performance_date,
            work_delivery_score,
            communication_responsibility_score,
            reviewer_user_id,
            reason_code,
            reviewer_comment,
            submitted_at,
            created_at,
            updated_at
        )
        values (
            p_candidate_cycle_id,
            p_performance_date,
            p_work_delivery_score,
            p_communication_responsibility_score,
            v_reviewer_user_id,
            v_reason_code,
            v_reviewer_comment,
            v_save_timestamp,
            v_save_timestamp,
            v_save_timestamp
        )
        returning
            id,
            daily_total
        into
            v_entry_id,
            v_new_daily_total;
    end if;

    select public.refresh_candidate_cycle_eligible_days(
        p_candidate_cycle_id
    )
    into v_eligible_days;

    begin
        select
            summary.scored_days,
            summary.daily_average,
            summary.daily_component_score
        into strict
            v_scored_days,
            v_daily_average,
            v_daily_component_score
        from public.refresh_candidate_cycle_daily_summary(
            p_candidate_cycle_id
        ) as summary;
    exception
        when no_data_found then
            raise exception 'Daily performance summary refresh returned no result.';
        when too_many_rows then
            raise exception 'Daily performance summary refresh returned multiple results.';
    end;

    begin
        select
            status_refresh.old_status,
            status_refresh.new_status
        into strict
            v_old_status,
            v_new_status
        from public.refresh_candidate_cycle_result_status(
            p_candidate_cycle_id
        ) as status_refresh;
    exception
        when no_data_found then
            raise exception 'Performance status refresh returned no result.';
        when too_many_rows then
            raise exception 'Performance status refresh returned multiple results.';
    end;

    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        from_status,
        to_status,
        remarks,
        activity_status,
        error_message,
        metadata,
        performed_by,
        performed_at,
        created_at,
        updated_at
    )
    values (
        v_assignment.candidate_id,
        v_activity_type,
        v_old_status,
        v_new_status,
        case v_operation
            when 'CREATED' then
                format(
                    'Daily performance mark created for %s.',
                    p_performance_date
                )
            else
                format(
                    'Daily performance mark updated for %s.',
                    p_performance_date
                )
        end,
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'daily_entry_id', v_entry_id,
            'performance_date', p_performance_date,
            'old_work_delivery_score', v_old_work_delivery_score,
            'new_work_delivery_score', p_work_delivery_score,
            'old_communication_responsibility_score',
                v_old_communication_responsibility_score,
            'new_communication_responsibility_score',
                p_communication_responsibility_score,
            'old_daily_total', v_old_daily_total,
            'new_daily_total', v_new_daily_total,
            'old_reason_code', v_old_reason_code,
            'new_reason_code', v_reason_code,
            'old_reviewer_comment', v_old_reviewer_comment,
            'new_reviewer_comment', v_reviewer_comment,
            'eligible_days', v_eligible_days,
            'scored_days', v_scored_days,
            'daily_average', v_daily_average,
            'daily_component_score', v_daily_component_score
        ),
        v_reviewer_user_id::text,
        v_save_timestamp,
        v_save_timestamp,
        v_save_timestamp
    );

    return jsonb_build_object(
        'dailyEntryId', v_entry_id,
        'candidateCycleId', p_candidate_cycle_id,
        'candidateId', v_assignment.candidate_id,
        'performanceDate', p_performance_date,
        'workDeliveryScore', p_work_delivery_score,
        'communicationResponsibilityScore',
            p_communication_responsibility_score,
        'dailyTotal', v_new_daily_total,
        'reasonCode', v_reason_code,
        'reviewerComment', v_reviewer_comment,
        'reviewerUserId', v_reviewer_user_id,
        'submittedAt', v_save_timestamp,
        'scoredDays', v_scored_days,
        'dailyAverage', v_daily_average,
        'dailyComponentScore', v_daily_component_score,
        'oldStatus', v_old_status,
        'newStatus', v_new_status,
        'operation', v_operation
    );
end;
$function$;

comment on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) is
    'Creates or updates one eligible daily performance mark for an authorized active HR reviewer, derives reviewer identity from the authenticated application user, refreshes the candidate-cycle daily summary and result status, and records a permanent activity log in the same transaction.';

revoke execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) from public;

revoke execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) from anon;

grant execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) to authenticated;

grant execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) to service_role;

commit;
