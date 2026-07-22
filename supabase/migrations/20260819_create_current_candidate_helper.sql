create or replace function public.current_candidate_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    select cua.candidate_id
    from public.candidate_user_accounts cua
    where cua.user_id = public.current_app_user_id()
      and cua.account_status = 'ACTIVE'
      and cua.deactivated_at is null
      and cua.activated_at <= pg_catalog.now();
$function$;

comment on function public.current_candidate_id() is
    'Resolves the active candidate or intern record for the current authenticated application user. public.candidate_user_accounts is the authorization mapping, email matching is not used, and this helper is intended for RLS policies and secure self-service actions.';

revoke execute on function public.current_candidate_id() from public;
revoke execute on function public.current_candidate_id() from anon;
grant execute on function public.current_candidate_id() to authenticated;
grant execute on function public.current_candidate_id() to service_role;
