begin;

-- Prevent a concurrent Exit initiation from inserting another unresolved row
-- between the backfill and the replacement of initiate_candidate_exit().
lock table public.exit_cases in share row exclusive mode;

-- Backfill only exit cases for which one distinct historical candidate pod is
-- provable on the stored exit date. Historical rows with zero or multiple
-- qualifying pods intentionally remain unresolved.
with uniquely_resolved_exit_pods as (
    select
        ec.exit_case_id,
        (pg_catalog.array_agg(distinct pm.pod_id order by pm.pod_id))[1] as pod_id
    from public.exit_cases ec
    join public.pod_memberships pm
      on pm.candidate_id = ec.candidate_id
     and pm.user_id is null
     and pm.membership_type = 'CANDIDATE'
     and pm.effective_from <= ec.exit_date
     and (pm.effective_to is null or pm.effective_to >= ec.exit_date)
    where ec.pod_id is null
    group by ec.exit_case_id
    having pg_catalog.count(distinct pm.pod_id) = 1
)
update public.exit_cases ec
set pod_id = resolved.pod_id
from uniquely_resolved_exit_pods resolved
where ec.exit_case_id = resolved.exit_case_id
  and ec.pod_id is null;

comment on column public.exit_cases.pod_id is
    'Historical pod snapshot for this Exit case. It is resolved from the candidate CANDIDATE pod membership covering exit_date and must not be inferred from department or current membership.';

create or replace function public.initiate_candidate_exit(
    p_candidate_id uuid,
    p_exit_type text,
    p_exit_date date
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
    v_case public.exit_cases%rowtype;
    v_candidate_pod_id uuid;
    v_candidate_pod_count bigint := 0;
    v_exit_type text := pg_catalog.upper(nullif(pg_catalog.btrim(p_exit_type), ''));
    v_timestamp timestamptz := pg_catalog.now();
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN',
               'HR_LEAD',
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE',
               'HR_EXECUTIVE_LEAD',
               'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using
            errcode = '42501',
            message = 'Authorized HR access is required.';
    end if;

    if p_candidate_id is null then
        raise exception using errcode = '22023', message = 'Candidate is required.';
    end if;

    if v_exit_type is null
       or v_exit_type not in ('COMPLETED_TERM', 'EARLY_EXIT', 'TERMINATED') then
        raise exception using errcode = '22023', message = 'A valid Exit type is required.';
    end if;

    if p_exit_date is null then
        raise exception using errcode = '22023', message = 'Exit date is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('candidate-exit:' || p_candidate_id::text, 0)
    );

    select mc.*
    into v_candidate
    from public.master_candidates mc
    where mc.candidate_id = p_candidate_id;

    if v_candidate.candidate_id is null then
        raise exception using errcode = 'P0001', message = 'Candidate was not found.';
    end if;

    select hl.*
    into v_lifecycle
    from public.hr_lifecycle hl
    where hl.candidate_id = p_candidate_id
    order by hl.updated_at desc, hl.lifecycle_id desc
    limit 1;

    if v_lifecycle.lifecycle_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'No lifecycle record was found for this candidate.';
    end if;

    if not exists (
        select 1
        from public.hr_lifecycle hl
        left join public.hr_offer_letters hol
          on hol.candidate_id = hl.candidate_id
        where hl.candidate_id = p_candidate_id
          and (
              hl.lifecycle_status = 'ACTIVE'
              or hol.offer_status = 'OFFER_LETTER_SENT'
          )
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Exit can only be initiated for a candidate in the Active Interns workflow.';
    end if;

    if exists (
        select 1
        from public.exit_cases ec
        where ec.candidate_id = p_candidate_id
          and ec.overall_status <> 'COMPLETED'
    ) then
        raise exception using
            errcode = '23505',
            message = 'An Exit process has already been initiated for this candidate.';
    end if;

    select
        pg_catalog.count(distinct pm.pod_id),
        (pg_catalog.array_agg(distinct pm.pod_id order by pm.pod_id))[1]
    into v_candidate_pod_count, v_candidate_pod_id
    from public.pod_memberships pm
    where pm.candidate_id = p_candidate_id
      and pm.user_id is null
      and pm.membership_type = 'CANDIDATE'
      and pm.effective_from <= p_exit_date
      and (pm.effective_to is null or pm.effective_to >= p_exit_date);

    if v_candidate_pod_count = 0 then
        raise exception using
            errcode = 'P0001',
            message = 'Exit cannot be initiated because no candidate pod membership covers the exit date.';
    end if;

    if v_candidate_pod_count > 1 then
        raise exception using
            errcode = 'P0001',
            message = 'Exit cannot be initiated because multiple candidate pods cover the exit date.';
    end if;

    begin
        insert into public.exit_cases (
            candidate_id,
            lifecycle_id,
            pod_id,
            initiated_by,
            mid,
            pod_name_snapshot,
            exit_date,
            exit_type,
            overall_status,
            candidate_form_completed,
            hr_form_completed,
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            v_lifecycle.lifecycle_id,
            v_candidate_pod_id,
            v_actor_user_id,
            v_lifecycle.mid,
            v_candidate.department,
            p_exit_date,
            v_exit_type,
            'INITIATED',
            false,
            false,
            v_timestamp,
            v_timestamp
        )
        returning * into v_case;
    exception
        when unique_violation then
            raise exception using
                errcode = '23505',
                message = 'An Exit process has already been initiated for this candidate.';
    end;

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
        'EXIT_INITIATED',
        null,
        'INITIATED',
        'Exit process initiated by an authorized HR user',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'exit_case_id', v_case.exit_case_id,
            'exit_type', v_case.exit_type,
            'exit_date', v_case.exit_date,
            'pod_id', v_case.pod_id
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return pg_catalog.jsonb_build_object(
        'exitCaseId', v_case.exit_case_id,
        'candidateId', v_case.candidate_id,
        'lifecycleId', v_case.lifecycle_id,
        'mid', v_case.mid,
        'podNameSnapshot', v_case.pod_name_snapshot,
        'exitDate', v_case.exit_date,
        'exitType', v_case.exit_type,
        'overallStatus', v_case.overall_status,
        'candidateFormCompleted', v_case.candidate_form_completed,
        'hrFormCompleted', v_case.hr_form_completed,
        'createdAt', v_case.created_at
    );
end;
$function$;

comment on function public.initiate_candidate_exit(uuid, text, date) is
    'Atomically creates one open Exit case and stores the one historical candidate pod membership covering exit_date. Zero or multiple qualifying pods fail safely; department is not used as pod authority.';

revoke execute on function public.initiate_candidate_exit(uuid, text, date) from public;
revoke execute on function public.initiate_candidate_exit(uuid, text, date) from anon;
grant execute on function public.initiate_candidate_exit(uuid, text, date) to authenticated;
grant execute on function public.initiate_candidate_exit(uuid, text, date) to service_role;

-- Keep unresolved historical cases fail-closed until the shared historical
-- POD_LEAD authorization helper is introduced in a later forward migration.
create or replace function public.get_exit_document_eligibility_internal(
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
        where v_case.pod_id is not null
          and cua.candidate_id = v_case.candidate_id
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

comment on function public.get_exit_document_eligibility_internal(uuid) is
    'Internal Certificate/LOR eligibility calculation. Unresolved exit-case pod snapshots fail closed for Pod Lead variants pending the shared historical authorization helper.';

revoke execute on function public.get_exit_document_eligibility_internal(uuid) from public;
revoke execute on function public.get_exit_document_eligibility_internal(uuid) from anon;
revoke execute on function public.get_exit_document_eligibility_internal(uuid) from authenticated;
grant execute on function public.get_exit_document_eligibility_internal(uuid) to service_role;

create or replace function public.claim_exit_document_job(
    p_job_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_case public.exit_cases%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_candidate public.master_candidates%rowtype;
    v_payload_case_id uuid;
    v_payload_request_id uuid;
    v_variant text;
    v_is_pod_lead boolean := false;
    v_is_operations_associate boolean := false;
    v_date_matches boolean := false;
    v_allowed_variants text[] := array['INTERN_CERTIFICATE', 'VOLUNTEER_CERTIFICATE', 'INTERN_LOR']::text[];
    v_business_date date := (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using errcode = '22023', message = 'Automation job ID is required.';
    end if;

    if auth.role() is distinct from 'service_role' then
        raise exception using errcode = '42501', message = 'Service-role worker access is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-document-job:' || p_job_id::text, 0)
    );
    select aj.* into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;
    if v_job.job_id is null then
        raise exception using errcode = 'P0001', message = 'Exit-document automation job was not found.';
    end if;
    if v_job.job_type is distinct from 'EXIT_DOCUMENT' then
        raise exception using errcode = 'P0001', message = 'Automation job is not an exit-document job.';
    end if;
    if v_job.job_status = 'PROCESSING' then
        raise exception using errcode = 'P0001', message = 'Exit-document job is already being processed.';
    end if;
    if v_job.job_status not in ('PENDING', 'RETRY') then
        raise exception using errcode = 'P0001', message = 'Exit-document job is not claimable.';
    end if;
    if v_job.provider_message_id is not null or v_job.provider_accepted_at is not null then
        raise exception using errcode = 'P0001', message = 'Exit-document job has an unexpected provider state.';
    end if;

    begin
        v_payload_case_id := (v_job.payload ->> 'exit_case_id')::uuid;
        v_payload_request_id := (v_job.payload ->> 'exit_document_request_id')::uuid;
    exception when invalid_text_representation then
        raise exception using errcode = 'P0001', message = 'Exit-document job payload identifiers are invalid.';
    end;
    v_variant := v_job.payload ->> 'document_variant';
    if v_payload_case_id is null or v_payload_request_id is null
       or v_variant not in (
           'INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE',
           'INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR'
       ) then
        raise exception using errcode = 'P0001', message = 'Exit-document job payload is incomplete or invalid.';
    end if;

    select ecr.* into v_request
    from public.exit_document_requests ecr
    where ecr.request_id = v_payload_request_id
    for update;
    if v_request.request_id is null
       or v_request.exit_case_id is distinct from v_payload_case_id
       or v_request.document_variant is distinct from v_variant
       or v_request.job_id is distinct from v_job.job_id then
        raise exception using errcode = 'P0001', message = 'Exit-document request does not match its automation job.';
    end if;
    if v_request.status not in ('REQUESTED', 'FAILED') then
        raise exception using errcode = 'P0001', message = 'Exit-document request is not claimable.';
    end if;

    select ec.* into v_case from public.exit_cases ec
    where ec.exit_case_id = v_payload_case_id
    for share;
    if v_case.exit_case_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found during document job revalidation.';
    end if;
    select hl.* into v_lifecycle from public.hr_lifecycle hl
    where hl.lifecycle_id = v_case.lifecycle_id
    for share;
    if v_lifecycle.lifecycle_id is null
       or v_lifecycle.candidate_id is distinct from v_case.candidate_id then
        raise exception using errcode = 'P0001', message = 'Exit case lifecycle was not found during document job revalidation.';
    end if;
    select mc.* into v_candidate from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id
    for share;
    if v_candidate.candidate_id is null or v_job.candidate_id is distinct from v_case.candidate_id then
        raise exception using errcode = 'P0001', message = 'Exit-document job candidate is invalid.';
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
        where v_case.pod_id is not null
          and cua.candidate_id = v_case.candidate_id
          and cua.account_status = 'ACTIVE'
    ) into v_is_pod_lead;
    v_is_operations_associate := v_candidate.applied_role = 'Operations Associate Intern';
    v_date_matches := v_case.exit_date is not distinct from v_lifecycle.current_end_date;
    if v_is_pod_lead then
        v_allowed_variants := v_allowed_variants || array['POD_LEAD_CERTIFICATE', 'POD_LEAD_LOR']::text[];
    end if;
    if v_is_operations_associate then
        v_allowed_variants := v_allowed_variants || array['OPERATIONS_ASSOCIATE_LOR']::text[];
    end if;
    if v_variant <> all(v_allowed_variants) then
        raise exception using errcode = 'P0001', message = 'Requested document variant is no longer allowed.';
    end if;
    if not v_date_matches and not v_request.date_mismatch_override_approved then
        raise exception using
            errcode = 'P0001',
            message = 'Exit date mismatch requires an explicit HR override before document processing.';
    end if;

    update public.automation_jobs
    set
        job_status = 'PROCESSING',
        attempt_count = attempt_count + 1,
        last_attempt_at = v_now,
        completed_at = null,
        error_message = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;
    update public.exit_document_requests
    set status = 'PROCESSING', error_message = null
    where request_id = v_request.request_id;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status,
        'attemptCount', v_job.attempt_count,
        'exitCaseId', v_payload_case_id,
        'exitDocumentRequestId', v_payload_request_id,
        'documentVariant', v_variant
    );
end;
$function$;

comment on function public.claim_exit_document_job(uuid) is
    'Service-role worker claim with advisory and row locking. Unresolved exit-case pod snapshots fail closed for Pod Lead variants; all other existing job revalidation remains unchanged.';

revoke execute on function public.claim_exit_document_job(uuid) from public;
revoke execute on function public.claim_exit_document_job(uuid) from anon;
revoke execute on function public.claim_exit_document_job(uuid) from authenticated;
grant execute on function public.claim_exit_document_job(uuid) to service_role;

create or replace function public.resolve_exit_case_pod_snapshot(
    p_exit_case_id uuid,
    p_pod_id uuid,
    p_resolution_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_pod public.pods%rowtype;
    v_resolution_reason text := nullif(pg_catalog.btrim(p_resolution_reason), '');
    v_timestamp timestamptz := pg_catalog.now();
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not pg_catalog.coalesce(public.current_user_has_role('HR_SITE_CONNECT_LEAD'), false) then
        raise exception using
            errcode = '42501',
            message = 'HR Site Connect Lead access is required.';
    end if;

    if p_exit_case_id is null or p_pod_id is null then
        raise exception using
            errcode = '22023',
            message = 'Exit case and pod are required.';
    end if;

    if v_resolution_reason is null then
        raise exception using
            errcode = '22023',
            message = 'A resolution reason is required.';
    end if;

    if pg_catalog.length(v_resolution_reason) > 1000 then
        raise exception using
            errcode = '22023',
            message = 'Resolution reason must be 1000 characters or fewer.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-case-pod-snapshot:' || p_exit_case_id::text, 0)
    );

    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.exit_case_id = p_exit_case_id
    for update;

    if v_case.exit_case_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found.';
    end if;

    if v_case.pod_id is not null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case pod is already resolved and cannot be replaced.';
    end if;

    select p.*
    into v_pod
    from public.pods p
    where p.id = p_pod_id;

    if v_pod.id is null then
        raise exception using errcode = 'P0001', message = 'Pod was not found.';
    end if;

    update public.exit_cases ec
    set pod_id = v_pod.id,
        updated_at = v_timestamp
    where ec.exit_case_id = v_case.exit_case_id
      and ec.pod_id is null
    returning * into v_case;

    if v_case.pod_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case pod could not be resolved.';
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
    ) values (
        v_case.candidate_id,
        'EXIT_POD_SNAPSHOT_MANUALLY_RESOLVED',
        'Historical Exit pod snapshot resolved by HR Site Connect Lead',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'exit_case_id', v_case.exit_case_id,
            'candidate_id', v_case.candidate_id,
            'exit_date', v_case.exit_date,
            'pod_id', v_case.pod_id,
            'pod_code', v_pod.pod_code,
            'pod_name', v_pod.pod_name,
            'pod_is_active', v_pod.is_active,
            'resolution_method', 'MANUAL',
            'resolution_reason', v_resolution_reason
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return pg_catalog.jsonb_build_object(
        'exitCaseId', v_case.exit_case_id,
        'candidateId', v_case.candidate_id,
        'exitDate', v_case.exit_date,
        'podId', v_case.pod_id,
        'resolvedBy', v_actor_user_id,
        'resolvedAt', v_timestamp
    );
end;
$function$;

comment on function public.resolve_exit_case_pod_snapshot(uuid, uuid, text) is
    'Allows only an active HR_SITE_CONNECT_LEAD to resolve one currently-null historical Exit pod snapshot to an existing pod with a required audit reason. Existing snapshots cannot be replaced and every successful resolution is audited.';

revoke execute on function public.resolve_exit_case_pod_snapshot(uuid, uuid, text) from public;
revoke execute on function public.resolve_exit_case_pod_snapshot(uuid, uuid, text) from anon;
grant execute on function public.resolve_exit_case_pod_snapshot(uuid, uuid, text) to authenticated;
grant execute on function public.resolve_exit_case_pod_snapshot(uuid, uuid, text) to service_role;

commit;
