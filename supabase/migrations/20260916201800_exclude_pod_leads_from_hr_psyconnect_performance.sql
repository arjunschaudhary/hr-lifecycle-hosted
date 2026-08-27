begin;

-- Exclude active/effective Pod Lead candidates from pure HR Psyconnect
-- performance handling while preserving every existing elevated HR path.

-- Pure HR Psyconnect users must not manage the active Pod Lead candidate
-- for a historical candidate-cycle pod. This internal predicate uses only
-- linked application identity, active authorization, and effective membership.
create or replace function public.candidate_is_active_pod_lead_for_performance(
    p_candidate_id uuid,
    p_pod_id uuid,
    p_business_date date
)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    select exists (
        select 1
        from public.candidate_user_accounts cua
        join public.user_roles ur
            on ur.user_id = cua.user_id
        join public.roles r
            on r.id = ur.role_id
           and r.slug = 'POD_LEAD'
           and r.is_active = true
        join public.pod_memberships pm
            on pm.user_id = cua.user_id
           and pm.pod_id = p_pod_id
           and pm.membership_type = 'POD_LEAD'
           and pm.is_active = true
           and pm.effective_from <= p_business_date
           and (
               pm.effective_to is null
               or pm.effective_to >= p_business_date
           )
        where cua.candidate_id = p_candidate_id
          and ur.is_active = true
          and ur.ended_at is null
    );
$function$;

comment on function public.candidate_is_active_pod_lead_for_performance(
    uuid,
    uuid,
    date
) is
    'Internal authorization predicate that identifies an active/effective Pod Lead candidate for the supplied historical candidate-cycle pod and India business date.';

revoke execute on function public.candidate_is_active_pod_lead_for_performance(
    uuid,
    uuid,
    date
) from public;

revoke execute on function public.candidate_is_active_pod_lead_for_performance(
    uuid,
    uuid,
    date
) from anon;

revoke execute on function public.candidate_is_active_pod_lead_for_performance(
    uuid,
    uuid,
    date
) from authenticated;

grant execute on function public.candidate_is_active_pod_lead_for_performance(
    uuid,
    uuid,
    date
) to service_role;

create or replace function public.get_performance_cycle_overview()
returns setof public.performance_cycle_overview_view
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid := public.current_app_user_id();
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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
      and not public.candidate_is_active_pod_lead_for_performance(
          cpc.candidate_id,
          cpc.pod_id,
          v_business_date
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
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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
       or (
           exists (
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
           and not public.candidate_is_active_pod_lead_for_performance(
               candidate_performance.candidate_id,
               candidate_performance.pod_id,
               v_business_date
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
    v_apply_pod_lead_exclusion boolean;
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
    v_apply_pod_lead_exclusion :=
        v_has_hr_site_connect
        and not coalesce(
            public.current_user_has_any_role(
                array[
                    'ADMIN',
                    'HR_SITE_CONNECT_LEAD',
                    'HR_EXECUTIVE',
                    'HR_EXECUTIVE_LEAD',
                    'HR_LEAD'
                ]::text[]
            ),
            false
        );

    return query
    select action_queue.*
    from public.performance_action_queue_view action_queue
    where (
        not v_apply_pod_lead_exclusion
        or not public.candidate_is_active_pod_lead_for_performance(
            action_queue.candidate_id,
            action_queue.pod_id,
            v_business_date
        )
    )
    and (
        (
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

    if not v_has_elevated_access
       and public.candidate_is_active_pod_lead_for_performance(
           v_assignment.candidate_id,
           v_assignment.pod_id,
           v_business_date
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR Psyconnect cannot manage performance for the Pod Lead of this pod.';
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
    v_is_pure_hr_site_connect boolean;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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

    v_is_pure_hr_site_connect :=
        coalesce(public.current_user_has_role('HR_SITE_CONNECT'), false)
        and not coalesce(
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

    if not v_has_elevated_access
       and v_is_pure_hr_site_connect
       and public.candidate_is_active_pod_lead_for_performance(
           v_assignment.candidate_id,
           v_assignment.pod_id,
           v_business_date
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR Psyconnect cannot manage performance for the Pod Lead of this pod.';
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
        from public.advance_candidate_cycle_performance(
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

create or replace function public.get_hr_review_tasks()
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
    review_open_date date,
    lock_date date,
    cycle_status text,
    pod_id uuid,
    pod_code text,
    pod_name text,
    evaluation_start_date date,
    evaluation_end_date date,
    is_partial_cycle boolean,
    result_status text,
    eligible_days integer,
    scored_days integer,
    daily_component_score numeric,
    daily_scoring_complete boolean,
    review_is_open boolean,
    review_id uuid,
    review_status text,
    task_status text,
    reviewer_user_id uuid,
    reviewer_name text,
    communication_professionalism_score smallint,
    attendance_update_discipline_score smallint,
    reporting_policy_compliance_score smallint,
    total_score smallint,
    reviewer_comment text,
    submitted_at timestamptz,
    review_created_at timestamptz,
    review_updated_at timestamptz,
    can_edit boolean
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_current_user_id uuid;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_has_elevated_access boolean;
    v_is_pure_hr_site_connect boolean;
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
            message = 'HR review workspace access is not available.';
    end if;

    v_current_user_id := public.current_app_user_id();

    if v_current_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'HR review workspace access is not available.';
    end if;

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

    v_is_pure_hr_site_connect :=
        coalesce(public.current_user_has_role('HR_SITE_CONNECT'), false)
        and not coalesce(
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
    select
        cpc.id::uuid as candidate_cycle_id,
        cpc.candidate_id::uuid,
        mc.full_name::text,
        mc.email::text,
        mc.applied_role::text,
        mc.role_code::text,
        cpc.cycle_id::uuid,
        pc.cycle_code::text,
        pc.cycle_number::integer,
        pc.start_date::date as cycle_start_date,
        pc.end_date::date as cycle_end_date,
        pc.review_open_date::date,
        pc.lock_date::date,
        pc.cycle_status::text,
        cpc.pod_id::uuid,
        p.pod_code::text,
        p.pod_name::text,
        cpc.evaluation_start_date::date,
        cpc.evaluation_end_date::date,
        cpc.is_partial_cycle::boolean,
        cpc.result_status::text,
        cpc.eligible_days::integer,
        cpc.scored_days::integer,
        cpc.daily_component_score::numeric,
        review_state.daily_scoring_complete,
        review_state.review_is_open,
        pr.id::uuid as review_id,
        pr.review_status::text,
        case
            when review_state.is_protected then 'PROTECTED'
            when pr.review_status = 'SUBMITTED' then 'SUBMITTED'
            when pr.review_status = 'DRAFT' then 'DRAFT'
            when not review_state.daily_scoring_complete then
                'WAITING_FOR_DAILY_SCORING'
            when not review_state.review_is_open then 'NOT_OPEN'
            else 'READY'
        end::text as task_status,
        pr.reviewer_user_id::uuid,
        reviewer.name::text as reviewer_name,
        pr.communication_professionalism_score::smallint,
        pr.attendance_update_discipline_score::smallint,
        pr.reporting_policy_compliance_score::smallint,
        pr.total_score::smallint,
        pr.reviewer_comment::text,
        pr.submitted_at::timestamptz,
        pr.created_at::timestamptz as review_created_at,
        pr.updated_at::timestamptz as review_updated_at,
        (
            review_state.daily_scoring_complete
            and review_state.review_is_open
            and not review_state.is_protected
        ) as can_edit
    from public.candidate_performance_cycles cpc
    join public.master_candidates mc
        on mc.candidate_id = cpc.candidate_id
    join public.performance_cycles pc
        on pc.id = cpc.cycle_id
    join public.pods p
        on p.id = cpc.pod_id
    cross join lateral (
        select
            (
                cpc.eligible_days > 0
                and cpc.scored_days = cpc.eligible_days
                and cpc.daily_component_score is not null
            ) as daily_scoring_complete,
            (
                current_date >= pc.review_open_date
                and pc.cycle_status not in (
                    'DRAFT',
                    'FINALIZED',
                    'LOCKED'
                )
                and cpc.result_status not in (
                    'FINALIZED',
                    'LOCKED'
                )
            ) as review_is_open,
            (
                pc.cycle_status in ('FINALIZED', 'LOCKED')
                or cpc.result_status in ('FINALIZED', 'LOCKED')
            ) as is_protected
    ) review_state
    left join public.performance_reviews pr
        on pr.candidate_cycle_id = cpc.id
       and pr.review_type = 'HR'
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id
    where v_has_elevated_access
       or (
           exists (
               select 1
               from public.pod_memberships pm
               where pm.user_id = v_current_user_id
                 and pm.pod_id = cpc.pod_id
                 and pm.candidate_id is null
                 and pm.membership_type = 'HR_SITE_CONNECT'
                 and pm.is_active = true
                 and pm.effective_from <= current_date
                 and (
                     pm.effective_to is null
                     or pm.effective_to >= current_date
                 )
           )
           and (
               not v_is_pure_hr_site_connect
               or not public.candidate_is_active_pod_lead_for_performance(
                   cpc.candidate_id,
                   cpc.pod_id,
                   v_business_date
               )
           )
       )
    order by
        pc.review_open_date desc,
        p.pod_name asc,
        mc.full_name asc,
        cpc.id asc;
end;
$function$;

comment on function public.get_hr_review_tasks() is
    'Returns pod-scoped HR Review tasks to plain active HR_SITE_CONNECT users and organization-wide tasks to active elevated HR reviewers. It exposes only HR Review fields and performs no write action.';

revoke execute on function public.get_hr_review_tasks() from public;
revoke execute on function public.get_hr_review_tasks() from anon;
grant execute on function public.get_hr_review_tasks() to authenticated;
grant execute on function public.get_hr_review_tasks() to service_role;

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
    v_is_pure_hr_site_connect boolean;
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

    v_is_pure_hr_site_connect :=
        coalesce(public.current_user_has_role('HR_SITE_CONNECT'), false)
        and not coalesce(
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

    if not v_has_elevated_access
       and v_is_pure_hr_site_connect
       and public.candidate_is_active_pod_lead_for_performance(
           v_assignment.candidate_id,
           v_assignment.pod_id,
           v_business_date
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR Psyconnect cannot manage performance for the Pod Lead of this pod.';
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

create or replace function public.save_candidate_hr_review(
    p_candidate_cycle_id uuid,
    p_communication_professionalism_score smallint,
    p_attendance_update_discipline_score smallint,
    p_reporting_policy_compliance_score smallint,
    p_reviewer_comment text,
    p_review_status text,
    p_amendment_reason text default null
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
    v_amendment_reason text;
    v_review_id uuid;
    v_revision_id uuid;
    v_new_total_score smallint;
    v_new_submitted_at timestamptz;
    v_old_review_status text;
    v_old_communication_professionalism_score smallint;
    v_old_attendance_update_discipline_score smallint;
    v_old_reporting_policy_compliance_score smallint;
    v_old_total_score smallint;
    v_old_reviewer_comment text;
    v_hr_score numeric;
    v_old_result_status text;
    v_new_result_status text;
    v_operation text;
    v_activity_type text;
    v_remarks text;
    v_save_timestamp timestamptz := now();
    v_review_exists boolean;
    v_is_amendment boolean;
    v_hr_total_changed boolean := false;
    v_has_elevated_access boolean;
    v_is_pure_hr_site_connect boolean;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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
            message = 'HR review marking access is not available.';
    end if;

    v_reviewer_user_id := public.current_app_user_id();

    if v_reviewer_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'HR review marking access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_review_status := upper(btrim(p_review_status));
    v_reviewer_comment := nullif(btrim(p_reviewer_comment), '');

    if v_reviewer_comment is null then
        raise exception 'Reviewer comment is required.'
            using errcode = '23514';
    end if;

    v_amendment_reason := nullif(btrim(p_amendment_reason), '');

    if v_review_status is null
       or v_review_status not in ('DRAFT', 'SUBMITTED') then
        raise exception 'Review status must be DRAFT or SUBMITTED.'
            using errcode = '22023';
    end if;

    if p_communication_professionalism_score is not null
       and p_communication_professionalism_score not between 0 and 5 then
        raise exception
            'Communication and professionalism score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_attendance_update_discipline_score is not null
       and p_attendance_update_discipline_score not between 0 and 5 then
        raise exception
            'Attendance and update discipline score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_reporting_policy_compliance_score is not null
       and p_reporting_policy_compliance_score not between 0 and 5 then
        raise exception
            'Reporting and policy compliance score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if v_review_status = 'SUBMITTED'
       and (
           p_communication_professionalism_score is null
           or p_attendance_update_discipline_score is null
           or p_reporting_policy_compliance_score is null
       ) then
        raise exception 'All HR review scores are required for submission.'
            using errcode = '23514';
    end if;

    if char_length(v_reviewer_comment) > 2000 then
        raise exception 'Reviewer comment must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    if char_length(v_amendment_reason) > 2000 then
        raise exception 'Amendment reason must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'performance-review:'
                || p_candidate_cycle_id::text
                || ':HR',
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
            cpc.hr_score,
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

    v_is_pure_hr_site_connect :=
        coalesce(public.current_user_has_role('HR_SITE_CONNECT'), false)
        and not coalesce(
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
           where pm.user_id = v_reviewer_user_id
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
            message = 'HR review marking access is not available.';
    end if;

    if not v_has_elevated_access
       and v_is_pure_hr_site_connect
       and public.candidate_is_active_pod_lead_for_performance(
           v_assignment.candidate_id,
           v_assignment.pod_id,
           v_business_date
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR Psyconnect cannot manage performance for the Pod Lead of this pod.';
    end if;

    if v_assignment.eligible_days <= 0 then
        raise exception 'HR review requires eligible performance days.'
            using errcode = '55000';
    end if;

    if v_assignment.scored_days
       is distinct from v_assignment.eligible_days
       or v_assignment.daily_component_score is null then
        raise exception
            'Daily performance scoring must be complete before HR review.'
            using errcode = '55000';
    end if;

    if current_date < v_assignment.review_open_date then
        raise exception 'HR review is not open yet.'
            using errcode = '55000';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'HR review is not available for this cycle status.'
            using errcode = '55000';
    end if;

    if v_assignment.result_status in ('FINALIZED', 'LOCKED') then
        raise exception
            'HR review is not available for this result status.'
            using errcode = '55000';
    end if;

    select pr.*
    into v_existing_review
    from public.performance_reviews pr
    where pr.candidate_cycle_id = p_candidate_cycle_id
      and pr.review_type = 'HR'
    for update;

    v_review_exists := found;
    v_is_amendment :=
        v_review_exists
        and v_existing_review.review_status = 'SUBMITTED';

    if v_is_amendment then
        if v_amendment_reason is null then
            raise exception
                'An amendment reason is required to change a submitted HR review.'
                using errcode = '23514';
        end if;

        if p_communication_professionalism_score is null
           or p_attendance_update_discipline_score is null
           or p_reporting_policy_compliance_score is null then
            raise exception 'All HR review scores are required for submission.'
                using errcode = '23514';
        end if;

        v_review_status := 'SUBMITTED';
    end if;

    if v_review_exists then
        v_old_review_status := v_existing_review.review_status;
        v_old_communication_professionalism_score :=
            v_existing_review.communication_professionalism_score;
        v_old_attendance_update_discipline_score :=
            v_existing_review.attendance_update_discipline_score;
        v_old_reporting_policy_compliance_score :=
            v_existing_review.reporting_policy_compliance_score;
        v_old_total_score := v_existing_review.total_score;
        v_old_reviewer_comment := v_existing_review.reviewer_comment;
    end if;

    if v_is_amendment then
        v_operation := 'AMENDED';
        v_activity_type := 'HR_REVIEW_AMENDED';
        v_remarks := 'Submitted HR performance review amended.';
    elsif v_review_status = 'SUBMITTED' then
        v_operation := 'SUBMITTED';
        v_activity_type := 'HR_REVIEW_SUBMITTED';
        v_remarks := 'HR performance review submitted.';
    else
        v_operation := 'DRAFT_SAVED';
        v_activity_type := 'HR_REVIEW_DRAFT_SAVED';
        v_remarks := 'HR performance review draft saved.';
    end if;

    if v_review_exists then
        update public.performance_reviews
        set
            reviewer_user_id = v_reviewer_user_id,
            communication_professionalism_score =
                p_communication_professionalism_score,
            attendance_update_discipline_score =
                p_attendance_update_discipline_score,
            reporting_policy_compliance_score =
                p_reporting_policy_compliance_score,
            reviewer_comment = v_reviewer_comment,
            review_status = v_review_status,
            submitted_at = case
                when v_is_amendment then v_existing_review.submitted_at
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
            communication_professionalism_score,
            attendance_update_discipline_score,
            reporting_policy_compliance_score,
            reviewer_comment,
            review_status,
            submitted_at,
            created_at,
            updated_at
        )
        values (
            p_candidate_cycle_id,
            'HR',
            v_reviewer_user_id,
            p_communication_professionalism_score,
            p_attendance_update_discipline_score,
            p_reporting_policy_compliance_score,
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

    if v_new_total_score not between 0 and 15 then
        raise exception 'HR review total must be between 0 and 15.'
            using errcode = '22003';
    end if;

    if v_is_amendment then
        v_hr_total_changed :=
            v_old_total_score is distinct from v_new_total_score;

        insert into public.performance_review_revisions (
            performance_review_id,
            candidate_cycle_id,
            review_type,
            previous_scores,
            new_scores,
            previous_total_score,
            new_total_score,
            amendment_reason,
            amended_by,
            amended_at,
            created_at
        )
        values (
            v_review_id,
            p_candidate_cycle_id,
            'HR',
            jsonb_build_object(
                'communication_professionalism_score',
                    v_old_communication_professionalism_score,
                'attendance_update_discipline_score',
                    v_old_attendance_update_discipline_score,
                'reporting_policy_compliance_score',
                    v_old_reporting_policy_compliance_score
            ),
            jsonb_build_object(
                'communication_professionalism_score',
                    p_communication_professionalism_score,
                'attendance_update_discipline_score',
                    p_attendance_update_discipline_score,
                'reporting_policy_compliance_score',
                    p_reporting_policy_compliance_score
            ),
            v_old_total_score,
            v_new_total_score,
            v_amendment_reason,
            v_reviewer_user_id,
            v_save_timestamp,
            v_save_timestamp
        )
        returning id into v_revision_id;
    end if;

    v_old_result_status := v_assignment.result_status;

    if v_review_status = 'SUBMITTED' then
        begin
            select review_summary.hr_score
            into strict v_hr_score
            from public.refresh_candidate_cycle_review_summary(
                p_candidate_cycle_id
            ) as review_summary;
        exception
            when no_data_found then
                raise exception 'Review summary refresh returned no result.';
            when too_many_rows then
                raise exception 'Review summary refresh returned multiple results.';
        end;

        if v_is_amendment and v_hr_total_changed then
            update public.candidate_performance_cycles
            set
                final_score = null,
                performance_band = null,
                calculated_at = null
            where id = p_candidate_cycle_id;
        end if;

        begin
            select
                status_refresh.old_status,
                status_refresh.new_status
            into strict
                v_old_result_status,
                v_new_result_status
            from public.advance_candidate_cycle_performance(
                p_candidate_cycle_id
            ) as status_refresh;
        exception
            when no_data_found then
                raise exception 'Performance status refresh returned no result.';
            when too_many_rows then
                raise exception 'Performance status refresh returned multiple results.';
        end;
    else
        v_hr_score := v_assignment.hr_score;
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
            'revision_id', v_revision_id,
            'review_type', 'HR',
            'old_review_status', v_old_review_status,
            'new_review_status', v_review_status,
            'old_communication_professionalism_score',
                v_old_communication_professionalism_score,
            'new_communication_professionalism_score',
                p_communication_professionalism_score,
            'old_attendance_update_discipline_score',
                v_old_attendance_update_discipline_score,
            'new_attendance_update_discipline_score',
                p_attendance_update_discipline_score,
            'old_reporting_policy_compliance_score',
                v_old_reporting_policy_compliance_score,
            'new_reporting_policy_compliance_score',
                p_reporting_policy_compliance_score,
            'old_total_score', v_old_total_score,
            'new_total_score', v_new_total_score,
            'old_reviewer_comment', v_old_reviewer_comment,
            'new_reviewer_comment', v_reviewer_comment,
            'amendment_reason', v_amendment_reason,
            'reviewer_user_id', v_reviewer_user_id,
            'hr_score', v_hr_score
        ),
        v_reviewer_user_id::text,
        v_save_timestamp,
        v_save_timestamp,
        v_save_timestamp
    );

    return jsonb_build_object(
        'reviewId', v_review_id,
        'revisionId', v_revision_id,
        'candidateCycleId', p_candidate_cycle_id,
        'candidateId', v_assignment.candidate_id,
        'podId', v_assignment.pod_id,
        'reviewStatus', v_review_status,
        'communicationProfessionalismScore',
            p_communication_professionalism_score,
        'attendanceUpdateDisciplineScore',
            p_attendance_update_discipline_score,
        'reportingPolicyComplianceScore',
            p_reporting_policy_compliance_score,
        'totalScore', v_new_total_score,
        'reviewerComment', v_reviewer_comment,
        'amendmentReason', v_amendment_reason,
        'reviewerUserId', v_reviewer_user_id,
        'reviewerName', v_reviewer_name,
        'submittedAt', v_new_submitted_at,
        'hrScore', v_hr_score,
        'oldResultStatus', v_old_result_status,
        'newResultStatus', v_new_result_status,
        'operation', v_operation
    );
end;
$function$;

comment on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) is
    'Creates or updates an HR Review draft, submits a complete HR Review, or amends a submitted HR Review with a required audit reason. Submission and amendment refresh the stored HR summary and result status and record permanent audit history atomically.';

revoke execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) from public;

revoke execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) from anon;

grant execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) to authenticated;

grant execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) to service_role;

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
    v_is_pure_hr_site_connect boolean;
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

    v_is_pure_hr_site_connect :=
        coalesce(public.current_user_has_role('HR_SITE_CONNECT'), false)
        and not coalesce(
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

    if not v_has_elevated_access
       and v_is_pure_hr_site_connect
       and public.candidate_is_active_pod_lead_for_performance(
           v_assignment.candidate_id,
           v_assignment.pod_id,
           v_business_date
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR Psyconnect cannot manage performance for the Pod Lead of this pod.';
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
