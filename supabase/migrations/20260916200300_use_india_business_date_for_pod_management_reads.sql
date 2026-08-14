begin;

create or replace function public.get_pod_management_pods()
returns table (
    pod_id uuid,
    pod_code text,
    pod_name text,
    description text,
    is_active boolean,
    active_candidate_count bigint,
    active_pod_lead_count bigint,
    active_tech_lead_count bigint,
    current_pod_leads jsonb,
    current_tech_leads jsonb,
    created_at timestamptz,
    updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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

    return query
    select
        p.id,
        p.pod_code::text,
        p.pod_name::text,
        p.description::text,
        p.is_active,
        count(*) filter (
            where pm.membership_type = 'CANDIDATE'
              and pm.is_active = true
              and pm.effective_from <= v_business_date
              and (
                  pm.effective_to is null
                  or pm.effective_to >= v_business_date
              )
        ),
        count(*) filter (
            where pm.membership_type = 'POD_LEAD'
              and pm.is_active = true
              and pm.effective_from <= v_business_date
              and (
                  pm.effective_to is null
                  or pm.effective_to >= v_business_date
              )
        ),
        count(*) filter (
            where pm.membership_type = 'TECH_LEAD'
              and pm.is_active = true
              and pm.effective_from <= v_business_date
              and (
                  pm.effective_to is null
                  or pm.effective_to >= v_business_date
              )
        ),
        coalesce(
            jsonb_agg(
                distinct jsonb_build_object(
                    'userId', u.id,
                    'name', u.name
                )
            ) filter (
                where pm.membership_type = 'POD_LEAD'
                  and pm.is_active = true
                  and pm.effective_from <= v_business_date
                  and (
                      pm.effective_to is null
                      or pm.effective_to >= v_business_date
                  )
                  and u.id is not null
            ),
            '[]'::jsonb
        ),
        coalesce(
            jsonb_agg(
                distinct jsonb_build_object(
                    'userId', u.id,
                    'name', u.name
                )
            ) filter (
                where pm.membership_type = 'TECH_LEAD'
                  and pm.is_active = true
                  and pm.effective_from <= v_business_date
                  and (
                      pm.effective_to is null
                      or pm.effective_to >= v_business_date
                  )
                  and u.id is not null
            ),
            '[]'::jsonb
        ),
        p.created_at,
        p.updated_at
    from public.pods p
    left join public.pod_memberships pm
        on pm.pod_id = p.id
    left join public.users u
        on u.id = pm.user_id
    group by p.id
    order by p.is_active desc, p.pod_code asc, p.id asc;
end;
$function$;

comment on function public.get_pod_management_pods() is
    'Returns pods, active membership counts, and current Pod Lead and Tech Lead summaries to active authorized Pod Management users.';

create or replace function public.get_pod_management_memberships(
    p_pod_id uuid
)
returns table (
    membership_id uuid,
    pod_id uuid,
    candidate_id uuid,
    user_id uuid,
    member_name text,
    member_email text,
    membership_type text,
    effective_from date,
    effective_to date,
    is_active boolean,
    assigned_by uuid,
    assigned_by_name text,
    created_at timestamptz,
    updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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

    if p_pod_id is null then
        raise exception using
            errcode = '22004',
            message = 'A valid pod ID is required.';
    end if;

    if not exists (select 1 from public.pods p where p.id = p_pod_id) then
        raise exception using
            errcode = 'P0002',
            message = 'Pod was not found.';
    end if;

    return query
    select
        pm.id,
        pm.pod_id,
        pm.candidate_id,
        pm.user_id,
        coalesce(c.full_name, u.name)::text,
        coalesce(c.email, u.email)::text,
        pm.membership_type::text,
        pm.effective_from,
        pm.effective_to,
        (
            pm.is_active = true
            and pm.effective_from <= v_business_date
            and (
                pm.effective_to is null
                or pm.effective_to >= v_business_date
            )
        ),
        pm.assigned_by,
        assigner.name::text,
        pm.created_at,
        pm.updated_at
    from public.pod_memberships pm
    left join public.master_candidates c
        on c.candidate_id = pm.candidate_id
    left join public.users u
        on u.id = pm.user_id
    left join public.users assigner
        on assigner.id = pm.assigned_by
    where pm.pod_id = p_pod_id
    order by
        (
            pm.is_active = true
            and pm.effective_from <= v_business_date
            and (
                pm.effective_to is null
                or pm.effective_to >= v_business_date
            )
        ) desc,
        pm.membership_type asc,
        pm.effective_from desc,
        pm.id asc;
end;
$function$;

comment on function public.get_pod_management_memberships(uuid) is
    'Returns current and historical memberships for one pod to active authorized Pod Management users.';

create or replace function public.search_pod_management_candidates(
    p_search_term text default null
)
returns table (
    candidate_id uuid,
    full_name text,
    email text,
    applied_role text,
    mid text,
    lifecycle_status text,
    active_pod_id uuid,
    active_pod_code text,
    portal_account_status text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_search_term text := lower(btrim(coalesce(p_search_term, '')));
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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
            errcode = '22001',
            message = 'Candidate search is too long.';
    end if;

    return query
    select
        c.candidate_id,
        c.full_name::text,
        c.email::text,
        c.applied_role::text,
        hl.mid::text,
        hl.lifecycle_status::text,
        pm.pod_id,
        p.pod_code::text,
        cua.account_status::text
    from public.master_candidates c
    left join public.hr_lifecycle hl
        on hl.candidate_id = c.candidate_id
    left join public.pod_memberships pm
        on pm.candidate_id = c.candidate_id
       and pm.membership_type = 'CANDIDATE'
       and pm.is_active = true
       and pm.effective_from <= v_business_date
       and (
           pm.effective_to is null
           or pm.effective_to >= v_business_date
       )
    left join public.pods p
        on p.id = pm.pod_id
    left join public.candidate_user_accounts cua
        on cua.candidate_id = c.candidate_id
       and cua.account_status = 'ACTIVE'
       and cua.deactivated_at is null
       and cua.activated_at <= now()
    where v_search_term = ''
       or lower(c.full_name) like '%' || v_search_term || '%'
       or lower(c.email) like '%' || v_search_term || '%'
       or lower(coalesce(hl.mid, '')) like '%' || v_search_term || '%'
    order by c.full_name asc, c.candidate_id asc
    limit 50;
end;
$function$;

comment on function public.search_pod_management_candidates(text) is
    'Searches candidates by name, email, or MID and returns only the minimum identity, lifecycle, pod, and portal fields needed by Pod Management.';

create or replace function public.get_candidates_waiting_for_pod()
returns table (
    candidate_id uuid,
    full_name text,
    email text,
    lifecycle_status text,
    probation_start_date date,
    required_evaluation_start_date date,
    performance_job_id uuid,
    performance_job_status text,
    performance_job_error text,
    has_active_portal_account boolean
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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

    return query
    select
        c.candidate_id,
        c.full_name::text,
        c.email::text,
        hl.lifecycle_status::text,
        hl.probation_start_date,
        case
            when pc.start_date is null then null
            else greatest(pc.start_date, hl.probation_start_date)
        end,
        aj.job_id,
        aj.job_status::text,
        aj.error_message::text,
        (
            cua.id is not null
            and u.status = 'active'
        )
    from public.master_candidates c
    join public.hr_lifecycle hl
        on hl.candidate_id = c.candidate_id
    left join lateral (
        select cycle.start_date
        from public.performance_cycles cycle
        where cycle.cycle_status = 'OPEN'
          and v_business_date between cycle.start_date and cycle.end_date
        order by cycle.start_date desc, cycle.id desc
        limit 1
    ) pc on true
    left join lateral (
        select job.job_id, job.job_status, job.error_message
        from public.automation_jobs job
        where job.candidate_id = c.candidate_id
          and job.job_type = 'PERFORMANCE_CYCLE_ASSIGNMENT'
          and job.job_status in ('PENDING', 'RETRY')
        order by job.created_at desc, job.job_id desc
        limit 1
    ) aj on true
    left join public.candidate_user_accounts cua
        on cua.candidate_id = c.candidate_id
       and cua.account_status = 'ACTIVE'
       and cua.deactivated_at is null
       and cua.activated_at <= now()
    left join public.users u
        on u.id = cua.user_id
    where hl.lifecycle_status = 'IN_PROBATION'
      and not exists (
          select 1
          from public.pod_memberships pm
          where pm.candidate_id = c.candidate_id
            and pm.membership_type = 'CANDIDATE'
            and pm.is_active = true
            and pm.effective_from <= v_business_date
            and (
                pm.effective_to is null
                or pm.effective_to >= v_business_date
            )
      )
    order by hl.probation_start_date asc nulls last, c.full_name asc;
end;
$function$;

comment on function public.get_candidates_waiting_for_pod() is
    'Returns in-probation candidates without an active candidate pod membership, including the safe state of an existing retryable performance-assignment job.';

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
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
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
       and pm.effective_from <= v_business_date
       and (
           pm.effective_to is null
           or pm.effective_to >= v_business_date
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

revoke execute on function public.get_pod_management_pods() from public;
revoke execute on function public.get_pod_management_pods() from anon;
grant execute on function public.get_pod_management_pods() to authenticated;
grant execute on function public.get_pod_management_pods() to service_role;

revoke execute on function public.get_pod_management_memberships(uuid) from public;
revoke execute on function public.get_pod_management_memberships(uuid) from anon;
grant execute on function public.get_pod_management_memberships(uuid) to authenticated;
grant execute on function public.get_pod_management_memberships(uuid) to service_role;

revoke execute on function public.search_pod_management_candidates(text) from public;
revoke execute on function public.search_pod_management_candidates(text) from anon;
grant execute on function public.search_pod_management_candidates(text) to authenticated;
grant execute on function public.search_pod_management_candidates(text) to service_role;

revoke execute on function public.get_candidates_waiting_for_pod() from public;
revoke execute on function public.get_candidates_waiting_for_pod() from anon;
grant execute on function public.get_candidates_waiting_for_pod() to authenticated;
grant execute on function public.get_candidates_waiting_for_pod() to service_role;

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

commit;
