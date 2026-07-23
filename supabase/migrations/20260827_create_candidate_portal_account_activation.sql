create or replace function public.find_auth_user_id_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    select au.id
    from auth.users au
    where p_email is not null
      and pg_catalog.btrim(p_email) <> ''
      and pg_catalog.lower(pg_catalog.btrim(au.email)) =
          pg_catalog.lower(pg_catalog.btrim(p_email))
    order by au.created_at, au.id
    limit 1;
$function$;

comment on function public.find_auth_user_id_by_email(text) is
    'Server-side-only helper that resolves at most one Auth user ID by normalized email. It is not available to browser roles.';

revoke execute on function public.find_auth_user_id_by_email(text) from public;
revoke execute on function public.find_auth_user_id_by_email(text) from anon;
revoke execute on function public.find_auth_user_id_by_email(text) from authenticated;
grant execute on function public.find_auth_user_id_by_email(text) to service_role;

create or replace function public.finalize_candidate_portal_account(
    p_candidate_id uuid,
    p_user_id uuid,
    p_actor_user_id uuid
)
returns table (
    outcome text,
    candidate_id uuid,
    user_id uuid,
    email text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_now timestamptz := pg_catalog.now();
    v_candidate_name text;
    v_candidate_email text;
    v_auth_email text;
    v_lifecycle_status text;
    v_candidate_role_id uuid;
    v_actor_authorized boolean := false;
    v_existing_user public.users%rowtype;
    v_existing_mapping public.candidate_user_accounts%rowtype;
    v_conflicting_user_id uuid;
    v_conflicting_candidate_id uuid;
    v_assignment_id uuid;
    v_user_exists boolean := false;
    v_mapping_exists boolean := false;
    v_assignment_exists boolean := false;
    v_user_needs_repair boolean := false;
    v_mapping_needs_repair boolean := false;
    v_outcome text;
    v_activity_type text;
    v_remarks text;
begin
    if p_candidate_id is null
       or p_user_id is null
       or p_actor_user_id is null then
        raise exception using
            errcode = '22023',
            message = 'Candidate ID, Auth user ID, and actor user ID are required.';
    end if;

    -- Serialize concurrent activation requests for the same candidate or user so they remain idempotent instead of racing into unique-constraint errors.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'candidate:' || p_candidate_id::text,
            0::bigint
        )
    );

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'user:' || p_user_id::text,
            0::bigint
        )
    );

    begin
        select
            pg_catalog.btrim(c.full_name),
            pg_catalog.lower(pg_catalog.btrim(c.email))
        into strict v_candidate_name, v_candidate_email
        from public.master_candidates c
        where c.candidate_id = p_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0002',
                message = 'Candidate does not exist.';
    end;

    if v_candidate_name is null or v_candidate_name = '' then
        raise exception using
            errcode = '22023',
            message = 'Candidate full name must not be blank.';
    end if;

    if v_candidate_email is null or v_candidate_email = '' then
        raise exception using
            errcode = '22023',
            message = 'Candidate email must not be blank.';
    end if;

    begin
        select l.lifecycle_status
        into strict v_lifecycle_status
        from public.hr_lifecycle l
        where l.candidate_id = p_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0002',
                message = 'Candidate lifecycle record does not exist.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records and cannot be activated.';
    end;

    if v_lifecycle_status <> 'ACTIVE' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status must be ACTIVE.';
    end if;

    begin
        select pg_catalog.lower(pg_catalog.btrim(au.email))
        into strict v_auth_email
        from auth.users au
        where au.id = p_user_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0002',
                message = 'Supabase Auth user does not exist.';
    end;

    if v_auth_email is null or v_auth_email = '' then
        raise exception using
            errcode = '22023',
            message = 'Supabase Auth user email must not be blank.';
    end if;

    if v_auth_email <> v_candidate_email then
        raise exception using
            errcode = 'P0001',
            message = 'Supabase Auth user email does not match the candidate email.';
    end if;

    select exists (
        select 1
        from public.users actor
        join public.user_roles actor_role
            on actor_role.user_id = actor.id
        join public.roles role
            on role.id = actor_role.role_id
        where actor.id = p_actor_user_id
          and actor.status = 'active'
          and actor_role.is_active = true
          and actor_role.ended_at is null
          and role.is_active = true
          and role.slug in (
              'HR_SITE_CONNECT',
              'HR_SITE_CONNECT_LEAD',
              'HR_EXECUTIVE',
              'HR_EXECUTIVE_LEAD',
              'HR_LEAD',
              'FOUNDERS_OFFICE',
              'ADMIN'
          )
    )
    into v_actor_authorized;

    if not v_actor_authorized then
        raise exception using
            errcode = '42501',
            message = 'Actor is not an active authorized staff user.';
    end if;

    begin
        select r.id
        into strict v_candidate_role_id
        from public.roles r
        where r.slug = 'CANDIDATE'
          and r.is_active = true
        for share;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'The active CANDIDATE role is not configured.';
    end;

    select cua.user_id
    into v_conflicting_user_id
    from public.candidate_user_accounts cua
    where cua.candidate_id = p_candidate_id
    for update;

    if found and v_conflicting_user_id <> p_user_id then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate is already linked to a different user account.';
    end if;

    select cua.candidate_id
    into v_conflicting_candidate_id
    from public.candidate_user_accounts cua
    where cua.user_id = p_user_id
    for update;

    if found and v_conflicting_candidate_id <> p_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'User account is already linked to a different candidate.';
    end if;

    select u.*
    into v_existing_user
    from public.users u
    where u.id = p_user_id
    for update;
    v_user_exists := found;

    if exists (
        select 1
        from public.users u
        where u.id <> p_user_id
          and pg_catalog.lower(pg_catalog.btrim(u.email)) = v_candidate_email
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate email belongs to a different application user.';
    end if;

    select ur.id
    into v_assignment_id
    from public.user_roles ur
    where ur.user_id = p_user_id
      and ur.role_id = v_candidate_role_id
      and ur.is_active = true
      and ur.ended_at is null
    for update;
    v_assignment_exists := found;

    select cua.*
    into v_existing_mapping
    from public.candidate_user_accounts cua
    where cua.candidate_id = p_candidate_id
      and cua.user_id = p_user_id
    for update;
    v_mapping_exists := found;

    v_user_needs_repair :=
        not v_user_exists
        or v_existing_user.name is distinct from v_candidate_name
        or pg_catalog.lower(pg_catalog.btrim(v_existing_user.email))
            is distinct from v_candidate_email
        or v_existing_user.status is distinct from 'active'
        or v_existing_user.joined_at is null
        or v_existing_user.role_id is null;

    v_mapping_needs_repair :=
        v_mapping_exists
        and v_existing_mapping.account_status = 'ACTIVE'
        and (
            v_existing_mapping.linked_by is null
            or v_existing_mapping.activated_at > v_now
        );

    if not v_mapping_exists then
        v_outcome := 'ACTIVATED';
    elsif v_existing_mapping.account_status = 'INACTIVE' then
        v_outcome := 'REACTIVATED';
    elsif v_user_needs_repair
          or not v_assignment_exists
          or v_mapping_needs_repair then
        v_outcome := 'REPAIRED';
    else
        v_outcome := 'ALREADY_ACTIVE';
    end if;

    if not v_user_exists then
        insert into public.users (
            id,
            name,
            email,
            status,
            role_id,
            joined_at,
            created_at,
            updated_at
        ) values (
            p_user_id,
            v_candidate_name,
            v_candidate_email,
            'active',
            v_candidate_role_id,
            v_now,
            v_now,
            v_now
        );
    elsif v_user_needs_repair then
        update public.users u
        set name = v_candidate_name,
            email = v_candidate_email,
            status = 'active',
            role_id = pg_catalog.coalesce(u.role_id, v_candidate_role_id),
            joined_at = pg_catalog.coalesce(u.joined_at, v_now),
            updated_at = v_now
        where u.id = p_user_id;
    end if;

    if not v_assignment_exists then
        insert into public.user_roles (
            user_id,
            role_id,
            is_active,
            assigned_by,
            assigned_at,
            ended_at,
            created_at,
            updated_at
        ) values (
            p_user_id,
            v_candidate_role_id,
            true,
            p_actor_user_id,
            v_now,
            null,
            v_now,
            v_now
        );
    end if;

    if not v_mapping_exists then
        insert into public.candidate_user_accounts (
            candidate_id,
            user_id,
            account_status,
            activated_at,
            deactivated_at,
            linked_by,
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            p_user_id,
            'ACTIVE',
            v_now,
            null,
            p_actor_user_id,
            v_now,
            v_now
        );
    elsif v_existing_mapping.account_status = 'INACTIVE' then
        update public.candidate_user_accounts cua
        set account_status = 'ACTIVE',
            activated_at = v_now,
            deactivated_at = null,
            linked_by = p_actor_user_id,
            updated_at = v_now
        where cua.id = v_existing_mapping.id;
    elsif v_mapping_needs_repair then
        update public.candidate_user_accounts cua
        set activated_at = case
                when cua.activated_at > v_now then v_now
                else cua.activated_at
            end,
            linked_by = pg_catalog.coalesce(cua.linked_by, p_actor_user_id),
            updated_at = v_now
        where cua.id = v_existing_mapping.id;
    end if;

    if v_outcome <> 'ALREADY_ACTIVE' then
        v_activity_type := case v_outcome
            when 'ACTIVATED' then 'CANDIDATE_PORTAL_ACCOUNT_ACTIVATED'
            when 'REACTIVATED' then 'CANDIDATE_PORTAL_ACCOUNT_REACTIVATED'
            else 'CANDIDATE_PORTAL_ACCOUNT_REPAIRED'
        end;

        v_remarks := case v_outcome
            when 'ACTIVATED' then
                'Candidate portal account activated by authorized staff'
            when 'REACTIVATED' then
                'Candidate portal account reactivated by authorized staff'
            else
                'Candidate portal account identity records repaired by authorized staff'
        end;

        insert into public.hr_activity_logs (
            candidate_id,
            activity_type,
            from_status,
            to_status,
            remarks,
            activity_status,
            performed_by,
            performed_at,
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            v_activity_type,
            'ACTIVE',
            'ACTIVE',
            v_remarks,
            'SUCCESS',
            p_actor_user_id::text,
            v_now,
            v_now,
            v_now
        );
    end if;

    return query
    select
        v_outcome,
        p_candidate_id,
        p_user_id,
        v_candidate_email;
exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'Portal-account activation conflicts with an existing user, role, or candidate mapping.';
end;
$function$;

comment on function public.finalize_candidate_portal_account(uuid, uuid, uuid) is
    'Atomically validates an authorized staff actor, activates or repairs one candidate portal identity mapping, preserves staff primary roles and inactive role history, and records non-idempotent outcomes. Server-side service_role use only.';

revoke execute on function public.finalize_candidate_portal_account(uuid, uuid, uuid) from public;
revoke execute on function public.finalize_candidate_portal_account(uuid, uuid, uuid) from anon;
revoke execute on function public.finalize_candidate_portal_account(uuid, uuid, uuid) from authenticated;
grant execute on function public.finalize_candidate_portal_account(uuid, uuid, uuid) to service_role;
