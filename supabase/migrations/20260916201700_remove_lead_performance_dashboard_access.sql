begin;

-- Project Managers and Pod Leads use the dedicated Lead Reviews workspace.
-- These dashboard RPCs retain only their existing HR and HR Psyconnect access;
-- a mixed-role user can still enter through an independently authorized HR role.

create or replace function public.get_performance_cycle_overview()
returns setof public.performance_cycle_overview_view
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid := public.current_app_user_id();
    v_has_elevated_access boolean;
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
           array[
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE',
               'HR_EXECUTIVE_LEAD',
               'HR_LEAD'
           ]::text[]
       ) is not true then
        raise insufficient_privilege
            using message = 'Performance dashboard access is not available.';
    end if;

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    if v_has_elevated_access then
        return query
        select overview.*
        from public.performance_cycle_overview_view overview
        order by
            overview.cycle_number desc,
            overview.cycle_id desc;

        return;
    end if;

    return query
    select
        pc.id as cycle_id,
        pc.cycle_code,
        pc.cycle_number,
        pc.start_date,
        pc.end_date,
        pc.review_open_date,
        pc.lock_date,
        pc.cycle_status,
        count(cpc.id)::integer as assignment_count,
        count(distinct cpc.pod_id)::integer as pod_count,
        count(cpc.id) filter (
            where cpc.is_partial_cycle = true
        )::integer as partial_cycle_count,
        coalesce(sum(cpc.eligible_days), 0)::integer as total_eligible_days,
        coalesce(sum(cpc.scored_days), 0)::integer as total_scored_days,
        case
            when coalesce(sum(cpc.eligible_days), 0) > 0 then
                round(
                    coalesce(sum(cpc.scored_days), 0)::numeric
                    / coalesce(sum(cpc.eligible_days), 0)::numeric
                    * 100,
                    2
                )
            else 0::numeric
        end as scoring_completion_percent,
        count(cpc.id) filter (
            where cpc.result_status = 'PENDING'
        )::integer as pending_count,
        count(cpc.id) filter (
            where cpc.result_status = 'DAILY_SCORING'
        )::integer as daily_scoring_count,
        count(cpc.id) filter (
            where cpc.result_status = 'AWAITING_REVIEWS'
        )::integer as awaiting_reviews_count,
        count(cpc.id) filter (
            where cpc.result_status = 'READY_TO_CALCULATE'
        )::integer as ready_to_calculate_count,
        count(cpc.id) filter (
            where cpc.result_status = 'CANDIDATE_REVIEW'
        )::integer as candidate_review_count,
        count(cpc.id) filter (
            where cpc.result_status = 'FINALIZED'
        )::integer as finalized_count,
        count(cpc.id) filter (
            where cpc.result_status = 'LOCKED'
        )::integer as locked_count,
        count(cpc.id) filter (
            where cpc.daily_component_score is not null
        )::integer as daily_summary_ready_count,
        count(cpc.id) filter (
            where cpc.lead_score is not null
        )::integer as lead_review_ready_count,
        count(cpc.id) filter (
            where cpc.hr_score is not null
        )::integer as hr_review_ready_count,
        count(cpc.id) filter (
            where cpc.lead_score is not null
              and cpc.hr_score is not null
        )::integer as review_summary_ready_count,
        count(cpc.id) filter (
            where cpc.exceptional_score is not null
        )::integer as exceptional_summary_ready_count,
        count(cpc.id) filter (
            where cpc.final_score is not null
              and cpc.performance_band is not null
        )::integer as final_result_count,
        round(avg(cpc.final_score), 2)::numeric as average_final_score,
        pc.created_at as cycle_created_at,
        pc.updated_at as cycle_updated_at
    from public.performance_cycles pc
    join public.candidate_performance_cycles cpc
        on cpc.cycle_id = pc.id
    where exists (
        select 1
        from public.pod_memberships pm
        where pm.user_id = v_actor_user_id
          and pm.pod_id = cpc.pod_id
          and (
              (
                  pm.membership_type = 'HR_SITE_CONNECT'
                  and public.current_user_has_role('HR_SITE_CONNECT')
              )
          )
          and pm.is_active = true
          and pm.effective_from <=
              (current_timestamp at time zone 'Asia/Kolkata')::date
          and (
              pm.effective_to is null
              or pm.effective_to >=
                  (current_timestamp at time zone 'Asia/Kolkata')::date
          )
    )
    group by
        pc.id,
        pc.cycle_code,
        pc.cycle_number,
        pc.start_date,
        pc.end_date,
        pc.review_open_date,
        pc.lock_date,
        pc.cycle_status,
        pc.created_at,
        pc.updated_at
    order by
        pc.cycle_number desc,
        pc.id desc;
end;
$function$;

comment on function public.get_performance_cycle_overview() is
    'Returns the read-only performance-cycle overview to active authenticated performance users with an approved dashboard role. It performs no performance write or workflow action.';

revoke execute on function public.get_performance_cycle_overview() from public;
revoke execute on function public.get_performance_cycle_overview() from anon;
grant execute on function public.get_performance_cycle_overview() to authenticated;
grant execute on function public.get_performance_cycle_overview() to service_role;

create or replace function public.get_candidate_performance_list()
returns setof public.candidate_performance_list_view
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid := public.current_app_user_id();
    v_has_elevated_access boolean;
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
           array[
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE',
               'HR_EXECUTIVE_LEAD',
               'HR_LEAD'
           ]::text[]
       ) is not true then
        raise insufficient_privilege
            using message = 'Performance dashboard access is not available.';
    end if;

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    return query
    select candidate_performance.*
    from public.candidate_performance_list_view candidate_performance
    where v_has_elevated_access
       or exists (
           select 1
           from public.pod_memberships pm
           where pm.user_id = v_actor_user_id
             and pm.pod_id = candidate_performance.pod_id
             and (
                 (
                     pm.membership_type = 'HR_SITE_CONNECT'
                     and public.current_user_has_role('HR_SITE_CONNECT')
                 )
             )
             and pm.is_active = true
             and pm.effective_from <=
                 (current_timestamp at time zone 'Asia/Kolkata')::date
             and (
                 pm.effective_to is null
                 or pm.effective_to >=
                     (current_timestamp at time zone 'Asia/Kolkata')::date
             )
       )
    order by
        candidate_performance.cycle_start_date desc,
        candidate_performance.full_name asc,
        candidate_performance.candidate_cycle_id asc;
end;
$function$;

comment on function public.get_candidate_performance_list() is
    'Returns the read-only candidate performance list to active authenticated performance users with an approved dashboard role. It performs no scoring, review, calculation, finalization, locking, or other write action.';

revoke execute on function public.get_candidate_performance_list() from public;
revoke execute on function public.get_candidate_performance_list() from anon;
grant execute on function public.get_candidate_performance_list() to authenticated;
grant execute on function public.get_candidate_performance_list() to service_role;

create or replace function public.get_performance_action_queue()
returns setof public.performance_action_queue_view
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid := public.current_app_user_id();
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_has_admin boolean;
    v_has_hr_site_connect boolean;
    v_has_hr_site_connect_lead boolean;
    v_has_hr_executive_lead boolean;
    v_has_hr_lead boolean;
    v_has_lead_review_access boolean;
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
           array[
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE',
               'HR_EXECUTIVE_LEAD',
               'HR_LEAD'
           ]::text[]
       ) is not true then
        raise insufficient_privilege
            using message = 'Performance dashboard access is not available.';
    end if;

    v_has_admin := coalesce(
        public.current_user_has_role('ADMIN'),
        false
    );
    v_has_hr_site_connect := coalesce(
        public.current_user_has_role('HR_SITE_CONNECT'),
        false
    );
    v_has_hr_site_connect_lead := coalesce(
        public.current_user_has_role('HR_SITE_CONNECT_LEAD'),
        false
    );
    v_has_hr_executive_lead := coalesce(
        public.current_user_has_role('HR_EXECUTIVE_LEAD'),
        false
    );
    v_has_hr_lead := coalesce(
        public.current_user_has_role('HR_LEAD'),
        false
    );
    v_has_lead_review_access := coalesce(
        public.current_user_has_any_role(
            array['POD_LEAD', 'TECH_LEAD']::text[]
        ),
        false
    );

    return query
    select action_queue.*
    from public.performance_action_queue_view action_queue
    where (
        action_queue.action_code = 'SUBMIT_LEAD_REVIEW'
        and case
            when v_has_lead_review_access then exists (
                select 1
                from public.get_lead_review_tasks() lead_task
                where lead_task.candidate_cycle_id =
                    action_queue.candidate_cycle_id
            )
            else false
        end
    )
    or (
        action_queue.action_code = 'COMPLETE_DAILY_SCORING'
        and (
            v_has_hr_site_connect_lead
            or v_has_hr_executive_lead
            or v_has_hr_lead
            or (
                v_has_hr_site_connect
                and exists (
                    select 1
                    from public.pod_memberships pm
                    where pm.user_id = v_actor_user_id
                      and pm.pod_id = action_queue.pod_id
                      and pm.membership_type = 'HR_SITE_CONNECT'
                      and pm.is_active = true
                      and pm.effective_from <= current_date
                      and (
                          pm.effective_to is null
                          or pm.effective_to >= current_date
                      )
                )
            )
        )
    )
    or (
        action_queue.action_code in (
            'SUBMIT_HR_REVIEW',
            'REVIEW_EXCEPTIONAL_CONTRIBUTIONS'
        )
        and (
            v_has_admin
            or v_has_hr_site_connect_lead
            or v_has_hr_executive_lead
            or v_has_hr_lead
            or (
                v_has_hr_site_connect
                and exists (
                    select 1
                    from public.pod_memberships pm
                    where pm.user_id = v_actor_user_id
                      and pm.pod_id = action_queue.pod_id
                      and pm.candidate_id is null
                      and pm.membership_type = 'HR_SITE_CONNECT'
                      and pm.is_active = true
                      and pm.effective_from <= current_date
                      and (
                          pm.effective_to is null
                          or pm.effective_to >= current_date
                      )
                )
            )
        )
    )
    or (
        action_queue.action_code = 'SUBMIT_EXCEPTIONAL_SCORE'
        and (
            v_has_hr_site_connect_lead
            or v_has_hr_executive_lead
            or v_has_hr_lead
            or (
                v_has_hr_site_connect
                and exists (
                    select 1
                    from public.pod_memberships pm
                    where pm.user_id = v_actor_user_id
                      and pm.pod_id = action_queue.pod_id
                      and pm.candidate_id is null
                      and pm.membership_type = 'HR_SITE_CONNECT'
                      and pm.is_active = true
                      and pm.effective_from <= v_business_date
                      and (
                          pm.effective_to is null
                          or pm.effective_to >= v_business_date
                      )
                )
            )
        )
    )
    or (
        action_queue.action_code = 'FINALIZE_RESULT'
        and v_has_hr_site_connect_lead
    )
    order by
        action_queue.is_overdue desc,
        action_queue.due_date asc,
        action_queue.full_name asc,
        action_queue.action_code asc,
        action_queue.action_key asc;
end;
$function$;

comment on function public.get_performance_action_queue() is
    'Returns only performance action rows that the active actor is authorized to handle. Lead actions reuse the Lead Review task authorization, HR actions preserve their write-role and pod models, and this function performs no action or write.';

revoke execute on function public.get_performance_action_queue() from public;
revoke execute on function public.get_performance_action_queue() from anon;
grant execute on function public.get_performance_action_queue() to authenticated;
grant execute on function public.get_performance_action_queue() to service_role;

create or replace function public.get_candidate_daily_performance_entries(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    cycle_id uuid,
    cycle_code text,
    cycle_status text,
    pod_id uuid,
    pod_code text,
    pod_name text,
    evaluation_start_date date,
    evaluation_end_date date,
    result_status text,
    eligible_days integer,
    performance_date date,
    is_scorable boolean,
    exclusion_reason text,
    entry_id uuid,
    work_delivery_score smallint,
    communication_responsibility_score smallint,
    daily_total smallint,
    reason_code text,
    reviewer_comment text,
    reviewer_user_id uuid,
    reviewer_name text,
    submitted_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_actor_user_id uuid := public.current_app_user_id();
    v_has_elevated_access boolean;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
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
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.id as candidate_cycle_id,
            cpc.candidate_id,
            mc.full_name,
            cpc.cycle_id,
            pc.cycle_code,
            pc.cycle_status,
            cpc.pod_id,
            p.pod_code,
            p.pod_name,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.result_status,
            cpc.eligible_days
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
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE',
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
           where pm.user_id = v_actor_user_id
             and pm.pod_id = v_assignment.pod_id
             and (
                 (
                     pm.membership_type = 'HR_SITE_CONNECT'
                     and public.current_user_has_role('HR_SITE_CONNECT')
                 )
             )
             and pm.is_active = true
             and pm.effective_from <= v_business_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= v_business_date
             )
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance access is not available.';
    end if;

    return query
    with generated_dates as (
        select
            (
                v_assignment.evaluation_start_date
                + generated.day_offset
            )::date as generated_date
        from pg_catalog.generate_series(
            0,
            v_assignment.evaluation_end_date
                - v_assignment.evaluation_start_date
        ) as generated(day_offset)
    ),
    date_eligibility as (
        select
            generated_dates.generated_date,
            extract(isodow from generated_dates.generated_date) = 7
                as is_sunday,
            exists (
                select 1
                from public.leave_requests lr
                where lr.candidate_id = v_assignment.candidate_id
                  and lr.leave_status = 'APPROVED'
                  and generated_dates.generated_date
                      between lr.start_date and lr.end_date
                  and lower(btrim(lr.leave_type)) <> 'work from home'
            ) as has_approved_leave
        from generated_dates
    )
    select
        v_assignment.candidate_cycle_id::uuid,
        v_assignment.candidate_id::uuid,
        v_assignment.full_name::text,
        v_assignment.cycle_id::uuid,
        v_assignment.cycle_code::text,
        v_assignment.cycle_status::text,
        v_assignment.pod_id::uuid,
        v_assignment.pod_code::text,
        v_assignment.pod_name::text,
        v_assignment.evaluation_start_date::date,
        v_assignment.evaluation_end_date::date,
        v_assignment.result_status::text,
        v_assignment.eligible_days::integer,
        eligibility.generated_date,
        not (
            eligibility.is_sunday
            or eligibility.has_approved_leave
            or eligibility.generated_date > current_date
        ) as is_scorable,
        case
            when eligibility.is_sunday then 'SUNDAY'::text
            when eligibility.has_approved_leave then 'APPROVED_LEAVE'::text
            when eligibility.generated_date > current_date then 'FUTURE_DATE'::text
            else null::text
        end as exclusion_reason,
        dpe.id,
        dpe.work_delivery_score,
        dpe.communication_responsibility_score,
        dpe.daily_total,
        dpe.reason_code,
        dpe.reviewer_comment,
        dpe.reviewer_user_id,
        reviewer.name::text,
        dpe.submitted_at,
        dpe.created_at,
        dpe.updated_at
    from date_eligibility eligibility
    left join public.daily_performance_entries dpe
        on dpe.candidate_cycle_id = v_assignment.candidate_cycle_id
       and dpe.performance_date = eligibility.generated_date
    left join public.users reviewer
        on reviewer.id = dpe.reviewer_user_id
    order by eligibility.generated_date;
end;
$function$;

comment on function
    public.get_candidate_daily_performance_entries(uuid) is
    'Returns the complete inclusive evaluation-date marking grid and stored cycle summary fields for one candidate performance cycle, including scorable-day eligibility and existing daily marks. Access is read-only and limited to active authorized performance users; reviewer email addresses are not exposed.';

revoke execute on function
    public.get_candidate_daily_performance_entries(uuid)
from public;

revoke execute on function
    public.get_candidate_daily_performance_entries(uuid)
from anon;

grant execute on function
    public.get_candidate_daily_performance_entries(uuid)
to authenticated;

grant execute on function
    public.get_candidate_daily_performance_entries(uuid)
to service_role;

commit;
