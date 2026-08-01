begin;

-- roles and user_roles are protected by RLS without authenticated read
-- policies. This helper exposes only the active HR_SITE_CONNECT assignment
-- state needed by active_interns_view to authorized active staff users.
create or replace function public.get_hr_psyconnect_access_status(
    p_user_id uuid
)
returns table (
    hr_psyconnect_access_active boolean,
    hr_psyconnect_access_granted_at timestamptz,
    hr_psyconnect_user_role_id uuid
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
begin
    if public.current_user_is_active() is distinct from true
       or public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT',
                'HR_SITE_CONNECT_LEAD',
                'HR_LEAD',
                'ADMIN'
            ]::text[]
       ) is distinct from true then
        raise exception using
            errcode = '42501',
            message = 'HR Psyconnect access status is unavailable.';
    end if;

    return query
    select
        (active_assignment.user_role_id is not null)::boolean,
        active_assignment.assigned_at::timestamptz,
        active_assignment.user_role_id::uuid
    from (select 1) as single_row
    left join lateral (
        select
            ur.id as user_role_id,
            ur.assigned_at
        from public.candidate_user_accounts cua
        join public.user_roles ur
            on ur.user_id = cua.user_id
        join public.roles r
            on r.id = ur.role_id
        where cua.user_id = p_user_id
          and ur.is_active = true
          and ur.ended_at is null
          and r.is_active = true
          and r.slug = 'HR_SITE_CONNECT'
        order by ur.assigned_at desc, ur.id desc
        limit 1
    ) active_assignment on true;
end;
$function$;

comment on function public.get_hr_psyconnect_access_status(uuid) is
    'Returns only the active HR_SITE_CONNECT assignment state for a candidate-mapped portal user. It is a narrow RLS-safe helper for authorized active staff and does not expose arbitrary role records.';

revoke all privileges on function
    public.get_hr_psyconnect_access_status(uuid)
from public;

revoke execute on function
    public.get_hr_psyconnect_access_status(uuid)
from anon;

grant execute on function
    public.get_hr_psyconnect_access_status(uuid)
to authenticated;

grant execute on function
    public.get_hr_psyconnect_access_status(uuid)
to service_role;

create or replace function public.grant_hr_psyconnect_access(
    p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_candidate public.master_candidates%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_portal_account public.candidate_user_accounts%rowtype;
    v_portal_user public.users%rowtype;
    v_candidate_role_id uuid;
    v_hr_role_id uuid;
    v_hr_user_role public.user_roles%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or public.current_user_has_any_role(
            array[
                'ADMIN',
                'HR_LEAD',
                'HR_SITE_CONNECT_LEAD'
            ]::text[]
       ) is distinct from true then
        raise exception using
            errcode = '42501',
            message = 'You do not have permission to manage HR Psyconnect access.';
    end if;

    if p_candidate_id is null then
        raise exception using
            errcode = '22004',
            message = 'Candidate ID is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'hr-psyconnect-access:' || p_candidate_id::text,
            0::bigint
        )
    );

    select c.*
    into v_candidate
    from public.master_candidates c
    where c.candidate_id = p_candidate_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate was not found.';
    end if;

    if v_candidate.applied_role is distinct from 'HR Psyconnect Intern'
       or v_candidate.role_code is distinct from 'HPI' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate is not eligible for HR Psyconnect access.';
    end if;

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = p_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0002',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    if v_lifecycle.lifecycle_status is null
       or v_lifecycle.lifecycle_status not in (
            'ACTIVE',
            'SIGNED_OFFER_SUBMITTED',
            'SIGNED_OFFER_VERIFIED',
            'MISMATCH_REVIEW'
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status is not eligible for HR Psyconnect access.';
    end if;

    select cua.*
    into v_portal_account
    from public.candidate_user_accounts cua
    where cua.candidate_id = p_candidate_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate portal account mapping was not found.';
    end if;

    if v_portal_account.account_status is distinct from 'ACTIVE'
       or v_portal_account.deactivated_at is not null
       or v_portal_account.activated_at > v_now then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate portal account is not active.';
    end if;

    select u.*
    into v_portal_user
    from public.users u
    where u.id = v_portal_account.user_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate application user was not found.';
    end if;

    if v_portal_user.status is distinct from 'active' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate application user is not active.';
    end if;

    select r.id
    into v_candidate_role_id
    from public.roles r
    where r.slug = 'CANDIDATE'
      and r.is_active = true
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Active CANDIDATE role was not found.';
    end if;

    select r.id
    into v_hr_role_id
    from public.roles r
    where r.slug = 'HR_SITE_CONNECT'
      and r.is_active = true
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Active HR_SITE_CONNECT role was not found.';
    end if;

    perform 1
    from public.user_roles ur
    where ur.user_id = v_portal_account.user_id
    for update;

    if not exists (
        select 1
        from public.user_roles ur
        where ur.user_id = v_portal_account.user_id
          and ur.role_id = v_candidate_role_id
          and ur.is_active = true
          and ur.ended_at is null
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate user does not have an active CANDIDATE role.';
    end if;

    select ur.*
    into v_hr_user_role
    from public.user_roles ur
    where ur.user_id = v_portal_account.user_id
      and ur.role_id = v_hr_role_id
      and ur.is_active = true
      and ur.ended_at is null;

    if found then
        return pg_catalog.jsonb_build_object(
            'success', true,
            'changed', false,
            'alreadyActive', true,
            'candidateId', p_candidate_id,
            'userId', v_portal_account.user_id,
            'roleSlug', 'HR_SITE_CONNECT',
            'userRoleId', v_hr_user_role.id,
            'candidateRolePreserved', true
        );
    end if;

    update public.user_roles ur
    set
        is_active = true,
        assigned_by = v_actor_user_id,
        assigned_at = v_now,
        ended_at = null,
        updated_at = v_now
    where ur.id = (
        select inactive_role.id
        from public.user_roles inactive_role
        where inactive_role.user_id = v_portal_account.user_id
          and inactive_role.role_id = v_hr_role_id
          and inactive_role.is_active = false
        order by inactive_role.assigned_at desc, inactive_role.id desc
        limit 1
    )
    returning ur.* into v_hr_user_role;

    if not found then
        insert into public.user_roles (
            user_id,
            role_id,
            is_active,
            assigned_by,
            assigned_at,
            ended_at,
            created_at,
            updated_at
        )
        values (
            v_portal_account.user_id,
            v_hr_role_id,
            true,
            v_actor_user_id,
            v_now,
            null,
            v_now,
            v_now
        )
        returning * into v_hr_user_role;
    end if;

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
        p_candidate_id,
        'HR_PSYCONNECT_ACCESS_GRANTED',
        'HR Psyconnect workspace access granted',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'candidate_id', p_candidate_id,
            'user_id', v_portal_account.user_id,
            'role_slug', 'HR_SITE_CONNECT',
            'user_role_id', v_hr_user_role.id,
            'applied_role', v_candidate.applied_role,
            'role_code', v_candidate.role_code,
            'changed', true
        ),
        v_actor_user_id::text,
        v_now,
        v_now,
        v_now
    );

    return pg_catalog.jsonb_build_object(
        'success', true,
        'changed', true,
        'alreadyActive', false,
        'candidateId', p_candidate_id,
        'userId', v_portal_account.user_id,
        'roleSlug', 'HR_SITE_CONNECT',
        'userRoleId', v_hr_user_role.id,
        'candidateRolePreserved', true
    );
end;
$function$;

comment on function public.grant_hr_psyconnect_access(uuid) is
    'Grants HR Psyconnect workspace access to an eligible candidate portal user by safely adding or reactivating HR_SITE_CONNECT while preserving CANDIDATE and all other identities.';

revoke all privileges on function
    public.grant_hr_psyconnect_access(uuid)
from public;

revoke execute on function
    public.grant_hr_psyconnect_access(uuid)
from anon;

grant execute on function
    public.grant_hr_psyconnect_access(uuid)
to authenticated;

grant execute on function
    public.grant_hr_psyconnect_access(uuid)
to service_role;

create or replace function public.revoke_hr_psyconnect_access(
    p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_candidate public.master_candidates%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_portal_account public.candidate_user_accounts%rowtype;
    v_portal_user public.users%rowtype;
    v_candidate_role_id uuid;
    v_hr_role_id uuid;
    v_hr_user_role public.user_roles%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or public.current_user_has_any_role(
            array[
                'ADMIN',
                'HR_LEAD',
                'HR_SITE_CONNECT_LEAD'
            ]::text[]
       ) is distinct from true then
        raise exception using
            errcode = '42501',
            message = 'You do not have permission to manage HR Psyconnect access.';
    end if;

    if p_candidate_id is null then
        raise exception using
            errcode = '22004',
            message = 'Candidate ID is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'hr-psyconnect-access:' || p_candidate_id::text,
            0::bigint
        )
    );

    select c.*
    into v_candidate
    from public.master_candidates c
    where c.candidate_id = p_candidate_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate was not found.';
    end if;

    if v_candidate.applied_role is distinct from 'HR Psyconnect Intern'
       or v_candidate.role_code is distinct from 'HPI' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate is not eligible for HR Psyconnect access.';
    end if;

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = p_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0002',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    if v_lifecycle.lifecycle_status is null
       or v_lifecycle.lifecycle_status not in (
            'ACTIVE',
            'SIGNED_OFFER_SUBMITTED',
            'SIGNED_OFFER_VERIFIED',
            'MISMATCH_REVIEW'
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status is not eligible for HR Psyconnect access.';
    end if;

    select cua.*
    into v_portal_account
    from public.candidate_user_accounts cua
    where cua.candidate_id = p_candidate_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate portal account mapping was not found.';
    end if;

    if v_portal_account.account_status is distinct from 'ACTIVE'
       or v_portal_account.deactivated_at is not null
       or v_portal_account.activated_at > v_now then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate portal account is not active.';
    end if;

    select u.*
    into v_portal_user
    from public.users u
    where u.id = v_portal_account.user_id
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate application user was not found.';
    end if;

    if v_portal_user.status is distinct from 'active' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate application user is not active.';
    end if;

    select r.id
    into v_candidate_role_id
    from public.roles r
    where r.slug = 'CANDIDATE'
      and r.is_active = true
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Active CANDIDATE role was not found.';
    end if;

    select r.id
    into v_hr_role_id
    from public.roles r
    where r.slug = 'HR_SITE_CONNECT'
      and r.is_active = true
    for update;

    if not found then
        raise exception using
            errcode = 'P0002',
            message = 'Active HR_SITE_CONNECT role was not found.';
    end if;

    perform 1
    from public.user_roles ur
    where ur.user_id = v_portal_account.user_id
    for update;

    if not exists (
        select 1
        from public.user_roles ur
        where ur.user_id = v_portal_account.user_id
          and ur.role_id = v_candidate_role_id
          and ur.is_active = true
          and ur.ended_at is null
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate user does not have an active CANDIDATE role.';
    end if;

    select ur.*
    into v_hr_user_role
    from public.user_roles ur
    where ur.user_id = v_portal_account.user_id
      and ur.role_id = v_hr_role_id
      and ur.is_active = true
      and ur.ended_at is null;

    if not found then
        return pg_catalog.jsonb_build_object(
            'success', true,
            'changed', false,
            'alreadyInactive', true,
            'candidateId', p_candidate_id,
            'userId', v_portal_account.user_id,
            'roleSlug', 'HR_SITE_CONNECT',
            'userRoleId', null,
            'candidateRolePreserved', true,
            'portalAccountPreserved', true
        );
    end if;

    update public.user_roles ur
    set
        is_active = false,
        ended_at = v_now,
        updated_at = v_now
    where ur.id = v_hr_user_role.id
    returning ur.* into v_hr_user_role;

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
        p_candidate_id,
        'HR_PSYCONNECT_ACCESS_REVOKED',
        'HR Psyconnect workspace access revoked',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'candidate_id', p_candidate_id,
            'user_id', v_portal_account.user_id,
            'role_slug', 'HR_SITE_CONNECT',
            'user_role_id', v_hr_user_role.id,
            'applied_role', v_candidate.applied_role,
            'role_code', v_candidate.role_code,
            'changed', true
        ),
        v_actor_user_id::text,
        v_now,
        v_now,
        v_now
    );

    return pg_catalog.jsonb_build_object(
        'success', true,
        'changed', true,
        'alreadyInactive', false,
        'candidateId', p_candidate_id,
        'userId', v_portal_account.user_id,
        'roleSlug', 'HR_SITE_CONNECT',
        'userRoleId', v_hr_user_role.id,
        'candidateRolePreserved', true,
        'portalAccountPreserved', true
    );
end;
$function$;

comment on function public.revoke_hr_psyconnect_access(uuid) is
    'Revokes only HR_SITE_CONNECT workspace access from an eligible candidate portal user while preserving CANDIDATE, other roles, the portal mapping, and user identities.';

revoke all privileges on function
    public.revoke_hr_psyconnect_access(uuid)
from public;

revoke execute on function
    public.revoke_hr_psyconnect_access(uuid)
from anon;

grant execute on function
    public.revoke_hr_psyconnect_access(uuid)
to authenticated;

grant execute on function
    public.revoke_hr_psyconnect_access(uuid)
to service_role;

-- Preserve the latest active_interns_view contract and append HR Psyconnect
-- access fields. Existing columns remain in their original order so this is a
-- safe CREATE OR REPLACE VIEW operation.
create or replace view public.active_interns_view
with (security_invoker = true)
as
select
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
    l.lifecycle_status,
    l.mid,
    o.offer_letter_number,
    o.sent_at as offer_letter_sent_at,
    s.signed_offer_status,
    s.signed_offer_submitted_at,
    s.verified_at,
    cua.account_status as portal_account_status,
    cua.user_id as portal_user_id,
    c.role_code,
    hr_access.hr_psyconnect_access_active,
    hr_access.hr_psyconnect_access_granted_at,
    hr_access.hr_psyconnect_user_role_id
from public.master_candidates c
join public.hr_lifecycle l
    on l.candidate_id = c.candidate_id
left join public.hr_offer_letters o
    on o.candidate_id = c.candidate_id
left join public.signed_offer_verifications s
    on s.candidate_id = c.candidate_id
left join public.candidate_user_accounts cua
    on cua.candidate_id = c.candidate_id
left join lateral public.get_hr_psyconnect_access_status(cua.user_id) hr_access
    on true
where l.lifecycle_status = 'ACTIVE'
   or o.offer_status = 'OFFER_LETTER_SENT';

revoke all privileges on public.active_interns_view from public;
revoke all privileges on public.active_interns_view from anon;
revoke all privileges on public.active_interns_view from authenticated;
grant select on public.active_interns_view to authenticated;

commit;
