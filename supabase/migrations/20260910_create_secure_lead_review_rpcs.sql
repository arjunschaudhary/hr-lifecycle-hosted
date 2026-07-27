begin;

create or replace function public.get_candidate_lead_review(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    cycle_id uuid,
    cycle_code text,
    cycle_status text,
    review_open_date date,
    lock_date date,
    pod_id uuid,
    pod_code text,
    pod_name text,
    evaluation_start_date date,
    evaluation_end_date date,
    result_status text,
    eligible_days integer,
    scored_days integer,
    daily_component_score numeric,
    daily_scoring_complete boolean,
    review_is_open boolean,
    review_id uuid,
    reviewer_user_id uuid,
    reviewer_name text,
    work_quality_score smallint,
    role_capability_score smallint,
    deadline_delivery_score smallint,
    ownership_teamwork_score smallint,
    total_score smallint,
    reviewer_comment text,
    review_status text,
    submitted_at timestamptz,
    review_created_at timestamptz,
    review_updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_current_user_id uuid;
    v_has_dashboard_access boolean;
    v_has_lead_role boolean;
    v_has_lead_pod_membership boolean;
begin
    if not coalesce(public.current_user_is_active(), false) then
        raise exception using
            errcode = '42501',
            message = 'Lead review access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_current_user_id := public.current_app_user_id();

    begin
        select
            cpc.id as candidate_cycle_id,
            cpc.candidate_id,
            mc.full_name,
            cpc.cycle_id,
            pc.cycle_code,
            pc.cycle_status,
            pc.review_open_date,
            pc.lock_date,
            cpc.pod_id,
            p.pod_code,
            p.pod_name,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.result_status,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at
        into strict v_assignment
        from public.candidate_performance_cycles cpc
        join public.master_candidates mc
            on mc.candidate_id = cpc.candidate_id
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        join public.pods p
            on p.id = cpc.pod_id
        where cpc.id = p_candidate_cycle_id;
    exception
        when no_data_found then
            raise exception 'Candidate performance cycle was not found.'
                using errcode = 'P0002';
    end;

    v_has_dashboard_access := coalesce(
        public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT',
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    v_has_lead_role := coalesce(
        public.current_user_has_any_role(
            array[
                'POD_LEAD',
                'TECH_LEAD',
                'TEAM_LEAD'
            ]::text[]
        ),
        false
    );

    select exists (
        select 1
        from public.pod_memberships pm
        join public.user_roles ur
            on ur.user_id = pm.user_id
        join public.roles r
            on r.id = ur.role_id
           and r.slug = pm.membership_type
        where pm.pod_id = v_assignment.pod_id
          and pm.user_id = v_current_user_id
          and pm.candidate_id is null
          and pm.membership_type in (
              'POD_LEAD',
              'TECH_LEAD',
              'TEAM_LEAD'
          )
          and pm.is_active = true
          and pm.effective_from <= current_date
          and (
              pm.effective_to is null
              or pm.effective_to >= current_date
          )
          and ur.is_active = true
          and ur.ended_at is null
          and r.is_active = true
    )
    into v_has_lead_pod_membership;

    if not v_has_dashboard_access
       and not (
           v_has_lead_role
           and coalesce(
               public.current_user_has_pod_access(v_assignment.pod_id),
               false
           )
           and v_has_lead_pod_membership
       ) then
        raise exception using
            errcode = '42501',
            message = 'Lead review access is not available.';
    end if;

    return query
    select
        v_assignment.candidate_cycle_id::uuid,
        v_assignment.candidate_id::uuid,
        v_assignment.full_name::text,
        v_assignment.cycle_id::uuid,
        v_assignment.cycle_code::text,
        v_assignment.cycle_status::text,
        v_assignment.review_open_date::date,
        v_assignment.lock_date::date,
        v_assignment.pod_id::uuid,
        v_assignment.pod_code::text,
        v_assignment.pod_name::text,
        v_assignment.evaluation_start_date::date,
        v_assignment.evaluation_end_date::date,
        v_assignment.result_status::text,
        v_assignment.eligible_days::integer,
        v_assignment.scored_days::integer,
        v_assignment.daily_component_score::numeric,
        (
            v_assignment.eligible_days > 0
            and v_assignment.scored_days = v_assignment.eligible_days
            and v_assignment.daily_component_score is not null
        ) as daily_scoring_complete,
        (
            current_date >= v_assignment.review_open_date
            and v_assignment.cycle_status not in (
                'DRAFT',
                'FINALIZED',
                'LOCKED'
            )
            and v_assignment.result_status not in (
                'CANDIDATE_REVIEW',
                'FINALIZED',
                'LOCKED'
            )
            and v_assignment.final_score is null
            and v_assignment.performance_band is null
            and v_assignment.calculated_at is null
        ) as review_is_open,
        pr.id,
        pr.reviewer_user_id,
        reviewer.name::text,
        pr.work_quality_score,
        pr.role_capability_score,
        pr.deadline_delivery_score,
        pr.ownership_teamwork_score,
        pr.total_score,
        pr.reviewer_comment,
        pr.review_status,
        pr.submitted_at,
        pr.created_at,
        pr.updated_at
    from (values (1)) as single_row(anchor)
    left join public.performance_reviews pr
        on pr.candidate_cycle_id = v_assignment.candidate_cycle_id
       and pr.review_type = 'LEAD'
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id;
end;
$function$;

comment on function public.get_candidate_lead_review(uuid) is
    'Returns one candidate-cycle Lead review with its candidate, cycle, pod, daily-scoring readiness, review-window state, and reviewer name. Read access is limited to active authorized HR dashboard users or active Lead-role users with matching Lead pod authority; reviewer email addresses are not exposed.';

revoke execute on function public.get_candidate_lead_review(uuid) from public;
revoke execute on function public.get_candidate_lead_review(uuid) from anon;
grant execute on function public.get_candidate_lead_review(uuid) to authenticated;
grant execute on function public.get_candidate_lead_review(uuid) to service_role;

create or replace function public.save_candidate_lead_review(
    p_candidate_cycle_id uuid,
    p_work_quality_score smallint,
    p_role_capability_score smallint,
    p_deadline_delivery_score smallint,
    p_ownership_teamwork_score smallint,
    p_reviewer_comment text,
    p_review_status text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_existing_review public.performance_reviews%rowtype;
    v_reviewer_user_id uuid;
    v_reviewer_name text;
    v_review_status text;
    v_reviewer_comment text;
    v_review_id uuid;
    v_new_total_score smallint;
    v_new_submitted_at timestamptz;
    v_old_review_status text;
    v_old_work_quality_score smallint;
    v_old_role_capability_score smallint;
    v_old_deadline_delivery_score smallint;
    v_old_ownership_teamwork_score smallint;
    v_old_total_score smallint;
    v_old_reviewer_comment text;
    v_lead_score numeric;
    v_old_result_status text;
    v_new_result_status text;
    v_operation text;
    v_activity_type text;
    v_remarks text;
    v_save_timestamp timestamptz := now();
    v_review_exists boolean;
    v_has_lead_pod_membership boolean;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'POD_LEAD',
                   'TECH_LEAD',
                   'TEAM_LEAD'
               ]::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Lead review marking access is not available.';
    end if;

    v_reviewer_user_id := public.current_app_user_id();

    if v_reviewer_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'Lead review marking access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_review_status := upper(btrim(p_review_status));
    v_reviewer_comment := nullif(btrim(p_reviewer_comment), '');

    if v_review_status is null
       or v_review_status not in ('DRAFT', 'SUBMITTED') then
        raise exception 'Review status must be DRAFT or SUBMITTED.'
            using errcode = '22023';
    end if;

    if p_work_quality_score is not null
       and p_work_quality_score not between 0 and 10 then
        raise exception 'Work quality score must be between 0 and 10.'
            using errcode = '22003';
    end if;

    if p_role_capability_score is not null
       and p_role_capability_score not between 0 and 5 then
        raise exception 'Role capability score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_deadline_delivery_score is not null
       and p_deadline_delivery_score not between 0 and 5 then
        raise exception 'Deadline delivery score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_ownership_teamwork_score is not null
       and p_ownership_teamwork_score not between 0 and 5 then
        raise exception 'Ownership and teamwork score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if v_review_status = 'SUBMITTED'
       and (
           p_work_quality_score is null
           or p_role_capability_score is null
           or p_deadline_delivery_score is null
           or p_ownership_teamwork_score is null
       ) then
        raise exception 'All Lead review scores are required for submission.'
            using errcode = '23514';
    end if;

    if char_length(v_reviewer_comment) > 2000 then
        raise exception 'Reviewer comment must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    v_new_total_score :=
        coalesce(p_work_quality_score, 0)
        + coalesce(p_role_capability_score, 0)
        + coalesce(p_deadline_delivery_score, 0)
        + coalesce(p_ownership_teamwork_score, 0);

    if v_new_total_score not between 0 and 25 then
        raise exception 'Lead review total must be between 0 and 25.'
            using errcode = '22003';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'performance-review:'
                || p_candidate_cycle_id::text
                || ':LEAD',
            0::bigint
        )
    );

    begin
        select
            cpc.candidate_id,
            cpc.pod_id,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.result_status,
            cpc.lead_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at,
            pc.review_open_date,
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

    select exists (
        select 1
        from public.pod_memberships pm
        join public.user_roles ur
            on ur.user_id = pm.user_id
        join public.roles r
            on r.id = ur.role_id
           and r.slug = pm.membership_type
        where pm.pod_id = v_assignment.pod_id
          and pm.user_id = v_reviewer_user_id
          and pm.candidate_id is null
          and pm.membership_type in (
              'POD_LEAD',
              'TECH_LEAD',
              'TEAM_LEAD'
          )
          and pm.is_active = true
          and pm.effective_from <= current_date
          and (
              pm.effective_to is null
              or pm.effective_to >= current_date
          )
          and ur.is_active = true
          and ur.ended_at is null
          and r.is_active = true
    )
    into v_has_lead_pod_membership;

    if not coalesce(
        public.current_user_has_pod_access(v_assignment.pod_id),
        false
    ) or not v_has_lead_pod_membership then
        raise exception using
            errcode = '42501',
            message = 'Lead review marking access is not available.';
    end if;

    if v_assignment.eligible_days <= 0 then
        raise exception 'Lead review requires eligible performance days.'
            using errcode = '55000';
    end if;

    if v_assignment.scored_days
       is distinct from v_assignment.eligible_days
       or v_assignment.daily_component_score is null then
        raise exception
            'Daily performance scoring must be complete before Lead review.'
            using errcode = '55000';
    end if;

    if current_date < v_assignment.review_open_date then
        raise exception 'Lead review is not open yet.'
            using errcode = '55000';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Lead review is not available for this cycle status.'
            using errcode = '55000';
    end if;

    if v_assignment.result_status in (
        'CANDIDATE_REVIEW',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Lead review is not available for this result status.'
            using errcode = '55000';
    end if;

    if v_assignment.final_score is not null
       or v_assignment.performance_band is not null
       or v_assignment.calculated_at is not null then
        raise exception
            'Lead review cannot be changed after final calculation.'
            using errcode = '55000';
    end if;

    select pr.*
    into v_existing_review
    from public.performance_reviews pr
    where pr.candidate_cycle_id = p_candidate_cycle_id
      and pr.review_type = 'LEAD'
    for update;

    v_review_exists := found;

    if v_review_exists
       and v_existing_review.review_status = 'SUBMITTED' then
        raise exception 'A submitted Lead review cannot be changed.'
            using errcode = '55000';
    end if;

    if v_review_exists then
        v_old_review_status := v_existing_review.review_status;
        v_old_work_quality_score := v_existing_review.work_quality_score;
        v_old_role_capability_score :=
            v_existing_review.role_capability_score;
        v_old_deadline_delivery_score :=
            v_existing_review.deadline_delivery_score;
        v_old_ownership_teamwork_score :=
            v_existing_review.ownership_teamwork_score;
        v_old_total_score := v_existing_review.total_score;
        v_old_reviewer_comment := v_existing_review.reviewer_comment;
    end if;

    if v_review_status = 'SUBMITTED' then
        v_operation := 'SUBMITTED';
        v_activity_type := 'LEAD_REVIEW_SUBMITTED';
        v_remarks := 'Lead performance review submitted.';
    elsif v_review_exists then
        v_operation := 'DRAFT_UPDATED';
        v_activity_type := 'LEAD_REVIEW_DRAFT_UPDATED';
        v_remarks := 'Lead performance review draft updated.';
    else
        v_operation := 'DRAFT_CREATED';
        v_activity_type := 'LEAD_REVIEW_DRAFT_CREATED';
        v_remarks := 'Lead performance review draft created.';
    end if;

    if v_review_exists then
        update public.performance_reviews
        set
            reviewer_user_id = v_reviewer_user_id,
            work_quality_score = p_work_quality_score,
            role_capability_score = p_role_capability_score,
            deadline_delivery_score = p_deadline_delivery_score,
            ownership_teamwork_score = p_ownership_teamwork_score,
            reviewer_comment = v_reviewer_comment,
            review_status = v_review_status,
            submitted_at = case
                when v_review_status = 'SUBMITTED' then v_save_timestamp
                else null
            end,
            updated_at = v_save_timestamp
        where id = v_existing_review.id
        returning
            id,
            total_score,
            submitted_at
        into
            v_review_id,
            v_new_total_score,
            v_new_submitted_at;
    else
        insert into public.performance_reviews (
            candidate_cycle_id,
            review_type,
            reviewer_user_id,
            work_quality_score,
            role_capability_score,
            deadline_delivery_score,
            ownership_teamwork_score,
            reviewer_comment,
            review_status,
            submitted_at,
            created_at,
            updated_at
        )
        values (
            p_candidate_cycle_id,
            'LEAD',
            v_reviewer_user_id,
            p_work_quality_score,
            p_role_capability_score,
            p_deadline_delivery_score,
            p_ownership_teamwork_score,
            v_reviewer_comment,
            v_review_status,
            case
                when v_review_status = 'SUBMITTED' then v_save_timestamp
                else null
            end,
            v_save_timestamp,
            v_save_timestamp
        )
        returning
            id,
            total_score,
            submitted_at
        into
            v_review_id,
            v_new_total_score,
            v_new_submitted_at;
    end if;

    v_old_result_status := v_assignment.result_status;

    if v_review_status = 'SUBMITTED' then
        begin
            select review_summary.lead_score
            into strict v_lead_score
            from public.refresh_candidate_cycle_review_summary(
                p_candidate_cycle_id
            ) as review_summary;
        exception
            when no_data_found then
                raise exception 'Review summary refresh returned no result.';
            when too_many_rows then
                raise exception 'Review summary refresh returned multiple results.';
        end;

        begin
            select
                status_refresh.old_status,
                status_refresh.new_status
            into strict
                v_old_result_status,
                v_new_result_status
            from public.refresh_candidate_cycle_result_status(
                p_candidate_cycle_id
            ) as status_refresh;
        exception
            when no_data_found then
                raise exception 'Performance status refresh returned no result.';
            when too_many_rows then
                raise exception 'Performance status refresh returned multiple results.';
        end;
    else
        v_lead_score := v_assignment.lead_score;
        v_new_result_status := v_old_result_status;
    end if;

    select u.name::text
    into strict v_reviewer_name
    from public.users u
    where u.id = v_reviewer_user_id;

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
        v_old_result_status,
        v_new_result_status,
        v_remarks,
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'review_id', v_review_id,
            'review_type', 'LEAD',
            'old_review_status', v_old_review_status,
            'new_review_status', v_review_status,
            'old_work_quality_score', v_old_work_quality_score,
            'new_work_quality_score', p_work_quality_score,
            'old_role_capability_score', v_old_role_capability_score,
            'new_role_capability_score', p_role_capability_score,
            'old_deadline_delivery_score', v_old_deadline_delivery_score,
            'new_deadline_delivery_score', p_deadline_delivery_score,
            'old_ownership_teamwork_score',
                v_old_ownership_teamwork_score,
            'new_ownership_teamwork_score',
                p_ownership_teamwork_score,
            'old_total_score', v_old_total_score,
            'new_total_score', v_new_total_score,
            'old_reviewer_comment', v_old_reviewer_comment,
            'new_reviewer_comment', v_reviewer_comment,
            'reviewer_user_id', v_reviewer_user_id,
            'lead_score', v_lead_score
        ),
        v_reviewer_user_id::text,
        v_save_timestamp,
        v_save_timestamp,
        v_save_timestamp
    );

    return jsonb_build_object(
        'reviewId', v_review_id,
        'candidateCycleId', p_candidate_cycle_id,
        'candidateId', v_assignment.candidate_id,
        'podId', v_assignment.pod_id,
        'reviewStatus', v_review_status,
        'workQualityScore', p_work_quality_score,
        'roleCapabilityScore', p_role_capability_score,
        'deadlineDeliveryScore', p_deadline_delivery_score,
        'ownershipTeamworkScore', p_ownership_teamwork_score,
        'totalScore', v_new_total_score,
        'reviewerComment', v_reviewer_comment,
        'reviewerUserId', v_reviewer_user_id,
        'reviewerName', v_reviewer_name,
        'submittedAt', v_new_submitted_at,
        'leadScore', v_lead_score,
        'oldResultStatus', v_old_result_status,
        'newResultStatus', v_new_result_status,
        'operation', v_operation
    );
end;
$function$;

comment on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) is
    'Creates or updates one partial Lead review draft, or submits one complete Lead review, for an active authorized Lead with matching Lead pod authority. Submitted reviews are immutable; submission refreshes the stored review summary and candidate result status and records a permanent activity log atomically.';

revoke execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) from public;

revoke execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) from anon;

grant execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) to authenticated;

grant execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) to service_role;

commit;
