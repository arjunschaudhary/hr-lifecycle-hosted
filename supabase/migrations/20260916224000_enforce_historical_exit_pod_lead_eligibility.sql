begin;

-- Certificate/LOR Pod Lead variants belong to the exiting candidate when that
-- candidate was a Pod Lead for the snapshotted exit pod on the stored exit
-- date. The server-controlled pod membership interval is the historical role
-- authority. Mutable account-activation and user-role timestamps are not.
create or replace function public.exit_case_candidate_was_historical_pod_lead(
    p_exit_case_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    select exists (
        select 1
        from public.exit_cases ec
        join public.candidate_user_accounts cua
          on cua.candidate_id = ec.candidate_id
        join public.pod_memberships pm
          on pm.user_id = cua.user_id
         and pm.candidate_id is null
         and pm.membership_type = 'POD_LEAD'
         and pm.pod_id = ec.pod_id
         and pm.effective_from <= ec.exit_date
         and (pm.effective_to is null or pm.effective_to >= ec.exit_date)
        where ec.exit_case_id = p_exit_case_id
          and ec.pod_id is not null
    );
$function$;

comment on function public.exit_case_candidate_was_historical_pod_lead(uuid) is
    'Internal historical Certificate/LOR predicate. It maps the exiting candidate to an application user and requires a server-controlled POD_LEAD membership for the snapshotted pod covering the stored exit date; mutable account and user-role timestamps are not historical authority, and unresolved snapshots fail closed.';

revoke execute on function public.exit_case_candidate_was_historical_pod_lead(uuid) from public;
revoke execute on function public.exit_case_candidate_was_historical_pod_lead(uuid) from anon;
revoke execute on function public.exit_case_candidate_was_historical_pod_lead(uuid) from authenticated;
grant execute on function public.exit_case_candidate_was_historical_pod_lead(uuid) to service_role;

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

    v_is_pod_lead := public.exit_case_candidate_was_historical_pod_lead(
        v_case.exit_case_id
    );
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
    'Internal Certificate/LOR eligibility calculation. Pod Lead variants use the shared historical exit-case predicate; unresolved pod snapshots and non-covering historical role or membership intervals fail closed.';

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
       or v_request.job_id is distinct from v_job.job_id
       or v_request.requested_by is distinct from v_job.requested_by then
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

    v_is_pod_lead := public.exit_case_candidate_was_historical_pod_lead(
        v_case.exit_case_id
    );
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
    'Service-role worker claim with advisory and row locking. Request/job actor identity must match, and Pod Lead variants use the same historical exit-case predicate as eligibility.';

revoke execute on function public.claim_exit_document_job(uuid) from public;
revoke execute on function public.claim_exit_document_job(uuid) from anon;
revoke execute on function public.claim_exit_document_job(uuid) from authenticated;
grant execute on function public.claim_exit_document_job(uuid) to service_role;

commit;
