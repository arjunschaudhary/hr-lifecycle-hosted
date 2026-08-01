begin;

-- Fail explicitly instead of silently resolving duplicate active reviewers.
do $preflight$
begin
    if exists (
        select 1
        from public.pod_memberships pm
        where pm.is_active = true
          and pm.membership_type = 'HR_SITE_CONNECT'
          and pm.user_id is not null
        group by pm.pod_id
        having count(*) > 1
    ) then
        raise exception using
            errcode = '23505',
            message = 'Cannot enforce one active HR Psyconnect reviewer per pod because duplicate active reviewer memberships exist.';
    end if;
end;
$preflight$;

create unique index if not exists
    uq_pod_memberships_active_hr_site_connect_per_pod
on public.pod_memberships (pod_id)
where is_active = true
  and membership_type = 'HR_SITE_CONNECT'
  and user_id is not null;

-- Reviewer assignments are staff-only pod events and therefore do not have a
-- candidate identity. All other activity types retain the candidate requirement.
alter table public.hr_activity_logs
    drop constraint if exists hr_activity_logs_candidate_required_check;

alter table public.hr_activity_logs
    add constraint hr_activity_logs_candidate_required_check
    check (
        candidate_id is not null
        or activity_type in (
            'POD_CREATED',
            'POD_UPDATED',
            'STAFF_POD_MEMBERSHIP_ENDED',
            'HR_SITE_CONNECT_POD_ASSIGNED'
        )
    );

create or replace function public.search_pod_management_hr_reviewers(
    p_search_term text default ''
)
returns table (
    user_id uuid,
    full_name text,
    email text,
    active_pod_count integer,
    active_pod_codes text[]
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_search_term text := btrim(coalesce(p_search_term, ''));
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT_LEAD']::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Pod Management access is not permitted.';
    end if;

    if char_length(v_search_term) > 150 then
        raise exception using
            errcode = '22023',
            message = 'HR Psyconnect reviewer search is too long.';
    end if;

    return query
    select
        u.id,
        u.name::text,
        u.email::text,
        count(distinct current_pod.id)::integer,
        coalesce(
            array_agg(
                distinct current_pod.pod_code::text
                order by current_pod.pod_code::text
            ) filter (where current_pod.id is not null),
            array[]::text[]
        )
    from public.users u
    left join public.pod_memberships pm
        on pm.user_id = u.id
       and pm.membership_type = 'HR_SITE_CONNECT'
       and pm.is_active = true
       and pm.effective_from <= current_date
       and (
           pm.effective_to is null
           or pm.effective_to >= current_date
       )
    left join public.pods current_pod
        on current_pod.id = pm.pod_id
       and current_pod.is_active = true
    where u.status = 'active'
      and exists (
          select 1
          from public.user_roles ur
          join public.roles r
              on r.id = ur.role_id
          where ur.user_id = u.id
            and ur.is_active = true
            and ur.ended_at is null
            and r.is_active = true
            and r.slug = 'HR_SITE_CONNECT'
      )
      and (
          v_search_term = ''
          or lower(u.name) like '%' || lower(v_search_term) || '%'
          or lower(u.email) like '%' || lower(v_search_term) || '%'
      )
    group by u.id, u.name, u.email
    order by lower(u.name), lower(u.email), u.id
    limit 50;
end;
$function$;

comment on function public.search_pod_management_hr_reviewers(text) is
    'Searches active HR_SITE_CONNECT users and returns only their current HR reviewer pod summaries to active authorized Pod Management users.';

create or replace function public.assign_hr_site_connect_to_pod(
    p_user_id uuid,
    p_pod_id uuid,
    p_effective_from date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_pod public.pods%rowtype;
    v_target_user public.users%rowtype;
    v_role_id uuid;
    v_existing_membership public.pod_memberships%rowtype;
    v_membership public.pod_memberships%rowtype;
    v_timestamp timestamptz := now();
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT_LEAD']::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Pod Management access is not permitted.';
    end if;

    if p_user_id is null or p_pod_id is null or p_effective_from is null then
        raise exception using
            errcode = '22004',
            message = 'HR Psyconnect reviewer assignment values are invalid.';
    end if;

    perform pg_advisory_xact_lock(
        hashtextextended('pod-hr-site-connect:' || p_pod_id::text, 0)
    );
    perform pg_advisory_xact_lock(
        hashtextextended('user-hr-site-connect:' || p_user_id::text, 0)
    );

    select p.*
    into v_pod
    from public.pods p
    where p.id = p_pod_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Pod was not found.';
    end if;

    if not v_pod.is_active then
        raise exception using
            errcode = 'P0001',
            message = 'HR Psyconnect reviewers cannot be assigned to an inactive pod.';
    end if;

    select u.*
    into v_target_user
    from public.users u
    where u.id = p_user_id
    for update;

    if not found or v_target_user.status is distinct from 'active' then
        raise exception using
            errcode = 'P0002',
            message = 'HR Psyconnect reviewer was not found.';
    end if;

    select r.id
    into v_role_id
    from public.roles r
    where r.slug = 'HR_SITE_CONNECT'
      and r.is_active = true;

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Target user does not have active HR_SITE_CONNECT access.';
    end if;

    perform 1
    from public.user_roles ur
    where ur.user_id = p_user_id
      and ur.role_id = v_role_id
    for update;

    if not exists (
        select 1
        from public.user_roles ur
        where ur.user_id = p_user_id
          and ur.role_id = v_role_id
          and ur.is_active = true
          and ur.ended_at is null
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Target user does not have active HR_SITE_CONNECT access.';
    end if;

    perform 1
    from public.pod_memberships pm
    where pm.pod_id = p_pod_id
      and pm.membership_type = 'HR_SITE_CONNECT'
    for update;

    select pm.*
    into v_existing_membership
    from public.pod_memberships pm
    where pm.pod_id = p_pod_id
      and pm.membership_type = 'HR_SITE_CONNECT'
      and pm.is_active = true
      and pm.user_id is not null
    order by pm.effective_from desc, pm.id desc
    limit 1;

    if v_existing_membership.id is not null then
        if v_existing_membership.user_id = p_user_id then
            return jsonb_build_object(
                'success', true,
                'operation', 'ASSIGN_HR_REVIEWER',
                'changed', false,
                'userId', p_user_id,
                'podId', p_pod_id,
                'membershipId', v_existing_membership.id,
                'membershipType', 'HR_SITE_CONNECT',
                'effectiveFrom', v_existing_membership.effective_from
            );
        end if;

        raise exception using
            errcode = '23505',
            message = 'Pod already has an active HR Psyconnect reviewer. End the current membership before assigning another.';
    end if;

    if exists (
        select 1
        from public.pod_memberships pm
        where pm.pod_id = p_pod_id
          and pm.membership_type = 'HR_SITE_CONNECT'
          and daterange(
              pm.effective_from,
              coalesce(pm.effective_to, 'infinity'::date),
              '[]'
          ) && daterange(p_effective_from, 'infinity'::date, '[]')
    ) then
        raise exception using
            errcode = '23P01',
            message = 'HR Psyconnect reviewer membership dates overlap an existing assignment in this pod.';
    end if;

    insert into public.pod_memberships (
        pod_id,
        candidate_id,
        user_id,
        membership_type,
        effective_from,
        effective_to,
        is_active,
        assigned_by,
        created_at,
        updated_at
    )
    values (
        p_pod_id,
        null,
        p_user_id,
        'HR_SITE_CONNECT',
        p_effective_from,
        null,
        true,
        v_actor_user_id,
        v_timestamp,
        v_timestamp
    )
    returning * into v_membership;

    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        remarks,
        activity_status,
        metadata,
        performed_by,
        performed_at,
        created_at,
        updated_at
    )
    values (
        null,
        'HR_SITE_CONNECT_POD_ASSIGNED',
        'HR Psyconnect reviewer assigned to pod',
        'SUCCESS',
        jsonb_build_object(
            'pod_id', p_pod_id,
            'pod_code', v_pod.pod_code,
            'user_id', p_user_id,
            'membership_id', v_membership.id,
            'membership_type', 'HR_SITE_CONNECT',
            'effective_from', p_effective_from,
            'changed', true
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return jsonb_build_object(
        'success', true,
        'operation', 'ASSIGN_HR_REVIEWER',
        'changed', true,
        'userId', p_user_id,
        'podId', p_pod_id,
        'membershipId', v_membership.id,
        'membershipType', 'HR_SITE_CONNECT',
        'effectiveFrom', p_effective_from
    );
end;
$function$;

comment on function public.assign_hr_site_connect_to_pod(uuid, uuid, date) is
    'Assigns one existing active HR_SITE_CONNECT user to an active pod without changing roles, candidate mappings, performance assignments, or prior membership history.';

revoke execute on function
    public.search_pod_management_hr_reviewers(text)
from public;

revoke execute on function
    public.search_pod_management_hr_reviewers(text)
from anon;

grant execute on function
    public.search_pod_management_hr_reviewers(text)
to authenticated;

grant execute on function
    public.search_pod_management_hr_reviewers(text)
to service_role;

revoke execute on function
    public.assign_hr_site_connect_to_pod(uuid, uuid, date)
from public;

revoke execute on function
    public.assign_hr_site_connect_to_pod(uuid, uuid, date)
from anon;

grant execute on function
    public.assign_hr_site_connect_to_pod(uuid, uuid, date)
to authenticated;

grant execute on function
    public.assign_hr_site_connect_to_pod(uuid, uuid, date)
to service_role;

commit;
