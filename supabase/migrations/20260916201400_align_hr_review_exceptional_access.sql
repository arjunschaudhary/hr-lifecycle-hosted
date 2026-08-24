begin;

-- Keep the HR Review detail readiness contract aligned with the India
-- business date used by Exceptional-score writes.
create or replace function public.get_candidate_hr_review(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    email text,
    applied_role text,
    role_code text,
    cycle_id uuid,
    cycle_code text,
    cycle_number integer,
    cycle_start_date date,
    cycle_end_date date,
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
    communication_professionalism_score smallint,
    attendance_update_discipline_score smallint,
    reporting_policy_compliance_score smallint,
    total_score smallint,
    reviewer_comment text,
    review_status text,
    reviewer_user_id uuid,
    reviewer_name text,
    submitted_at timestamptz,
    review_created_at timestamptz,
    review_updated_at timestamptz,
    task_status text,
    can_edit boolean,
    edit_reason text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_current_user_id uuid;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_has_elevated_access boolean;
    v_daily_scoring_complete boolean;
    v_review_is_open boolean;
    v_is_protected boolean;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'ADMIN',
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
            message = 'HR review access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_current_user_id := public.current_app_user_id();

    if v_current_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'HR review access is not available.';
    end if;

    begin
        select
            cpc.id as candidate_cycle_id,
            cpc.candidate_id,
            mc.full_name,
            mc.email,
            mc.applied_role,
            mc.role_code,
            cpc.cycle_id,
            pc.cycle_code,
            pc.cycle_number,
            pc.start_date as cycle_start_date,
            pc.end_date as cycle_end_date,
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
            cpc.daily_component_score
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

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'ADMIN',
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
           where pm.user_id = v_current_user_id
             and pm.pod_id = v_assignment.pod_id
             and pm.candidate_id is null
             and pm.membership_type = 'HR_SITE_CONNECT'
             and pm.is_active = true
             and pm.effective_from <= current_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= current_date
             )
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR review access is not available.';
    end if;

    v_daily_scoring_complete :=
        v_assignment.eligible_days > 0
        and v_assignment.scored_days = v_assignment.eligible_days
        and v_assignment.daily_component_score is not null;

    v_is_protected :=
        v_assignment.cycle_status in ('FINALIZED', 'LOCKED')
        or v_assignment.result_status in ('FINALIZED', 'LOCKED');

    v_review_is_open :=
        v_business_date >= v_assignment.review_open_date
        and v_assignment.cycle_status not in (
            'DRAFT',
            'FINALIZED',
            'LOCKED'
        )
        and v_assignment.result_status not in ('FINALIZED', 'LOCKED');

    return query
    select
        v_assignment.candidate_cycle_id::uuid,
        v_assignment.candidate_id::uuid,
        v_assignment.full_name::text,
        v_assignment.email::text,
        v_assignment.applied_role::text,
        v_assignment.role_code::text,
        v_assignment.cycle_id::uuid,
        v_assignment.cycle_code::text,
        v_assignment.cycle_number::integer,
        v_assignment.cycle_start_date::date,
        v_assignment.cycle_end_date::date,
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
        v_daily_scoring_complete,
        v_review_is_open,
        pr.id::uuid,
        pr.communication_professionalism_score::smallint,
        pr.attendance_update_discipline_score::smallint,
        pr.reporting_policy_compliance_score::smallint,
        pr.total_score::smallint,
        pr.reviewer_comment::text,
        pr.review_status::text,
        pr.reviewer_user_id::uuid,
        reviewer.name::text,
        pr.submitted_at::timestamptz,
        pr.created_at::timestamptz,
        pr.updated_at::timestamptz,
        case
            when v_is_protected then 'PROTECTED'
            when pr.review_status = 'SUBMITTED' then 'SUBMITTED'
            when pr.review_status = 'DRAFT' then 'DRAFT'
            when not v_daily_scoring_complete then
                'WAITING_FOR_DAILY_SCORING'
            when not v_review_is_open then 'NOT_OPEN'
            else 'READY'
        end::text,
        (
            v_daily_scoring_complete
            and v_review_is_open
            and not v_is_protected
        ),
        case
            when v_is_protected then
                'HR review is protected for this candidate cycle.'
            when not v_daily_scoring_complete then
                'Daily performance scoring must be complete before HR review.'
            when not v_review_is_open then
                'HR review is not open yet.'
            when pr.review_status = 'SUBMITTED' then
                'A nonblank amendment reason is required to change this submitted HR review.'
            else null::text
        end
    from (values (1)) as single_row(anchor)
    left join public.performance_reviews pr
        on pr.candidate_cycle_id = v_assignment.candidate_cycle_id
       and pr.review_type = 'HR'
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id;
end;
$function$;

comment on function public.get_candidate_hr_review(uuid) is
    'Returns one authorized candidate-cycle HR Review with candidate, cycle, pod, scoring readiness, reviewer identity, amendment availability, and HR-only review fields. Lead Review component scores are not exposed.';

revoke execute on function public.get_candidate_hr_review(uuid) from public;
revoke execute on function public.get_candidate_hr_review(uuid) from anon;
grant execute on function public.get_candidate_hr_review(uuid) to authenticated;
grant execute on function public.get_candidate_hr_review(uuid) to service_role;

-- Exceptional /10 is operationally owned by HR Psyconnect roles. Generic
-- ADMIN access is intentionally excluded while existing HR role and pod
-- authorization remains unchanged.
create or replace function public.save_candidate_exceptional_score(
    p_candidate_cycle_id uuid,
    p_exceptional_score numeric
)
returns table (
    candidate_cycle_id uuid,
    previous_exceptional_score numeric,
    exceptional_score numeric,
    result_status text,
    final_score numeric,
    performance_band text,
    calculated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_assignment record;
    v_has_elevated_access boolean;
    v_normalized_score numeric;
    v_new_result_status text;
    v_final_score numeric;
    v_performance_band text;
    v_calculated_at timestamptz;
    v_save_timestamp timestamptz := current_timestamp;
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
        raise insufficient_privilege
            using message = 'Exceptional performance scoring access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null then
        raise insufficient_privilege
            using message = 'Exceptional performance scoring access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    if p_exceptional_score is null then
        raise exception 'Exceptional score is required.'
            using errcode = '22004';
    end if;

    if p_exceptional_score < 0 or p_exceptional_score > 10 then
        raise exception 'Exceptional score must be between 0 and 10.'
            using errcode = '22003';
    end if;

    v_normalized_score := round(p_exceptional_score, 2);

    select
        cpc.candidate_id,
        cpc.pod_id,
        cpc.eligible_days,
        cpc.scored_days,
        cpc.daily_component_score,
        cpc.exceptional_score,
        cpc.result_status,
        pc.review_open_date,
        pc.cycle_status
    into strict v_assignment
    from public.candidate_performance_cycles cpc
    join public.performance_cycles pc
      on pc.id = cpc.cycle_id
    where cpc.id = p_candidate_cycle_id
    for update of cpc;

    if v_assignment.result_status in (
        'FINALIZED',
        'LOCKED',
        'NOT_EVALUATED'
    ) then
        raise exception
            'Exceptional score cannot be changed for this terminal performance result.'
            using errcode = 'P0001';
    end if;

    if v_assignment.eligible_days <= 0 then
        raise exception
            'Exceptional scoring requires eligible performance days.'
            using errcode = 'P0001';
    end if;

    if v_assignment.scored_days <> v_assignment.eligible_days
       or v_assignment.daily_component_score is null then
        raise exception
            'Daily performance scoring must be complete before Exceptional scoring.'
            using errcode = 'P0001';
    end if;

    if v_business_date < v_assignment.review_open_date then
        raise exception
            'Exceptional scoring is not open yet.'
            using errcode = 'P0001';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Exceptional scoring is not available for this cycle status.'
            using errcode = 'P0001';
    end if;

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
            from public.user_roles ur
            join public.roles r
              on r.id = ur.role_id
             and r.slug = 'HR_SITE_CONNECT'
             and r.is_active = true
            join public.pod_memberships pm
              on pm.user_id = ur.user_id
             and pm.membership_type = 'HR_SITE_CONNECT'
             and pm.pod_id = v_assignment.pod_id
             and pm.candidate_id is null
             and pm.is_active = true
             and pm.effective_from <= v_business_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= v_business_date
             )
            where ur.user_id = v_actor_user_id
              and ur.is_active = true
              and ur.ended_at is null
       ) then
        raise insufficient_privilege
            using message = 'Exceptional performance scoring access is not available.';
    end if;

    if v_assignment.exceptional_score
       is not distinct from v_normalized_score then
        select
            advancement.new_status,
            advancement.final_score,
            advancement.performance_band,
            advancement.calculated_at
        into strict
            v_new_result_status,
            v_final_score,
            v_performance_band,
            v_calculated_at
        from public.advance_candidate_cycle_performance(
            p_candidate_cycle_id
        ) as advancement;

        return query
        select
            p_candidate_cycle_id,
            v_assignment.exceptional_score,
            v_normalized_score,
            v_new_result_status,
            v_final_score,
            v_performance_band,
            v_calculated_at;
        return;
    end if;

    update public.candidate_performance_cycles
    set
        exceptional_score = v_normalized_score,
        final_score = null,
        performance_band = null,
        calculated_at = null,
        finalized_at = null,
        updated_at = v_save_timestamp
    where id = p_candidate_cycle_id;

    select
        advancement.new_status,
        advancement.final_score,
        advancement.performance_band,
        advancement.calculated_at
    into strict
        v_new_result_status,
        v_final_score,
        v_performance_band,
        v_calculated_at
    from public.advance_candidate_cycle_performance(
        p_candidate_cycle_id
    ) as advancement;

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
        performed_at
    )
    values (
        v_assignment.candidate_id,
        'PERFORMANCE_EXCEPTIONAL_SCORE_UPDATED',
        v_assignment.result_status,
        v_new_result_status,
        'Exceptional performance score saved by HR.',
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'old_exceptional_score', v_assignment.exceptional_score,
            'new_exceptional_score', v_normalized_score,
            'actor_user_id', v_actor_user_id
        ),
        v_actor_user_id::text,
        v_save_timestamp
    );

    return query
    select
        p_candidate_cycle_id,
        v_assignment.exceptional_score,
        v_normalized_score,
        v_new_result_status,
        v_final_score,
        v_performance_band,
        v_calculated_at;
exception
    when no_data_found then
        raise exception
            'Candidate performance cycle does not exist.'
            using errcode = 'P0001';
end;
$function$;

comment on function public.save_candidate_exceptional_score(uuid, numeric) is
    'Allows authorized HR performance reviewers to enter or amend an explicit 0-to-10 candidate-cycle Exceptional score after Daily scoring is complete and review is open. It uses the existing HR review role/pod model, keeps exceptional_contributions separate, invalidates any provisional final result before recalculation, audits changes, and advances the result automatically.';

revoke execute on function public.save_candidate_exceptional_score(uuid, numeric) from public;
revoke execute on function public.save_candidate_exceptional_score(uuid, numeric) from anon;
grant execute on function public.save_candidate_exceptional_score(uuid, numeric) to authenticated;
grant execute on function public.save_candidate_exceptional_score(uuid, numeric) to service_role;

commit;

