begin;

-- Replace the Phase 1 read contract so the linked current-end-date comparison
-- remains authoritative but is exposed as a warning, never a list exclusion.
drop function if exists public.get_exit_document_eligibility(uuid);

create function public.get_exit_document_eligibility(
    p_exit_case_id uuid
)
returns table (
    eligible boolean,
    reason text,
    date_matches boolean,
    warning_required boolean,
    exit_date date,
    current_end_date date,
    candidate_id uuid,
    candidate_name text,
    candidate_email text,
    applied_role text,
    is_pod_lead boolean,
    is_operations_associate boolean,
    allowed_variants text[],
    allowed_certificate_variants text[],
    allowed_lor_variants text[]
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_candidate public.master_candidates%rowtype;
    v_is_pod_lead boolean := false;
    v_is_operations_associate boolean := false;
    v_date_matches boolean := false;
    v_certificate_variants text[] := array[
        'CERTIFICATE_INTERN',
        'CERTIFICATE_VOLUNTEER'
    ]::text[];
    v_lor_variants text[] := array['LOR_INTERN']::text[];
    v_business_date date := (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;

    select ec.* into v_case
    from public.exit_cases ec
    where ec.exit_case_id = p_exit_case_id;

    if v_case.exit_case_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found.';
    end if;

    -- Always resolve this exact lifecycle row. original_end_date is not read.
    select hl.* into v_lifecycle
    from public.hr_lifecycle hl
    where hl.lifecycle_id = v_case.lifecycle_id;

    if v_lifecycle.lifecycle_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case lifecycle record was not found.';
    end if;

    select mc.* into v_candidate
    from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id;

    if v_candidate.candidate_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case candidate was not found.';
    end if;

    select exists (
        select 1
        from public.candidate_user_accounts cua
        join public.users u
          on u.id = cua.user_id
         and u.status = 'active'
        join public.pod_memberships pm
          on pm.user_id = u.id
         and pm.candidate_id is null
         and pm.membership_type = 'POD_LEAD'
         and pm.is_active = true
         and pm.effective_from <= v_business_date
         and (pm.effective_to is null or pm.effective_to >= v_business_date)
        where cua.candidate_id = v_case.candidate_id
          and cua.account_status = 'ACTIVE'
    ) into v_is_pod_lead;

    v_is_operations_associate := v_candidate.applied_role = 'Operations Associate Intern';
    v_date_matches := v_case.exit_date is not distinct from v_lifecycle.current_end_date;

    if v_is_pod_lead then
        v_certificate_variants := array_append(v_certificate_variants, 'CERTIFICATE_POD_LEAD');
        v_lor_variants := array_append(v_lor_variants, 'LOR_POD_LEAD');
    end if;

    if v_is_operations_associate then
        v_lor_variants := array_append(v_lor_variants, 'LOR_OPERATIONS_ASSOCIATE');
    end if;

    return query
    select
        true,
        case when v_date_matches then 'DATE_MATCHES' else 'DATE_MISMATCH_WARNING' end,
        v_date_matches,
        not v_date_matches,
        v_case.exit_date,
        v_lifecycle.current_end_date,
        v_case.candidate_id,
        v_candidate.full_name::text,
        v_candidate.email::text,
        v_candidate.applied_role::text,
        v_is_pod_lead,
        v_is_operations_associate,
        v_certificate_variants || v_lor_variants,
        v_certificate_variants,
        v_lor_variants;
end;
$function$;

comment on function public.get_exit_document_eligibility(uuid) is
    'Returns server-derived issuance data for one Exit case. exit_date is compared only to the linked current_end_date; a mismatch returns allowed variants with warning_required=true.';

revoke execute on function public.get_exit_document_eligibility(uuid) from public;
revoke execute on function public.get_exit_document_eligibility(uuid) from anon;
grant execute on function public.get_exit_document_eligibility(uuid) to authenticated;
grant execute on function public.get_exit_document_eligibility(uuid) to service_role;

create or replace function public.request_exit_documents(
    p_exit_case_id uuid,
    p_document_variants text[],
    p_allow_date_mismatch boolean default false
)
returns table (
    request_id uuid,
    document_variant text,
    status text
)
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_candidate public.master_candidates%rowtype;
    v_is_pod_lead boolean := false;
    v_is_operations_associate boolean := false;
    v_allowed_variants text[] := array[
        'CERTIFICATE_INTERN',
        'CERTIFICATE_VOLUNTEER',
        'LOR_INTERN'
    ]::text[];
    v_business_date date := (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;

    if p_allow_date_mismatch is null then
        raise exception using errcode = '22023', message = 'Date mismatch confirmation is required.';
    end if;

    if p_document_variants is null
       or cardinality(p_document_variants) = 0 then
        raise exception using errcode = '22023', message = 'Select at least one document variant.';
    end if;

    if cardinality(p_document_variants) > 6
       or exists (
           select 1
           from unnest(p_document_variants) as variant(value)
           where value not in (
               'CERTIFICATE_INTERN', 'CERTIFICATE_POD_LEAD', 'CERTIFICATE_VOLUNTEER',
               'LOR_INTERN', 'LOR_POD_LEAD', 'LOR_OPERATIONS_ASSOCIATE'
           )
       )
       or cardinality(p_document_variants) <> (
           select count(distinct value)
           from unnest(p_document_variants) as variant(value)
       ) then
        raise exception using errcode = '22023', message = 'Selected document variants are invalid.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-document-request:' || p_exit_case_id::text, 0)
    );

    select ec.* into v_case
    from public.exit_cases ec
    where ec.exit_case_id = p_exit_case_id
    for update;

    if v_case.exit_case_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found.';
    end if;

    -- Re-check the lifecycle through the exit case itself. Never use original_end_date.
    select hl.* into v_lifecycle
    from public.hr_lifecycle hl
    where hl.lifecycle_id = v_case.lifecycle_id;

    if v_lifecycle.lifecycle_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case lifecycle record was not found.';
    end if;

    if v_case.exit_date is distinct from v_lifecycle.current_end_date
       and not p_allow_date_mismatch then
        raise exception using
            errcode = 'P0001',
            message = 'Exit date does not match the current internship end date. Explicit HR confirmation is required.';
    end if;

    select mc.* into v_candidate
    from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id;

    if v_candidate.candidate_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case candidate was not found.';
    end if;

    select exists (
        select 1
        from public.candidate_user_accounts cua
        join public.users u
          on u.id = cua.user_id
         and u.status = 'active'
        join public.pod_memberships pm
          on pm.user_id = u.id
         and pm.candidate_id is null
         and pm.membership_type = 'POD_LEAD'
         and pm.is_active = true
         and pm.effective_from <= v_business_date
         and (pm.effective_to is null or pm.effective_to >= v_business_date)
        where cua.candidate_id = v_case.candidate_id
          and cua.account_status = 'ACTIVE'
    ) into v_is_pod_lead;

    v_is_operations_associate := v_candidate.applied_role = 'Operations Associate Intern';

    if v_is_pod_lead then
        v_allowed_variants := array_append(v_allowed_variants, 'CERTIFICATE_POD_LEAD');
        v_allowed_variants := array_append(v_allowed_variants, 'LOR_POD_LEAD');
    end if;

    if v_is_operations_associate then
        v_allowed_variants := array_append(v_allowed_variants, 'LOR_OPERATIONS_ASSOCIATE');
    end if;

    if exists (
        select 1
        from unnest(p_document_variants) as requested(variant)
        where requested.variant <> all(v_allowed_variants)
    ) then
        raise exception using errcode = '22023', message = 'One or more selected document variants are not allowed for this candidate.';
    end if;

    insert into public.exit_document_requests (
        exit_case_id,
        document_variant,
        status,
        requested_by,
        requested_at,
        created_at,
        updated_at
    )
    select
        v_case.exit_case_id,
        requested.variant,
        'REQUESTED',
        v_actor_user_id,
        pg_catalog.now(),
        pg_catalog.now(),
        pg_catalog.now()
    from unnest(p_document_variants) as requested(variant)
    on conflict (exit_case_id, document_variant) do nothing;

    -- The case/variant uniqueness key makes repeat identical submissions
    -- idempotent without creating duplicate requests or automation jobs.
    return query
    select
        ecr.request_id,
        ecr.document_variant,
        ecr.status
    from public.exit_document_requests ecr
    where ecr.exit_case_id = v_case.exit_case_id
      and ecr.document_variant = any(p_document_variants)
    order by ecr.document_variant;
end;
$function$;

comment on function public.request_exit_documents(uuid, text[], boolean) is
    'Creates idempotent Phase 2 document requests after server-side authorization, variant validation, Pod Lead/Operations Associate resolution, and current-end-date mismatch confirmation. It creates no automation jobs.';

revoke execute on function public.request_exit_documents(uuid, text[], boolean) from public;
revoke execute on function public.request_exit_documents(uuid, text[], boolean) from anon;
grant execute on function public.request_exit_documents(uuid, text[], boolean) to authenticated;
grant execute on function public.request_exit_documents(uuid, text[], boolean) to service_role;

commit;
