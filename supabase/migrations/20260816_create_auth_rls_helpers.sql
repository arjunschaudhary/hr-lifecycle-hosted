create or replace function public.current_app_user_id()
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    select u.id
    from public.users u
    where u.id = auth.uid()
      and u.status = 'active';
$function$;

comment on function public.current_app_user_id() is
    'Returns the active application user matching auth.uid(), or null when no active application user exists. public.user_roles is the permission source of truth, public.users.role_id is not used for authorization, and this helper is intended for RLS policy expressions.';

revoke execute on function public.current_app_user_id() from public;
revoke execute on function public.current_app_user_id() from anon;
grant execute on function public.current_app_user_id() to authenticated;
grant execute on function public.current_app_user_id() to service_role;

create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    select public.current_app_user_id() is not null;
$function$;

comment on function public.current_user_is_active() is
    'Identifies whether auth.uid() maps to an active application user. public.user_roles is the permission source of truth, public.users.role_id is not used for authorization, and this helper is intended for RLS policy expressions.';

revoke execute on function public.current_user_is_active() from public;
revoke execute on function public.current_user_is_active() from anon;
grant execute on function public.current_user_is_active() to authenticated;
grant execute on function public.current_user_is_active() to service_role;

create or replace function public.current_user_has_role(p_role_slug text)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    select case
        when p_role_slug is null
             or pg_catalog.btrim(p_role_slug) = '' then false
        else exists (
            select 1
            from public.user_roles ur
            join public.roles r
                on r.id = ur.role_id
            where ur.user_id = public.current_app_user_id()
              and ur.is_active = true
              and ur.ended_at is null
              and r.is_active = true
              and r.slug = pg_catalog.upper(pg_catalog.btrim(p_role_slug))
        )
    end;
$function$;

comment on function public.current_user_has_role(text) is
    'Checks whether the active application user has one explicit active role slug after trimming and uppercasing the supplied value. public.user_roles is the permission source of truth, public.users.role_id is not used for authorization, and this helper is intended for RLS policy expressions.';

revoke execute on function public.current_user_has_role(text) from public;
revoke execute on function public.current_user_has_role(text) from anon;
grant execute on function public.current_user_has_role(text) to authenticated;
grant execute on function public.current_user_has_role(text) to service_role;

create or replace function public.current_user_has_any_role(p_role_slugs text[])
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    with current_user_context as (
        select public.current_app_user_id() as user_id
    ),
    normalized_roles as (
        select pg_catalog.upper(pg_catalog.btrim(supplied.role_slug)) as role_slug
        from pg_catalog.unnest(p_role_slugs) as supplied(role_slug)
        where supplied.role_slug is not null
          and pg_catalog.btrim(supplied.role_slug) <> ''
    )
    select exists (
        select 1
        from current_user_context app_user
        join public.user_roles ur
            on ur.user_id = app_user.user_id
        join public.roles r
            on r.id = ur.role_id
        join normalized_roles supplied_role
            on supplied_role.role_slug = r.slug
        where app_user.user_id is not null
          and ur.is_active = true
          and ur.ended_at is null
          and r.is_active = true
    );
$function$;

comment on function public.current_user_has_any_role(text[]) is
    'Checks whether the active application user has at least one role from a supplied set of explicit active role slugs, ignoring null and blank elements and normalizing usable values. public.user_roles is the permission source of truth, public.users.role_id is not used for authorization, and this set-based helper is intended for RLS policy expressions.';

revoke execute on function public.current_user_has_any_role(text[]) from public;
revoke execute on function public.current_user_has_any_role(text[]) from anon;
grant execute on function public.current_user_has_any_role(text[]) to authenticated;
grant execute on function public.current_user_has_any_role(text[]) to service_role;

create or replace function public.current_user_has_pod_access(p_pod_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    with current_user_context as (
        select public.current_app_user_id() as user_id
    )
    select exists (
        select 1
        from current_user_context app_user
        join public.pod_memberships pm
            on pm.user_id = app_user.user_id
        join public.user_roles ur
            on ur.user_id = pm.user_id
        join public.roles r
            on r.id = ur.role_id
           and r.slug = pm.membership_type
        where p_pod_id is not null
          and app_user.user_id is not null
          and pm.pod_id = p_pod_id
          and pm.candidate_id is null
          and pm.is_active = true
          and pm.effective_from <= current_date
          and (
              pm.effective_to is null
              or pm.effective_to >= current_date
          )
          and pm.membership_type in (
              'TEAM_LEAD',
              'TECH_LEAD',
              'POD_LEAD',
              'HR_SITE_CONNECT'
          )
          and ur.is_active = true
          and ur.ended_at is null
          and r.is_active = true
    );
$function$;

comment on function public.current_user_has_pod_access(uuid) is
    'Checks whether the active application user has both a matching active role and an effective active reviewer membership for the supplied pod. public.user_roles is the permission source of truth, public.users.role_id is not used for authorization, and this helper is intended for RLS policy expressions.';

revoke execute on function public.current_user_has_pod_access(uuid) from public;
revoke execute on function public.current_user_has_pod_access(uuid) from anon;
grant execute on function public.current_user_has_pod_access(uuid) to authenticated;
grant execute on function public.current_user_has_pod_access(uuid) to service_role;
