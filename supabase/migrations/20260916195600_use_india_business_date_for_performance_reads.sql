begin;

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
               'HR_LEAD',
               'TECH_LEAD'
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
              or (
                  pm.membership_type = 'TECH_LEAD'
                  and public.current_user_has_role('TECH_LEAD')
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
    'Returns the read-only performance-cycle overview to active authenticated HR users with an approved dashboard role. It performs no performance write or workflow action.';

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
               'HR_LEAD',
               'TECH_LEAD'
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
                 or (
                     pm.membership_type = 'TECH_LEAD'
                     and public.current_user_has_role('TECH_LEAD')
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
    'Returns the read-only candidate performance list to active authenticated HR users with an approved dashboard role. It performs no scoring, review, calculation, finalization, locking, or other write action.';

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
    v_has_elevated_access boolean;
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
           array[
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE',
               'HR_EXECUTIVE_LEAD',
               'HR_LEAD',
               'TECH_LEAD'
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
    select action_queue.*
    from public.performance_action_queue_view action_queue
    where v_has_elevated_access
       or exists (
           select 1
           from public.pod_memberships pm
           where pm.user_id = v_actor_user_id
             and pm.pod_id = action_queue.pod_id
             and (
                 (
                     pm.membership_type = 'HR_SITE_CONNECT'
                     and public.current_user_has_role('HR_SITE_CONNECT')
                 )
                 or (
                     pm.membership_type = 'TECH_LEAD'
                     and public.current_user_has_role('TECH_LEAD')
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
        action_queue.is_overdue desc,
        action_queue.due_date asc,
        action_queue.full_name asc,
        action_queue.action_code asc,
        action_queue.action_key asc;
end;
$function$;

comment on function public.get_performance_action_queue() is
    'Returns the read-only performance action queue to active authenticated HR users with an approved dashboard role. Queue rows describe outstanding work but this function performs no action or write.';

revoke execute on function public.get_performance_action_queue() from public;
revoke execute on function public.get_performance_action_queue() from anon;
grant execute on function public.get_performance_action_queue() to authenticated;
grant execute on function public.get_performance_action_queue() to service_role;

commit;
