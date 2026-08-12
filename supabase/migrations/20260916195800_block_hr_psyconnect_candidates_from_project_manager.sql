begin;

create or replace function public.assign_candidate_lead_to_pod(
    p_candidate_id uuid,
    p_pod_id uuid,
    p_lead_type text,
    p_effective_from date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_user_id uuid;
    v_role_id uuid;
    v_candidate_role_id uuid;
    v_lead_type text := upper(btrim(coalesce(p_lead_type, '')));
    v_candidate public.master_candidates%rowtype;
    v_membership public.pod_memberships%rowtype;
    v_timestamp timestamptz := now();
begin
    v_actor_user_id := public.current_app_user_id();
    if v_actor_user_id is null
       or not coalesce(
           public.current_user_has_any_role(
               array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT_LEAD']::text[]
           ),
           false
       ) then
        raise exception using errcode = '42501', message = 'Pod Management access is not permitted.';
    end if;
    if p_candidate_id is null or p_pod_id is null or p_effective_from is null then
        raise exception using errcode = '22004', message = 'Candidate, pod, lead type, and effective date are required.';
    end if;
    if v_lead_type not in ('POD_LEAD', 'TECH_LEAD') then
        raise exception using errcode = '22023', message = 'Lead type must be POD_LEAD or TECH_LEAD.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('candidate-lead:' || p_candidate_id::text, 0));
    perform pg_advisory_xact_lock(hashtextextended('pod:' || p_pod_id::text, 0));

    select c.* into v_candidate
    from public.master_candidates c
    where c.candidate_id = p_candidate_id
    for update;
    if not found then
        raise exception using errcode = 'P0002', message = 'Candidate was not found.';
    end if;

    perform 1 from public.pods p
    where p.id = p_pod_id and p.is_active = true for update;
    if not found then
        raise exception using errcode = 'P0002', message = 'Active pod was not found.';
    end if;

    select cua.user_id into strict v_user_id
    from public.candidate_user_accounts cua
    where cua.candidate_id = p_candidate_id
      and cua.account_status = 'ACTIVE'
      and cua.deactivated_at is null
      and cua.activated_at <= now()
    for update;

    perform 1 from public.users u
    where u.id = v_user_id and u.status = 'active' for update;
    if not found then
        raise exception using errcode = 'P0001', message = 'Candidate portal user is not active.';
    end if;

    select r.id into strict v_candidate_role_id
    from public.roles r
    where r.slug = 'CANDIDATE' and r.is_active = true;

    if not exists (
        select 1 from public.user_roles ur
        where ur.user_id = v_user_id
          and ur.role_id = v_candidate_role_id
          and ur.is_active = true
          and ur.ended_at is null
    ) then
        raise exception using errcode = 'P0001', message = 'Candidate role is not active for the mapped portal user.';
    end if;

    select r.id into strict v_role_id
    from public.roles r
    where r.slug = v_lead_type and r.is_active = true;

    perform 1 from public.user_roles ur
    where ur.user_id = v_user_id for update;
    perform 1 from public.pod_memberships pm
    where pm.user_id = v_user_id and pm.pod_id = p_pod_id for update;

    if v_lead_type = 'TECH_LEAD'
       and (
           (
               v_candidate.applied_role = 'HR Psyconnect Intern'
               and v_candidate.role_code = 'HPI'
           )
           or exists (
               select 1
               from public.user_roles ur
               join public.roles r
                 on r.id = ur.role_id
               where ur.user_id = v_user_id
                 and ur.is_active = true
                 and ur.ended_at is null
                 and r.slug = 'HR_SITE_CONNECT'
                 and r.is_active = true
           )
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'HR Psyconnect candidates cannot be assigned as Project Manager.';
    end if;

    if exists (
        select 1
        from public.pod_memberships pm
        where pm.pod_id = p_pod_id
          and pm.user_id = v_user_id
          and pm.membership_type in ('POD_LEAD', 'TECH_LEAD')
          and daterange(pm.effective_from, coalesce(pm.effective_to, 'infinity'::date), '[]')
              && daterange(p_effective_from, 'infinity'::date, '[]')
    ) then
        raise exception using errcode = '23P01', message = 'Lead membership dates overlap an existing lead assignment in this pod.';
    end if;

    if not exists (
        select 1
        from public.user_roles ur
        where ur.user_id = v_user_id
          and ur.role_id = v_role_id
          and ur.is_active = true
          and ur.ended_at is null
    ) then
        update public.user_roles
        set
            is_active = true,
            ended_at = null,
            assigned_by = v_actor_user_id,
            assigned_at = v_timestamp,
            updated_at = v_timestamp
        where id = (
            select ur.id
            from public.user_roles ur
            where ur.user_id = v_user_id
              and ur.role_id = v_role_id
              and ur.is_active = false
            order by ur.assigned_at desc, ur.id desc
            limit 1
        );

        if not found then
            insert into public.user_roles (
                user_id, role_id, is_active, assigned_by, assigned_at,
                ended_at, created_at, updated_at
            )
            values (
                v_user_id, v_role_id, true, v_actor_user_id, v_timestamp,
                null, v_timestamp, v_timestamp
            );
        end if;
    end if;

    insert into public.pod_memberships (
        pod_id, candidate_id, user_id, membership_type, effective_from,
        effective_to, is_active, assigned_by, created_at, updated_at
    )
    values (
        p_pod_id, null, v_user_id, v_lead_type, p_effective_from,
        null, true, v_actor_user_id, v_timestamp, v_timestamp
    )
    returning * into v_membership;

    insert into public.hr_activity_logs (
        candidate_id, activity_type, remarks, activity_status, metadata,
        performed_by, performed_at, created_at, updated_at
    )
    values (
        p_candidate_id,
        v_lead_type || '_ASSIGNED',
        case v_lead_type
            when 'POD_LEAD' then 'Candidate assigned as Pod Lead'
            else 'Candidate assigned as Tech Lead'
        end,
        'SUCCESS',
        jsonb_build_object(
            'pod_id', p_pod_id,
            'membership_id', v_membership.id,
            'membership_type', v_lead_type,
            'effective_from', p_effective_from,
            'user_id', v_user_id
        ),
        v_actor_user_id::text, v_timestamp, v_timestamp, v_timestamp
    );

    return jsonb_build_object(
        'success', true,
        'candidateId', p_candidate_id,
        'userId', v_user_id,
        'podId', p_pod_id,
        'membershipId', v_membership.id,
        'membershipType', v_lead_type,
        'effectiveFrom', p_effective_from,
        'candidateRolePreserved', true
    );
exception
    when no_data_found then
        raise exception using errcode = 'P0002', message = 'Required candidate portal account or active role was not found.';
end;
$function$;

comment on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) is
    'Atomically adds a Pod Lead or Tech Lead role and matching pod membership to an existing active candidate portal user without replacing the Candidate role or changing the portal mapping. HR Psyconnect candidates and active HR_SITE_CONNECT users cannot be assigned as Tech Leads.';

revoke execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) from public;
revoke execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) from anon;
grant execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) to authenticated;
grant execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) to service_role;

commit;
