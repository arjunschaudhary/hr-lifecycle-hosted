begin;

create or replace function public.get_performance_cycle_overview()
returns setof public.performance_cycle_overview_view
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
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

    return query
    select overview.*
    from public.performance_cycle_overview_view overview
    order by
        overview.cycle_number desc,
        overview.cycle_id desc;
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

    return query
    select candidate_performance.*
    from public.candidate_performance_list_view candidate_performance
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

    return query
    select action_queue.*
    from public.performance_action_queue_view action_queue
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
