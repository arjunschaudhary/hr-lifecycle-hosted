begin;

-- One canonical reason code protects every new operational assignment from
-- candidates whose lifecycle is already rejected or whose Exit process has
-- started. Existing memberships and historical records are not changed.
create or replace function public.candidate_new_assignment_block_reason(
    p_candidate_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_lifecycle_status text;
begin
    if p_candidate_id is null then
        return 'CANDIDATE_NOT_FOUND';
    end if;

    select hl.lifecycle_status
    into v_lifecycle_status
    from public.hr_lifecycle hl
    where hl.candidate_id = p_candidate_id
    order by hl.updated_at desc nulls last, hl.lifecycle_id desc
    limit 1;

    if v_lifecycle_status = 'PROBATION_REJECTED' then
        return 'PROBATION_REJECTED';
    end if;

    if exists (
        select 1
        from public.exit_cases ec
        where ec.candidate_id = p_candidate_id
    ) then
        return 'EXIT_STARTED';
    end if;

    return null;
end;
$function$;

comment on function public.candidate_new_assignment_block_reason(uuid) is
    'Internal predicate returning a controlled reason when a candidate cannot receive a new operational assignment because probation was rejected or Exit has started.';

revoke all privileges on function public.candidate_new_assignment_block_reason(uuid)
from public, anon, authenticated;
grant execute on function public.candidate_new_assignment_block_reason(uuid)
to service_role;

create or replace function public.enforce_new_candidate_pod_eligibility()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_block_reason text;
begin
    if new.membership_type is distinct from 'CANDIDATE'
       or new.candidate_id is null then
        return new;
    end if;

    v_block_reason := public.candidate_new_assignment_block_reason(
        new.candidate_id
    );

    if v_block_reason = 'PROBATION_REJECTED' then
        raise exception using
            errcode = 'P0001',
            message = 'Probation-rejected candidates cannot be assigned to a pod.';
    end if;

    if v_block_reason = 'EXIT_STARTED' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidates with an initiated Exit process cannot be assigned to a pod.';
    end if;

    return new;
end;
$function$;

revoke all privileges on function public.enforce_new_candidate_pod_eligibility()
from public, anon, authenticated;

drop trigger if exists enforce_new_candidate_pod_eligibility
on public.pod_memberships;

create trigger enforce_new_candidate_pod_eligibility
before insert on public.pod_memberships
for each row
execute function public.enforce_new_candidate_pod_eligibility();

-- Search remains informational, but now exposes the same server-owned reason
-- used by the insert trigger so the UI can disable only known-invalid actions.
drop function if exists public.search_pod_management_candidates(text);

create function public.search_pod_management_candidates(
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
    portal_account_status text,
    pod_assignment_block_reason text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_search_term text := pg_catalog.lower(
        pg_catalog.btrim(coalesce(p_search_term, ''))
    );
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

    if pg_catalog.char_length(v_search_term) > 150 then
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
        cua.account_status::text,
        public.candidate_new_assignment_block_reason(c.candidate_id)
    from public.master_candidates c
    left join public.hr_lifecycle hl
        on hl.candidate_id = c.candidate_id
    left join public.pod_memberships pm
        on pm.candidate_id = c.candidate_id
       and pm.membership_type = 'CANDIDATE'
       and pm.is_active = true
       and pm.effective_from <=
           (current_timestamp at time zone 'Asia/Kolkata')::date
       and (
           pm.effective_to is null
           or pm.effective_to >=
               (current_timestamp at time zone 'Asia/Kolkata')::date
       )
    left join public.pods p
        on p.id = pm.pod_id
    left join public.candidate_user_accounts cua
        on cua.candidate_id = c.candidate_id
       and cua.account_status = 'ACTIVE'
       and cua.deactivated_at is null
       and cua.activated_at <= pg_catalog.now()
    where v_search_term = ''
       or pg_catalog.lower(c.full_name) like '%' || v_search_term || '%'
       or pg_catalog.lower(c.email) like '%' || v_search_term || '%'
       or pg_catalog.lower(coalesce(hl.mid, ''))
           like '%' || v_search_term || '%'
    order by c.full_name asc, c.candidate_id asc
    limit 50;
end;
$function$;

comment on function public.search_pod_management_candidates(text) is
    'Searches Pod Management candidates and exposes the canonical controlled reason when a new candidate pod assignment is blocked.';

revoke all privileges on function public.search_pod_management_candidates(text)
from public, anon;
grant execute on function public.search_pod_management_candidates(text)
to authenticated, service_role;

-- Keep the operational Waiting for Pod queue aligned with the same canonical
-- eligibility guard that protects the membership insert boundary. The return
-- shape is intentionally unchanged.
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
set search_path = pg_catalog, public, auth, pg_temp
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
       and cua.activated_at <= pg_catalog.now()
    left join public.users u
        on u.id = cua.user_id
    where hl.lifecycle_status = 'IN_PROBATION'
      and public.candidate_new_assignment_block_reason(c.candidate_id) is null
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
    'Returns only assignment-eligible in-probation candidates without an active candidate pod membership, preserving the existing response shape and retryable performance-job state.';

revoke all privileges on function public.get_candidates_waiting_for_pod()
from public, anon;
grant execute on function public.get_candidates_waiting_for_pod()
to authenticated, service_role;

-- Exit initiation is authoritative through exit_cases. These triggers make
-- every new extension fail closed even if an old browser path bypasses the
-- new atomic RPC. Existing extension rows are untouched.
create or replace function public.enforce_no_extension_after_exit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
begin
    if exists (
        select 1
        from public.exit_cases ec
        where ec.candidate_id = new.candidate_id
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Internship extension is not available after Exit has started.';
    end if;

    return new;
end;
$function$;

revoke all privileges on function public.enforce_no_extension_after_exit()
from public, anon, authenticated;

drop trigger if exists enforce_no_extension_after_exit
on public.internship_extensions;

create trigger enforce_no_extension_after_exit
before insert on public.internship_extensions
for each row
execute function public.enforce_no_extension_after_exit();

create or replace function public.enforce_no_lifecycle_extension_after_exit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
begin
    if (
        coalesce(new.total_extension_months, 0)
            > coalesce(old.total_extension_months, 0)
        or coalesce(new.probation_extension_count, 0)
            > coalesce(old.probation_extension_count, 0)
        or (
            new.lifecycle_status = 'PROBATION_EXTENDED'
            and old.lifecycle_status is distinct from 'PROBATION_EXTENDED'
        )
    )
    and exists (
        select 1
        from public.exit_cases ec
        where ec.candidate_id = new.candidate_id
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate extension is not available after Exit has started.';
    end if;

    return new;
end;
$function$;

revoke all privileges on function public.enforce_no_lifecycle_extension_after_exit()
from public, anon, authenticated;

drop trigger if exists enforce_no_lifecycle_extension_after_exit
on public.hr_lifecycle;

create trigger enforce_no_lifecycle_extension_after_exit
before update of
    lifecycle_status,
    probation_extension_count,
    total_extension_months
on public.hr_lifecycle
for each row
execute function public.enforce_no_lifecycle_extension_after_exit();

create or replace function public.get_internship_extension_candidates()
returns table (
    candidate_id uuid,
    full_name text,
    email text,
    phone text,
    applied_role text,
    lifecycle_status text,
    probation_start_date date,
    internship_duration_months integer,
    total_extension_months integer,
    total_internship_duration_days integer,
    current_internship_duration_days integer,
    current_end_date date,
    mid text,
    allocated_leave_days integer,
    approved_leave_days integer,
    remaining_leave_days integer,
    extra_leave_days integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_role('HR_SITE_CONNECT_LEAD') is not true then
        raise exception using
            errcode = '42501',
            message = 'Internship extension access is not available.';
    end if;

    return query
    select
        detail.candidate_id,
        detail.full_name::text,
        detail.email::text,
        detail.phone::text,
        detail.applied_role::text,
        detail.lifecycle_status::text,
        detail.probation_start_date::date,
        detail.internship_duration_months::integer,
        detail.total_extension_months::integer,
        detail.total_internship_duration_days::integer,
        detail.current_internship_duration_days::integer,
        detail.current_end_date::date,
        detail.mid::text,
        detail.allocated_leave_days::integer,
        detail.approved_leave_days::integer,
        detail.remaining_leave_days::integer,
        detail.extra_leave_days::integer
    from public.candidate_detail_view detail
    where detail.lifecycle_status in (
        'HR_APPROVED_FOR_PROBATION',
        'WELCOME_MAIL_SENT',
        'IN_PROBATION',
        'PROBATION_REVIEW',
        'PROBATION_EXTENDED',
        'PROBATION_PASSED',
        'MID_GENERATED',
        'OFFER_LETTER_GENERATED',
        'OFFER_LETTER_SENT',
        'ACTIVE',
        'SIGNED_OFFER_SUBMITTED',
        'SIGNED_OFFER_VERIFIED',
        'MISMATCH_REVIEW'
    )
      and not exists (
          select 1
          from public.exit_cases ec
          where ec.candidate_id = detail.candidate_id
      )
    order by detail.full_name, detail.candidate_id;
end;
$function$;

comment on function public.get_internship_extension_candidates() is
    'Returns the minimum extension fields for eligible candidates to an exact active HR_SITE_CONNECT_LEAD and excludes every candidate whose Exit process has started.';

revoke all privileges on function public.get_internship_extension_candidates()
from public, anon;
grant execute on function public.get_internship_extension_candidates()
to authenticated, service_role;

create or replace function public.extend_candidate_internship(
    p_candidate_id uuid,
    p_extension_months integer,
    p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_balance public.leave_balances%rowtype;
    v_reason text := nullif(pg_catalog.btrim(p_reason), '');
    v_previous_extension_months integer;
    v_total_extension_months integer;
    v_total_duration_days integer;
    v_allocated_leave_days integer;
    v_approved_leave_days integer;
    v_remaining_leave_days integer;
    v_extra_leave_days integer;
    v_current_end_date date;
    v_leave_days_to_add integer;
    v_added_leave_days integer := 0;
    v_timestamp timestamptz := pg_catalog.now();
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_role('HR_SITE_CONNECT_LEAD') is not true then
        raise exception using
            errcode = '42501',
            message = 'Internship extension access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if p_candidate_id is null then
        raise exception using errcode = '22004', message = 'Candidate is required.';
    end if;

    if p_extension_months is null
       or p_extension_months < 1
       or p_extension_months > 6 then
        raise exception using
            errcode = '22023',
            message = 'Extension months must be between 1 and 6.';
    end if;

    if v_reason is null then
        raise exception using
            errcode = '22004',
            message = 'Extension reason is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'candidate-internship-extension:' || p_candidate_id::text,
            0
        )
    );

    select hl.*
    into v_lifecycle
    from public.hr_lifecycle hl
    where hl.candidate_id = p_candidate_id
    order by hl.updated_at desc nulls last, hl.lifecycle_id desc
    limit 1
    for update;

    if v_lifecycle.lifecycle_id is null then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate lifecycle record was not found.';
    end if;

    if exists (
        select 1
        from public.exit_cases ec
        where ec.candidate_id = p_candidate_id
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Internship extension is not available after Exit has started.';
    end if;

    if v_lifecycle.lifecycle_status not in (
        'HR_APPROVED_FOR_PROBATION',
        'WELCOME_MAIL_SENT',
        'IN_PROBATION',
        'PROBATION_REVIEW',
        'PROBATION_EXTENDED',
        'PROBATION_PASSED',
        'MID_GENERATED',
        'OFFER_LETTER_GENERATED',
        'OFFER_LETTER_SENT',
        'ACTIVE',
        'SIGNED_OFFER_SUBMITTED',
        'SIGNED_OFFER_VERIFIED',
        'MISMATCH_REVIEW'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate is not eligible for internship extension.';
    end if;

    if v_lifecycle.probation_start_date is null then
        raise exception using
            errcode = 'P0001',
            message = 'Probation start date is required for internship extension.';
    end if;

    if v_lifecycle.internship_duration_months not in (3, 4) then
        raise exception using
            errcode = 'P0001',
            message = 'Leave entitlement is defined only for 3 or 4 month internships.';
    end if;

    perform 1
    from public.internship_extensions ie
    where ie.candidate_id = p_candidate_id
    for update;

    select coalesce(pg_catalog.sum(ie.extension_value), 0)::integer
    into v_previous_extension_months
    from public.internship_extensions ie
    where ie.candidate_id = p_candidate_id
      and ie.extension_type = 'MONTHS'
      and ie.is_processed = true;

    v_total_extension_months :=
        v_previous_extension_months + p_extension_months;
    v_total_duration_days :=
        v_lifecycle.internship_duration_months * 30
        + v_total_extension_months * 30;

    select lb.*
    into v_balance
    from public.leave_balances lb
    where lb.candidate_id = p_candidate_id
    for update;

    v_approved_leave_days :=
        coalesce(v_balance.approved_leave_days, 0);
    v_extra_leave_days :=
        coalesce(v_balance.extra_leave_days, 0);
    v_allocated_leave_days :=
        case v_lifecycle.internship_duration_months
            when 3 then 9 + v_total_extension_months * 3
            when 4 then 15 + v_total_extension_months * 3
        end;
    v_remaining_leave_days := greatest(
        v_allocated_leave_days - v_approved_leave_days,
        0
    );

    v_current_end_date :=
        v_lifecycle.probation_start_date + v_total_duration_days;
    v_leave_days_to_add := v_approved_leave_days + v_extra_leave_days;

    while v_added_leave_days < v_leave_days_to_add loop
        v_current_end_date := v_current_end_date + 1;
        if extract(isodow from v_current_end_date) <> 7 then
            v_added_leave_days := v_added_leave_days + 1;
        end if;
    end loop;

    insert into public.internship_extensions (
        candidate_id,
        mid,
        extension_type,
        extension_value,
        reason,
        created_at,
        is_processed
    ) values (
        p_candidate_id,
        v_lifecycle.mid,
        'MONTHS',
        p_extension_months,
        v_reason,
        v_timestamp,
        true
    );

    update public.hr_lifecycle
    set
        total_extension_months = v_total_extension_months,
        total_internship_duration_days = v_total_duration_days,
        current_internship_duration_days = v_total_duration_days,
        current_end_date = v_current_end_date,
        updated_at = v_timestamp
    where lifecycle_id = v_lifecycle.lifecycle_id;

    insert into public.leave_balances (
        candidate_id,
        mid,
        allocated_leave_days,
        approved_leave_days,
        remaining_leave_days,
        extra_leave_days,
        created_at,
        updated_at
    ) values (
        p_candidate_id,
        coalesce(v_lifecycle.mid, v_balance.mid),
        v_allocated_leave_days,
        v_approved_leave_days,
        v_remaining_leave_days,
        v_extra_leave_days,
        v_timestamp,
        v_timestamp
    )
    on conflict (candidate_id) do update
    set
        mid = excluded.mid,
        allocated_leave_days = excluded.allocated_leave_days,
        approved_leave_days = excluded.approved_leave_days,
        remaining_leave_days = excluded.remaining_leave_days,
        extra_leave_days = excluded.extra_leave_days,
        updated_at = excluded.updated_at;

    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        from_status,
        to_status,
        remarks,
        activity_status,
        metadata,
        performed_by,
        performed_at,
        created_at,
        updated_at
    ) values (
        p_candidate_id,
        'INTERNSHIP_EXTENDED',
        v_lifecycle.lifecycle_status,
        v_lifecycle.lifecycle_status,
        pg_catalog.format(
            'Internship extended by %s month(s). %s',
            p_extension_months,
            v_reason
        ),
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'extension_months', p_extension_months,
            'total_extension_months', v_total_extension_months,
            'allocated_leave_days', v_allocated_leave_days,
            'current_end_date', v_current_end_date
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return pg_catalog.jsonb_build_object(
        'candidateId', p_candidate_id,
        'allocatedLeaveDays', v_allocated_leave_days,
        'currentEndDate', v_current_end_date,
        'totalExtensionMonths', v_total_extension_months,
        'totalInternshipDurationDays', v_total_duration_days
    );
end;
$function$;

comment on function public.extend_candidate_internship(uuid, integer, text) is
    'Atomically extends one eligible internship, recalculates leave/end-date state with the existing policy, records audit history, and rejects every candidate whose Exit process has started.';

revoke all privileges on function public.extend_candidate_internship(uuid, integer, text)
from public, anon;
grant execute on function public.extend_candidate_internship(uuid, integer, text)
to authenticated, service_role;

-- Current non-terminal candidate performance belongs only to a candidate who
-- is still an active member of the historical cycle pod. Terminal history is
-- retained regardless of later pod changes.
create or replace function public.candidate_performance_cycle_is_visible(
    p_candidate_cycle_id uuid,
    p_business_date date
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
    select exists (
        select 1
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        where cpc.id = p_candidate_cycle_id
          and (
              cpc.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED')
              or pc.cycle_status in ('FINALIZED', 'LOCKED')
              or exists (
                  select 1
                  from public.pod_memberships pm
                  where pm.candidate_id = cpc.candidate_id
                    and pm.user_id is null
                    and pm.pod_id = cpc.pod_id
                    and pm.membership_type = 'CANDIDATE'
                    and pm.is_active = true
                    and pm.effective_from <= p_business_date
                    and (
                        pm.effective_to is null
                        or pm.effective_to >= p_business_date
                    )
              )
          )
    );
$function$;

comment on function public.candidate_performance_cycle_is_visible(uuid, date) is
    'Internal read predicate retaining terminal performance history while requiring current active membership in the historical candidate-cycle pod for non-terminal evaluation.';

revoke all privileges on function public.candidate_performance_cycle_is_visible(uuid, date)
from public, anon, authenticated;
grant execute on function public.candidate_performance_cycle_is_visible(uuid, date)
to service_role;

create or replace function public.current_linked_candidate_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
    select cua.candidate_id
    from public.candidate_user_accounts cua
    where cua.user_id = public.current_app_user_id();
$function$;

comment on function public.current_linked_candidate_id() is
    'Internal assessment guard resolving the authenticated application user one-to-one candidate identity, including an audit-preserved inactive portal mapping.';

revoke all privileges on function public.current_linked_candidate_id()
from public, anon, authenticated;
grant execute on function public.current_linked_candidate_id()
to service_role;

create or replace view public.candidate_performance_list_view
with (security_invoker = true)
as
select
    cpc.id as candidate_cycle_id,
    cpc.cycle_id,
    pc.cycle_code,
    pc.cycle_number,
    pc.start_date as cycle_start_date,
    pc.end_date as cycle_end_date,
    pc.review_open_date,
    pc.lock_date,
    pc.cycle_status,
    cpc.candidate_id,
    mc.full_name,
    mc.email,
    mc.applied_role,
    mc.role_code,
    mc.department,
    cpc.pod_id,
    p.pod_code,
    p.pod_name,
    cpc.evaluation_start_date,
    cpc.evaluation_end_date,
    cpc.is_partial_cycle,
    cpc.eligible_days,
    cpc.scored_days,
    greatest(cpc.eligible_days - cpc.scored_days, 0)::integer
        as remaining_scoring_days,
    case
        when cpc.eligible_days > 0 then
            pg_catalog.round(
                cpc.scored_days::numeric / cpc.eligible_days::numeric * 100,
                2
            )
        else 0::numeric
    end as scoring_completion_percent,
    cpc.daily_average,
    cpc.daily_component_score,
    cpc.lead_score,
    cpc.hr_score,
    cpc.exceptional_score,
    cpc.final_score,
    cpc.performance_band,
    cpc.result_status,
    (cpc.daily_component_score is not null) as daily_summary_ready,
    (cpc.lead_score is not null) as lead_review_ready,
    (cpc.hr_score is not null) as hr_review_ready,
    (cpc.exceptional_score is not null) as exceptional_summary_ready,
    (
        cpc.eligible_days > 0
        and cpc.scored_days = cpc.eligible_days
        and cpc.daily_component_score is not null
        and cpc.lead_score is not null
        and cpc.hr_score is not null
        and cpc.exceptional_score is not null
    ) as all_components_ready,
    (
        cpc.final_score is not null
        and cpc.performance_band is not null
    ) as final_result_ready,
    (cpc.result_status = 'CANDIDATE_REVIEW') as ready_for_finalization,
    (
        cpc.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED')
    ) as is_protected,
    cpc.calculated_at,
    cpc.finalized_at,
    cpc.created_at as assignment_created_at,
    cpc.updated_at as assignment_updated_at
from public.candidate_performance_cycles cpc
join public.performance_cycles pc on pc.id = cpc.cycle_id
join public.master_candidates mc on mc.candidate_id = cpc.candidate_id
join public.pods p on p.id = cpc.pod_id
where public.candidate_performance_cycle_is_visible(
    cpc.id,
    (current_timestamp at time zone 'Asia/Kolkata')::date
);

comment on view public.candidate_performance_list_view is
    'Returns terminal performance history plus currently evaluable candidate-cycle rows whose candidate remains active in the historical cycle pod.';

revoke all privileges on public.candidate_performance_list_view from public;
revoke all privileges on public.candidate_performance_list_view from anon;
revoke all privileges on public.candidate_performance_list_view from authenticated;
grant select on public.candidate_performance_list_view to service_role;

create or replace view public.performance_cycle_overview_view
with (security_invoker = true)
as
select
    pc.id as cycle_id,
    pc.cycle_code,
    pc.cycle_number,
    pc.start_date,
    pc.end_date,
    pc.review_open_date,
    pc.lock_date,
    pc.cycle_status,
    pg_catalog.count(cpc.id)::integer as assignment_count,
    pg_catalog.count(distinct cpc.pod_id)::integer as pod_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.is_partial_cycle = true
    )::integer as partial_cycle_count,
    coalesce(pg_catalog.sum(cpc.eligible_days), 0)::integer
        as total_eligible_days,
    coalesce(pg_catalog.sum(cpc.scored_days), 0)::integer
        as total_scored_days,
    case
        when coalesce(pg_catalog.sum(cpc.eligible_days), 0) > 0 then
            pg_catalog.round(
                coalesce(pg_catalog.sum(cpc.scored_days), 0)::numeric
                / coalesce(pg_catalog.sum(cpc.eligible_days), 0)::numeric
                * 100,
                2
            )
        else 0::numeric
    end as scoring_completion_percent,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'PENDING'
    )::integer as pending_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'DAILY_SCORING'
    )::integer as daily_scoring_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'AWAITING_REVIEWS'
    )::integer as awaiting_reviews_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'READY_TO_CALCULATE'
    )::integer as ready_to_calculate_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'CANDIDATE_REVIEW'
    )::integer as candidate_review_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'FINALIZED'
    )::integer as finalized_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.result_status = 'LOCKED'
    )::integer as locked_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.daily_component_score is not null
    )::integer as daily_summary_ready_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.lead_score is not null
    )::integer as lead_review_ready_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.hr_score is not null
    )::integer as hr_review_ready_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.lead_score is not null
          and cpc.hr_score is not null
    )::integer as review_summary_ready_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.exceptional_score is not null
    )::integer as exceptional_summary_ready_count,
    pg_catalog.count(cpc.id) filter (
        where cpc.final_score is not null
          and cpc.performance_band is not null
    )::integer as final_result_count,
    pg_catalog.round(pg_catalog.avg(cpc.final_score), 2)::numeric
        as average_final_score,
    pc.created_at as cycle_created_at,
    pc.updated_at as cycle_updated_at
from public.performance_cycles pc
left join public.candidate_performance_cycles cpc
    on cpc.cycle_id = pc.id
   and public.candidate_performance_cycle_is_visible(
       cpc.id,
       (current_timestamp at time zone 'Asia/Kolkata')::date
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
    pc.updated_at;

comment on view public.performance_cycle_overview_view is
    'Summarizes terminal history plus currently evaluable candidate-cycle rows and excludes removed pod members from current operational totals.';

revoke all privileges on public.performance_cycle_overview_view from public;
revoke all privileges on public.performance_cycle_overview_view from anon;
revoke all privileges on public.performance_cycle_overview_view from authenticated;
grant select on public.performance_cycle_overview_view to service_role;

create or replace function public.get_performance_cycle_overview()
returns setof public.performance_cycle_overview_view
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid := public.current_app_user_id();
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_has_elevated_access boolean;
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
        order by overview.cycle_number desc, overview.cycle_id desc;
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
        pg_catalog.count(cpc.id)::integer as assignment_count,
        pg_catalog.count(distinct cpc.pod_id)::integer as pod_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.is_partial_cycle = true
        )::integer as partial_cycle_count,
        coalesce(pg_catalog.sum(cpc.eligible_days), 0)::integer
            as total_eligible_days,
        coalesce(pg_catalog.sum(cpc.scored_days), 0)::integer
            as total_scored_days,
        case
            when coalesce(pg_catalog.sum(cpc.eligible_days), 0) > 0 then
                pg_catalog.round(
                    coalesce(pg_catalog.sum(cpc.scored_days), 0)::numeric
                    / coalesce(pg_catalog.sum(cpc.eligible_days), 0)::numeric
                    * 100,
                    2
                )
            else 0::numeric
        end as scoring_completion_percent,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'PENDING'
        )::integer as pending_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'DAILY_SCORING'
        )::integer as daily_scoring_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'AWAITING_REVIEWS'
        )::integer as awaiting_reviews_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'READY_TO_CALCULATE'
        )::integer as ready_to_calculate_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'CANDIDATE_REVIEW'
        )::integer as candidate_review_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'FINALIZED'
        )::integer as finalized_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.result_status = 'LOCKED'
        )::integer as locked_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.daily_component_score is not null
        )::integer as daily_summary_ready_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.lead_score is not null
        )::integer as lead_review_ready_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.hr_score is not null
        )::integer as hr_review_ready_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.lead_score is not null
              and cpc.hr_score is not null
        )::integer as review_summary_ready_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.exceptional_score is not null
        )::integer as exceptional_summary_ready_count,
        pg_catalog.count(cpc.id) filter (
            where cpc.final_score is not null
              and cpc.performance_band is not null
        )::integer as final_result_count,
        pg_catalog.round(pg_catalog.avg(cpc.final_score), 2)::numeric
            as average_final_score,
        pc.created_at as cycle_created_at,
        pc.updated_at as cycle_updated_at
    from public.performance_cycles pc
    join public.candidate_performance_cycles cpc
        on cpc.cycle_id = pc.id
    where public.candidate_performance_cycle_is_visible(
        cpc.id,
        v_business_date
    )
      and exists (
          select 1
          from public.pod_memberships pm
          where pm.user_id = v_actor_user_id
            and pm.pod_id = cpc.pod_id
            and pm.membership_type = 'HR_SITE_CONNECT'
            and public.current_user_has_role('HR_SITE_CONNECT')
            and pm.is_active = true
            and pm.effective_from <= v_business_date
            and (
                pm.effective_to is null
                or pm.effective_to >= v_business_date
            )
      )
      and not public.candidate_is_active_pod_lead_for_performance(
          cpc.candidate_id,
          cpc.pod_id,
          v_business_date
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
    order by pc.cycle_number desc, pc.id desc;
end;
$function$;

comment on function public.get_performance_cycle_overview() is
    'Returns cycle totals from terminal history and candidates who remain operationally eligible in the historical cycle pod, preserving existing HR role and pod authorization.';

revoke all privileges on function public.get_performance_cycle_overview()
from public, anon;
grant execute on function public.get_performance_cycle_overview()
to authenticated, service_role;

-- Prevent self-scoring and scoring removed members at the storage boundary.
-- These triggers protect every current and future caller, including the
-- existing Daily, HR Review, and Exceptional-score RPCs.
create or replace function public.enforce_performance_assessment_target()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_candidate_cycle_id uuid;
    v_target_candidate_id uuid;
    v_current_candidate_id uuid;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    if tg_table_name = 'daily_performance_entries'
       or tg_table_name = 'performance_reviews' then
        v_candidate_cycle_id := new.candidate_cycle_id;
    elsif tg_table_name = 'candidate_performance_cycles' then
        if new.exceptional_score is not distinct from old.exceptional_score then
            return new;
        end if;
        v_candidate_cycle_id := new.id;
    else
        raise exception using
            errcode = 'P0001',
            message = 'Performance assessment target guard is misconfigured.';
    end if;

    select cpc.candidate_id
    into v_target_candidate_id
    from public.candidate_performance_cycles cpc
    where cpc.id = v_candidate_cycle_id;

    if v_target_candidate_id is null then
        raise exception using
            errcode = 'P0002',
            message = 'Candidate performance cycle was not found.';
    end if;

    v_current_candidate_id := public.current_linked_candidate_id();

    if v_current_candidate_id is not null
       and v_current_candidate_id = v_target_candidate_id then
        raise exception using
            errcode = '42501',
            message = 'Evaluators cannot award performance points to themselves.';
    end if;

    if not public.candidate_performance_cycle_is_visible(
        v_candidate_cycle_id,
        v_business_date
    ) then
        raise exception using
            errcode = '42501',
            message = 'Performance scoring is unavailable because the candidate is no longer active in the cycle pod.';
    end if;

    return new;
end;
$function$;

revoke all privileges on function public.enforce_performance_assessment_target()
from public, anon, authenticated;

drop trigger if exists enforce_performance_assessment_target
on public.daily_performance_entries;
create trigger enforce_performance_assessment_target
before insert or update on public.daily_performance_entries
for each row
execute function public.enforce_performance_assessment_target();

drop trigger if exists enforce_performance_assessment_target
on public.performance_reviews;
create trigger enforce_performance_assessment_target
before insert or update on public.performance_reviews
for each row
execute function public.enforce_performance_assessment_target();

drop trigger if exists enforce_exceptional_assessment_target
on public.candidate_performance_cycles;
create trigger enforce_exceptional_assessment_target
before update of exceptional_score on public.candidate_performance_cycles
for each row
execute function public.enforce_performance_assessment_target();

commit;
