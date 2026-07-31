begin;

-- Pod-level audit events do not have a candidate identity. Existing candidate
-- lifecycle events continue to store their candidate_id as before.
alter table public.hr_activity_logs
    alter column candidate_id drop not null;

comment on column public.hr_activity_logs.candidate_id is
    'Candidate associated with the event. Null is permitted only for pod-level events and staff-only pod-membership termination events that do not belong to a candidate.';

alter table public.hr_activity_logs
    drop constraint if exists hr_activity_logs_candidate_required_check;

alter table public.hr_activity_logs
    add constraint hr_activity_logs_candidate_required_check
    check (
        candidate_id is not null
        or activity_type in (
            'POD_CREATED',
            'POD_UPDATED',
            'STAFF_POD_MEMBERSHIP_ENDED'
        )
    )
    not valid;

do $validation$
begin
    if not exists (
        select 1
        from public.hr_activity_logs log
        where log.candidate_id is null
          and log.activity_type not in (
              'POD_CREATED',
              'POD_UPDATED',
              'STAFF_POD_MEMBERSHIP_ENDED'
          )
    ) then
        alter table public.hr_activity_logs
            validate constraint hr_activity_logs_candidate_required_check;
    end if;
end;
$validation$;

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
              and pm.effective_from <= current_date
              and (
                  pm.effective_to is null
                  or pm.effective_to >= current_date
              )
        ),
        count(*) filter (
            where pm.membership_type = 'POD_LEAD'
              and pm.is_active = true
              and pm.effective_from <= current_date
              and (
                  pm.effective_to is null
                  or pm.effective_to >= current_date
              )
        ),
        count(*) filter (
            where pm.membership_type = 'TECH_LEAD'
              and pm.is_active = true
              and pm.effective_from <= current_date
              and (
                  pm.effective_to is null
                  or pm.effective_to >= current_date
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
                  and pm.effective_from <= current_date
                  and (
                      pm.effective_to is null
                      or pm.effective_to >= current_date
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
                  and pm.effective_from <= current_date
                  and (
                      pm.effective_to is null
                      or pm.effective_to >= current_date
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
            and pm.effective_from <= current_date
            and (
                pm.effective_to is null
                or pm.effective_to >= current_date
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
            and pm.effective_from <= current_date
            and (
                pm.effective_to is null
                or pm.effective_to >= current_date
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
       and pm.effective_from <= current_date
       and (
           pm.effective_to is null
           or pm.effective_to >= current_date
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
          and current_date between cycle.start_date and cycle.end_date
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
            and pm.effective_from <= current_date
            and (
                pm.effective_to is null
                or pm.effective_to >= current_date
            )
      )
    order by hl.probation_start_date asc nulls last, c.full_name asc;
end;
$function$;

comment on function public.get_candidates_waiting_for_pod() is
    'Returns in-probation candidates without an active candidate pod membership, including the safe state of an existing retryable performance-assignment job.';

create or replace function public.create_pod(
    p_pod_code text,
    p_pod_name text,
    p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_pod public.pods%rowtype;
    v_pod_code text := upper(btrim(coalesce(p_pod_code, '')));
    v_pod_name text := btrim(coalesce(p_pod_name, ''));
    v_description text := nullif(btrim(coalesce(p_description, '')), '');
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
        raise exception using
            errcode = '42501',
            message = 'Pod Management access is not permitted.';
    end if;

    if v_pod_code = '' or char_length(v_pod_code) > 30 then
        raise exception using errcode = '22023', message = 'Pod code is invalid.';
    end if;
    if v_pod_name = '' or char_length(v_pod_name) > 150 then
        raise exception using errcode = '22023', message = 'Pod name is invalid.';
    end if;
    if v_description is not null and char_length(v_description) > 1000 then
        raise exception using errcode = '22001', message = 'Pod description is too long.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('pod-code:' || v_pod_code, 0));

    if exists (select 1 from public.pods p where p.pod_code = v_pod_code) then
        raise exception using errcode = '23505', message = 'Pod code already exists.';
    end if;

    insert into public.pods (
        pod_code, pod_name, description, is_active, created_at, updated_at
    )
    values (
        v_pod_code, v_pod_name, v_description, true, v_timestamp, v_timestamp
    )
    returning * into v_pod;

    insert into public.hr_activity_logs (
        candidate_id, activity_type, remarks, activity_status, metadata,
        performed_by, performed_at, created_at, updated_at
    )
    values (
        null,
        'POD_CREATED',
        'Pod created by an authorized HR user',
        'SUCCESS',
        jsonb_build_object('pod_id', v_pod.id, 'pod_code', v_pod.pod_code),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return jsonb_build_object(
        'success', true,
        'podId', v_pod.id,
        'podCode', v_pod.pod_code,
        'podName', v_pod.pod_name,
        'isActive', v_pod.is_active
    );
end;
$function$;

comment on function public.create_pod(text, text, text) is
    'Creates one active pod and records a permanent pod-level audit event. Access is limited to active authorized Pod Management users.';

create or replace function public.update_pod(
    p_pod_id uuid,
    p_pod_name text,
    p_description text,
    p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_pod public.pods%rowtype;
    v_pod_name text := btrim(coalesce(p_pod_name, ''));
    v_description text := nullif(btrim(coalesce(p_description, '')), '');
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
        raise exception using
            errcode = '42501',
            message = 'Pod Management access is not permitted.';
    end if;
    if p_pod_id is null or p_is_active is null then
        raise exception using errcode = '22004', message = 'Pod update values are required.';
    end if;
    if v_pod_name = '' or char_length(v_pod_name) > 150 then
        raise exception using errcode = '22023', message = 'Pod name is invalid.';
    end if;
    if v_description is not null and char_length(v_description) > 1000 then
        raise exception using errcode = '22001', message = 'Pod description is too long.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('pod:' || p_pod_id::text, 0));

    select * into strict v_pod
    from public.pods p
    where p.id = p_pod_id
    for update;

    if p_is_active = false
       and v_pod.is_active = true
       and exists (
           select 1
           from public.pod_memberships pm
           where pm.pod_id = p_pod_id
             and pm.is_active = true
             and (
                 pm.effective_to is null
                 or pm.effective_to >= current_date
             )
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Pod cannot be deactivated while active memberships remain.';
    end if;

    update public.pods
    set
        pod_name = v_pod_name,
        description = v_description,
        is_active = p_is_active,
        updated_at = v_timestamp
    where id = p_pod_id
    returning * into v_pod;

    insert into public.hr_activity_logs (
        candidate_id, activity_type, remarks, activity_status, metadata,
        performed_by, performed_at, created_at, updated_at
    )
    values (
        null,
        'POD_UPDATED',
        'Pod updated by an authorized HR user',
        'SUCCESS',
        jsonb_build_object('pod_id', v_pod.id, 'is_active', v_pod.is_active),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return jsonb_build_object(
        'success', true,
        'podId', v_pod.id,
        'podCode', v_pod.pod_code,
        'podName', v_pod.pod_name,
        'isActive', v_pod.is_active
    );
exception
    when no_data_found then
        raise exception using errcode = 'P0002', message = 'Pod was not found.';
end;
$function$;

comment on function public.update_pod(uuid, text, text, boolean) is
    'Updates a pod without changing its code and blocks deactivation while active memberships remain.';

create or replace function public.assign_candidate_to_pod(
    p_candidate_id uuid,
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
    v_candidate public.master_candidates%rowtype;
    v_previous public.pod_memberships%rowtype;
    v_membership public.pod_memberships%rowtype;
    v_previous_end_date date;
    v_job public.automation_jobs%rowtype;
    v_required_date date;
    v_retry_allowed boolean := false;
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
        raise exception using errcode = '22004', message = 'Candidate, pod, and effective date are required.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('candidate-pod:' || p_candidate_id::text, 0));

    select * into strict v_candidate
    from public.master_candidates c
    where c.candidate_id = p_candidate_id
    for update;

    select * into strict v_pod
    from public.pods p
    where p.id = p_pod_id
    for update;

    if not v_pod.is_active then
        raise exception using errcode = 'P0001', message = 'Candidates cannot be assigned to an inactive pod.';
    end if;

    perform 1
    from public.pod_memberships pm
    where pm.candidate_id = p_candidate_id
      and pm.membership_type = 'CANDIDATE'
    for update;

    select * into v_previous
    from public.pod_memberships pm
    where pm.candidate_id = p_candidate_id
      and pm.membership_type = 'CANDIDATE'
      and pm.is_active = true
    order by pm.effective_from desc, pm.id desc
    limit 1;

    if v_previous.id is not null and v_previous.pod_id = p_pod_id then
        raise exception using errcode = 'P0001', message = 'Candidate already has an active membership in this pod.';
    end if;

    if v_previous.id is not null then
        if p_effective_from <= v_previous.effective_from then
            raise exception using errcode = '22023', message = 'Transfer date must be after the current membership start date.';
        end if;
        v_previous_end_date := p_effective_from - 1;
        update public.pod_memberships
        set
            effective_to = v_previous_end_date,
            is_active = false,
            updated_at = v_timestamp
        where id = v_previous.id;

        insert into public.hr_activity_logs (
            candidate_id, activity_type, remarks, activity_status, metadata,
            performed_by, performed_at, created_at, updated_at
        )
        values (
            p_candidate_id,
            'CANDIDATE_POD_MEMBERSHIP_ENDED',
            'Previous candidate pod membership ended during transfer',
            'SUCCESS',
            jsonb_build_object(
                'pod_id', v_previous.pod_id,
                'membership_id', v_previous.id,
                'membership_type', 'CANDIDATE',
                'effective_from', v_previous.effective_from,
                'effective_to', v_previous_end_date
            ),
            v_actor_user_id::text, v_timestamp, v_timestamp, v_timestamp
        );
    end if;

    if exists (
        select 1
        from public.pod_memberships pm
        where pm.candidate_id = p_candidate_id
          and pm.membership_type = 'CANDIDATE'
          and pm.id is distinct from v_previous.id
          and daterange(pm.effective_from, coalesce(pm.effective_to, 'infinity'::date), '[]')
              && daterange(p_effective_from, 'infinity'::date, '[]')
    ) then
        raise exception using errcode = '23P01', message = 'Candidate pod membership dates overlap an existing membership.';
    end if;

    insert into public.pod_memberships (
        pod_id, candidate_id, user_id, membership_type, effective_from,
        effective_to, is_active, assigned_by, created_at, updated_at
    )
    values (
        p_pod_id, p_candidate_id, null, 'CANDIDATE', p_effective_from,
        null, true, v_actor_user_id, v_timestamp, v_timestamp
    )
    returning * into v_membership;

    select greatest(pc.start_date, hl.probation_start_date)
    into v_required_date
    from public.hr_lifecycle hl
    join lateral (
        select cycle.start_date
        from public.performance_cycles cycle
        where cycle.cycle_status = 'OPEN'
          and current_date between cycle.start_date and cycle.end_date
        order by cycle.start_date desc, cycle.id desc
        limit 1
    ) pc on true
    where hl.candidate_id = p_candidate_id;

    select * into v_job
    from public.automation_jobs aj
    where aj.candidate_id = p_candidate_id
      and aj.job_type = 'PERFORMANCE_CYCLE_ASSIGNMENT'
      and aj.job_status in ('PENDING', 'RETRY')
    order by aj.created_at desc, aj.job_id desc
    limit 1
    for update;

    v_retry_allowed :=
        v_job.job_id is not null
        and v_required_date is not null
        and p_effective_from <= v_required_date;

    insert into public.hr_activity_logs (
        candidate_id, activity_type, remarks, activity_status, metadata,
        performed_by, performed_at, created_at, updated_at
    )
    values (
        p_candidate_id,
        'CANDIDATE_POD_ASSIGNED',
        'Candidate assigned to a pod by an authorized HR user',
        'SUCCESS',
        jsonb_build_object(
            'pod_id', p_pod_id,
            'membership_id', v_membership.id,
            'membership_type', 'CANDIDATE',
            'effective_from', p_effective_from,
            'performance_job_id', v_job.job_id,
            'performance_retry_allowed', v_retry_allowed,
            'required_evaluation_start_date', v_required_date
        ),
        v_actor_user_id::text, v_timestamp, v_timestamp, v_timestamp
    );

    return jsonb_build_object(
        'success', true,
        'candidateId', p_candidate_id,
        'podId', p_pod_id,
        'membershipId', v_membership.id,
        'effectiveFrom', p_effective_from,
        'performanceJobId', v_job.job_id,
        'performanceJobStatus', v_job.job_status,
        'performanceRetryAllowed', v_retry_allowed,
        'requiredEvaluationStartDate', v_required_date,
        'performanceMessage',
        case
            when v_job.job_id is null then 'No pending performance-assignment job exists.'
            when v_required_date is null then 'No applicable OPEN performance cycle is available.'
            when not v_retry_allowed then 'Pod membership starts after the required performance evaluation start date.'
            else 'The existing performance-assignment job may be retried.'
        end
    );
exception
    when no_data_found then
        raise exception using errcode = 'P0002', message = 'Candidate or pod was not found.';
end;
$function$;

comment on function public.assign_candidate_to_pod(uuid, uuid, date) is
    'Assigns or transfers one candidate to an active pod, preserves ended membership history, and reports whether an existing pending performance-assignment job may be retried.';

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

    perform 1 from public.master_candidates c
    where c.candidate_id = p_candidate_id for update;
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
    'Atomically adds a Pod Lead or Tech Lead role and matching pod membership to an existing active candidate portal user without replacing the Candidate role or changing the portal mapping.';

create or replace function public.end_pod_membership(
    p_membership_id uuid,
    p_effective_to date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_membership public.pod_memberships%rowtype;
    v_candidate_id uuid;
    v_activity_type text;
    v_staff_only boolean := false;
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
    if p_membership_id is null or p_effective_to is null then
        raise exception using errcode = '22004', message = 'Membership and end date are required.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('pod-membership:' || p_membership_id::text, 0));

    select * into strict v_membership
    from public.pod_memberships pm
    where pm.id = p_membership_id
    for update;

    if not v_membership.is_active then
        raise exception using errcode = 'P0001', message = 'Pod membership is already inactive.';
    end if;
    if p_effective_to < v_membership.effective_from then
        raise exception using errcode = '22023', message = 'Membership end date cannot be earlier than its start date.';
    end if;

    update public.pod_memberships
    set effective_to = p_effective_to, is_active = false, updated_at = v_timestamp
    where id = p_membership_id
    returning * into v_membership;

    if v_membership.candidate_id is not null then
        v_candidate_id := v_membership.candidate_id;
    else
        select cua.candidate_id into v_candidate_id
        from public.candidate_user_accounts cua
        where cua.user_id = v_membership.user_id;

        v_staff_only := v_candidate_id is null;
    end if;

    v_activity_type := case
        when v_staff_only then 'STAFF_POD_MEMBERSHIP_ENDED'
        else 'CANDIDATE_POD_MEMBERSHIP_ENDED'
    end;

    insert into public.hr_activity_logs (
        candidate_id, activity_type, remarks, activity_status, metadata,
        performed_by, performed_at, created_at, updated_at
    )
    values (
        v_candidate_id,
        v_activity_type,
        'Pod membership ended by an authorized HR user',
        'SUCCESS',
        jsonb_build_object(
            'pod_id', v_membership.pod_id,
            'membership_id', v_membership.id,
            'membership_type', v_membership.membership_type,
            'effective_from', v_membership.effective_from,
            'effective_to', v_membership.effective_to,
            'user_id', v_membership.user_id,
            'staffOnly', v_staff_only
        ),
        v_actor_user_id::text, v_timestamp, v_timestamp, v_timestamp
    );

    return jsonb_build_object(
        'success', true,
        'membershipId', v_membership.id,
        'podId', v_membership.pod_id,
        'membershipType', v_membership.membership_type,
        'effectiveTo', v_membership.effective_to,
        'isActive', v_membership.is_active
    );
exception
    when no_data_found then
        raise exception using errcode = 'P0002', message = 'Pod membership was not found.';
end;
$function$;

comment on function public.end_pod_membership(uuid, date) is
    'Ends one active pod membership without deleting its historical row. Candidate-backed memberships retain their candidate audit identity, while valid staff-only lead memberships use a dedicated staff-only audit event.';

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

revoke execute on function public.create_pod(text, text, text) from public;
revoke execute on function public.create_pod(text, text, text) from anon;
grant execute on function public.create_pod(text, text, text) to authenticated;
grant execute on function public.create_pod(text, text, text) to service_role;

revoke execute on function public.update_pod(uuid, text, text, boolean) from public;
revoke execute on function public.update_pod(uuid, text, text, boolean) from anon;
grant execute on function public.update_pod(uuid, text, text, boolean) to authenticated;
grant execute on function public.update_pod(uuid, text, text, boolean) to service_role;

revoke execute on function public.assign_candidate_to_pod(uuid, uuid, date) from public;
revoke execute on function public.assign_candidate_to_pod(uuid, uuid, date) from anon;
grant execute on function public.assign_candidate_to_pod(uuid, uuid, date) to authenticated;
grant execute on function public.assign_candidate_to_pod(uuid, uuid, date) to service_role;

revoke execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) from public;
revoke execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) from anon;
grant execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) to authenticated;
grant execute on function public.assign_candidate_lead_to_pod(uuid, uuid, text, date) to service_role;

revoke execute on function public.end_pod_membership(uuid, date) from public;
revoke execute on function public.end_pod_membership(uuid, date) from anon;
grant execute on function public.end_pod_membership(uuid, date) to authenticated;
grant execute on function public.end_pod_membership(uuid, date) to service_role;

commit;
