begin;

-- Canonical names distinguish the performance-based Volunteer Certificate from
-- an intern's ordinary certificate. These names do not represent a volunteer
-- candidate role or add any volunteer-status eligibility rule.
alter table public.exit_documents
    drop constraint if exists exit_documents_document_variant_check,
    drop constraint if exists exit_documents_variant_type_check;

alter table public.exit_document_requests
    drop constraint if exists exit_document_requests_variant_check;

update public.exit_documents
set document_variant = case document_variant
    when 'CERTIFICATE_INTERN' then 'INTERN_CERTIFICATE'
    when 'CERTIFICATE_POD_LEAD' then 'POD_LEAD_CERTIFICATE'
    when 'CERTIFICATE_VOLUNTEER' then 'VOLUNTEER_CERTIFICATE'
    when 'LOR_INTERN' then 'INTERN_LOR'
    when 'LOR_POD_LEAD' then 'POD_LEAD_LOR'
    when 'LOR_OPERATIONS_ASSOCIATE' then 'OPERATIONS_ASSOCIATE_LOR'
    else document_variant
end;

update public.exit_document_requests
set document_variant = case document_variant
    when 'CERTIFICATE_INTERN' then 'INTERN_CERTIFICATE'
    when 'CERTIFICATE_POD_LEAD' then 'POD_LEAD_CERTIFICATE'
    when 'CERTIFICATE_VOLUNTEER' then 'VOLUNTEER_CERTIFICATE'
    when 'LOR_INTERN' then 'INTERN_LOR'
    when 'LOR_POD_LEAD' then 'POD_LEAD_LOR'
    when 'LOR_OPERATIONS_ASSOCIATE' then 'OPERATIONS_ASSOCIATE_LOR'
    else document_variant
end;

alter table public.exit_documents
    add constraint exit_documents_document_variant_check
        check (
            document_variant is null
            or document_variant in (
                'INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE',
                'INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR'
            )
        ),
    add constraint exit_documents_variant_type_check
        check (
            document_variant is null
            or (
                document_variant in ('INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE')
                and document_type = 'CERTIFICATE'
            )
            or (
                document_variant in ('INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR')
                and document_type = 'LOR'
            )
        );

alter table public.exit_document_requests
    add constraint exit_document_requests_variant_check
        check (
            document_variant in (
                'INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE',
                'INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR'
            )
        );

create or replace function public.get_exit_document_eligibility(
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
    v_certificate_variants text[] := array['INTERN_CERTIFICATE', 'VOLUNTEER_CERTIFICATE']::text[];
    v_lor_variants text[] := array['INTERN_LOR']::text[];
    v_business_date date := (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    v_actor_user_id := public.current_app_user_id();
    if v_actor_user_id is null or not public.current_user_has_any_role(
        array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
              'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE']::text[]
    ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;
    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;

    select ec.* into v_case from public.exit_cases ec where ec.exit_case_id = p_exit_case_id;
    if v_case.exit_case_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found.';
    end if;

    -- Only the lifecycle linked by this exit case is authoritative. The query
    -- intentionally never reads original_end_date.
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
        join public.users u on u.id = cua.user_id and u.status = 'active'
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
        v_certificate_variants := array_append(v_certificate_variants, 'POD_LEAD_CERTIFICATE');
        v_lor_variants := array_append(v_lor_variants, 'POD_LEAD_LOR');
    end if;
    if v_is_operations_associate then
        v_lor_variants := array_append(v_lor_variants, 'OPERATIONS_ASSOCIATE_LOR');
    end if;

    return query select
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

create or replace function public.request_exit_documents(
    p_exit_case_id uuid,
    p_document_variants text[],
    p_allow_date_mismatch boolean default false
)
returns table (request_id uuid, document_variant text, status text)
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_eligibility record;
begin
    v_actor_user_id := public.current_app_user_id();
    if v_actor_user_id is null or not public.current_user_has_any_role(
        array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
              'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE']::text[]
    ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;
    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;
    if p_allow_date_mismatch is null then
        raise exception using errcode = '22023', message = 'Date mismatch confirmation is required.';
    end if;
    if p_document_variants is null or cardinality(p_document_variants) = 0 then
        raise exception using errcode = '22023', message = 'Select at least one document variant.';
    end if;
    if cardinality(p_document_variants) > 6
       or exists (
           select 1 from unnest(p_document_variants) as requested(variant)
           where requested.variant not in (
               'INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE',
               'INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR'
           )
       )
       or cardinality(p_document_variants) <> (
           select count(distinct requested.variant)
           from unnest(p_document_variants) as requested(variant)
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

    -- Calls the secure function after locking, which independently resolves the
    -- case's lifecycle/current_end_date and the allowed variants server-side.
    select * into v_eligibility
    from public.get_exit_document_eligibility(p_exit_case_id);

    if v_eligibility.warning_required and not p_allow_date_mismatch then
        raise exception using
            errcode = 'P0001',
            message = 'Exit date does not match the current internship end date. Explicit HR confirmation is required.';
    end if;
    if exists (
        select 1 from unnest(p_document_variants) as requested(variant)
        where requested.variant <> all(v_eligibility.allowed_variants)
    ) then
        raise exception using errcode = '22023', message = 'One or more selected document variants are not allowed for this candidate.';
    end if;

    insert into public.exit_document_requests (
        exit_case_id, document_variant, status, requested_by, requested_at, created_at, updated_at
    )
    select
        v_case.exit_case_id, requested.variant, 'REQUESTED', v_actor_user_id,
        pg_catalog.now(), pg_catalog.now(), pg_catalog.now()
    from unnest(p_document_variants) as requested(variant)
    on conflict (exit_case_id, document_variant) do nothing;

    return query
    select ecr.request_id, ecr.document_variant, ecr.status
    from public.exit_document_requests ecr
    where ecr.exit_case_id = v_case.exit_case_id
      and ecr.document_variant = any(p_document_variants)
    order by ecr.document_variant;
end;
$function$;

create or replace function public.get_hr_exit_document_request_statuses(
    p_exit_case_ids uuid[] default null
)
returns table (exit_case_id uuid, certificate_status text, lor_status text)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_certificate_variants constant text[] := array['INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE'];
    v_lor_variants constant text[] := array['INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR'];
begin
    v_actor_user_id := public.current_app_user_id();
    if v_actor_user_id is null or not public.current_user_has_any_role(
        array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
              'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE']::text[]
    ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    return query
    select
        ecr.exit_case_id,
        case
            when count(*) filter (where ecr.document_variant = any(v_certificate_variants)) = 0 then 'NOT_REQUESTED'
            when bool_or(ecr.status = 'PROCESSING') filter (where ecr.document_variant = any(v_certificate_variants)) then 'PROCESSING'
            when bool_or(ecr.status = 'REQUESTED') filter (where ecr.document_variant = any(v_certificate_variants)) then 'REQUESTED'
            when bool_or(ecr.status = 'GENERATED') filter (where ecr.document_variant = any(v_certificate_variants)) then 'GENERATED'
            when bool_or(ecr.status = 'FAILED') filter (where ecr.document_variant = any(v_certificate_variants)) then 'FAILED'
            else 'EMAILED'
        end::text,
        case
            when count(*) filter (where ecr.document_variant = any(v_lor_variants)) = 0 then 'NOT_REQUESTED'
            when bool_or(ecr.status = 'PROCESSING') filter (where ecr.document_variant = any(v_lor_variants)) then 'PROCESSING'
            when bool_or(ecr.status = 'REQUESTED') filter (where ecr.document_variant = any(v_lor_variants)) then 'REQUESTED'
            when bool_or(ecr.status = 'GENERATED') filter (where ecr.document_variant = any(v_lor_variants)) then 'GENERATED'
            when bool_or(ecr.status = 'FAILED') filter (where ecr.document_variant = any(v_lor_variants)) then 'FAILED'
            else 'EMAILED'
        end::text
    from public.exit_document_requests ecr
    where p_exit_case_ids is null or ecr.exit_case_id = any(p_exit_case_ids)
    group by ecr.exit_case_id;
end;
$function$;

comment on function public.get_exit_document_eligibility(uuid) is
    'Returns server-derived issuance data using canonical document variants. Volunteer Certificate is performance-based and not a volunteer-role determination.';

comment on function public.request_exit_documents(uuid, text[], boolean) is
    'Creates idempotent request records with canonical document variants; no automation jobs are created.';

commit;
