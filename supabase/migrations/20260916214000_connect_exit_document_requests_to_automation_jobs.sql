begin;

-- Persist the explicit HR decision that permits a date mismatch. The worker
-- must re-check this database-owned value; it must never rely on frontend data.
alter table public.exit_document_requests
    add column if not exists date_mismatch_override_approved boolean not null default false;

create unique index if not exists uq_exit_document_requests_job_id
    on public.exit_document_requests (job_id)
    where job_id is not null;

create index if not exists idx_automation_jobs_exit_document_pending
    on public.automation_jobs (scheduled_at, created_at)
    where job_type = 'EXIT_DOCUMENT'
      and job_status in ('PENDING', 'RETRY');

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
    v_request public.exit_document_requests%rowtype;
    v_job public.automation_jobs%rowtype;
    v_variant text;
    v_idempotency_key text;
    v_now timestamptz := pg_catalog.now();
    v_override_approved boolean := false;
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

    -- This function resolves exactly exit_cases.lifecycle_id and compares only
    -- current_end_date. It also resolves Pod Lead and Operations Associate.
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

    v_override_approved := v_eligibility.warning_required and p_allow_date_mismatch;

    foreach v_variant in array p_document_variants loop
        insert into public.exit_document_requests (
            exit_case_id,
            document_variant,
            status,
            requested_by,
            requested_at,
            date_mismatch_override_approved,
            created_at,
            updated_at
        ) values (
            v_case.exit_case_id,
            v_variant,
            'REQUESTED',
            v_actor_user_id,
            v_now,
            v_override_approved,
            v_now,
            v_now
        )
        on conflict (exit_case_id, document_variant) do update
        set date_mismatch_override_approved =
            public.exit_document_requests.date_mismatch_override_approved
            or excluded.date_mismatch_override_approved
        returning * into v_request;

        v_idempotency_key := 'EXIT_DOCUMENT:' || v_case.exit_case_id::text || ':' || v_variant;
        select aj.* into v_job
        from public.automation_jobs aj
        where aj.idempotency_key = v_idempotency_key
        for update;

        if v_job.job_id is null then
            insert into public.automation_jobs (
                candidate_id,
                job_type,
                job_status,
                payload,
                scheduled_at,
                attempt_count,
                completed_at,
                error_message,
                idempotency_key,
                requested_by,
                last_attempt_at,
                created_at,
                updated_at
            ) values (
                v_case.candidate_id,
                'EXIT_DOCUMENT',
                'PENDING',
                pg_catalog.jsonb_build_object(
                    'exit_case_id', v_case.exit_case_id,
                    'exit_document_request_id', v_request.request_id,
                    'document_variant', v_variant
                ),
                v_now,
                0,
                null,
                null,
                v_idempotency_key,
                v_actor_user_id,
                null,
                v_now,
                v_now
            )
            returning * into v_job;
        elsif v_job.job_type is distinct from 'EXIT_DOCUMENT'
           or v_job.candidate_id is distinct from v_case.candidate_id
           or v_job.payload ->> 'exit_case_id' is distinct from v_case.exit_case_id::text
           or v_job.payload ->> 'exit_document_request_id' is distinct from v_request.request_id::text
           or v_job.payload ->> 'document_variant' is distinct from v_variant then
            raise exception using
                errcode = 'P0001',
                message = 'Exit-document automation job is inconsistent with the request.';
        end if;

        if v_request.job_id is not null and v_request.job_id is distinct from v_job.job_id then
            raise exception using
                errcode = 'P0001',
                message = 'Exit-document request is assigned to another automation job.';
        end if;

        update public.exit_document_requests
        set job_id = v_job.job_id
        where request_id = v_request.request_id
          and job_id is null;
    end loop;

    return query
    select ecr.request_id, ecr.document_variant, ecr.status
    from public.exit_document_requests ecr
    where ecr.exit_case_id = v_case.exit_case_id
      and ecr.document_variant = any(p_document_variants)
    order by ecr.document_variant;
end;
$function$;

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

    -- Worker-only RPC. Direct table mutation is already service-role owned;
    -- this explicit check also prevents an accidentally granted caller role.
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
        where cua.candidate_id = v_case.candidate_id
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

create or replace function public.record_exit_document_job_failure(
    p_job_id uuid,
    p_error_message text,
    p_retryable boolean,
    p_provider_outcome text default 'NOT_STARTED'
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
    v_error_message text;
    v_provider_outcome text;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null or p_retryable is null then
        raise exception using errcode = '22023', message = 'Job ID and retryability are required.';
    end if;
    if auth.role() is distinct from 'service_role' then
        raise exception using errcode = '42501', message = 'Service-role worker access is required.';
    end if;
    v_error_message := left(coalesce(nullif(btrim(p_error_message), ''), 'Exit-document worker failure.'), 1000);
    v_provider_outcome := upper(coalesce(nullif(btrim(p_provider_outcome), ''), 'NOT_STARTED'));
    if v_provider_outcome not in ('NOT_STARTED', 'UNKNOWN') then
        raise exception using errcode = '22023', message = 'Provider outcome must be NOT_STARTED or UNKNOWN.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-document-job:' || p_job_id::text, 0)
    );
    select aj.* into v_job from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;
    if v_job.job_id is null or v_job.job_type is distinct from 'EXIT_DOCUMENT' then
        raise exception using errcode = 'P0001', message = 'Exit-document automation job was not found.';
    end if;
    if v_job.job_status is distinct from 'PROCESSING' then
        raise exception using errcode = 'P0001', message = 'Exit-document job is not being processed.';
    end if;
    select ecr.* into v_request from public.exit_document_requests ecr
    where ecr.job_id = v_job.job_id
    for update;
    if v_request.request_id is null then
        raise exception using errcode = 'P0001', message = 'Exit-document request was not found for automation job.';
    end if;

    if v_provider_outcome = 'UNKNOWN' then
        update public.automation_jobs
        set error_message = v_error_message, updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;
        update public.exit_document_requests
        set error_message = v_error_message
        where request_id = v_request.request_id;
    elsif p_retryable then
        update public.automation_jobs
        set job_status = 'RETRY', error_message = v_error_message, updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;
        update public.exit_document_requests
        set status = 'REQUESTED', error_message = v_error_message
        where request_id = v_request.request_id;
    else
        update public.automation_jobs
        set job_status = 'FAILED', error_message = v_error_message, completed_at = null, updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;
        update public.exit_document_requests
        set status = 'FAILED', error_message = v_error_message
        where request_id = v_request.request_id;
    end if;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status,
        'requestStatus', case when v_provider_outcome = 'UNKNOWN' then 'PROCESSING'
                              when p_retryable then 'REQUESTED' else 'FAILED' end,
        'providerOutcome', v_provider_outcome
    );
end;
$function$;

comment on function public.request_exit_documents(uuid, text[], boolean) is
    'Authorizes HR, validates server-derived variants and the current-end-date override, then idempotently links each exit-document request to one durable EXIT_DOCUMENT automation job.';

comment on function public.claim_exit_document_job(uuid) is
    'Service-role worker claim with advisory and row locking. Revalidates the linked exit case/lifecycle/candidate, current Pod Lead and Operations Associate eligibility, and persisted date-mismatch override before entering PROCESSING.';

comment on function public.record_exit_document_job_failure(uuid, text, boolean, text) is
    'Service-role failure recording for exit-document jobs. UNKNOWN preserves PROCESSING for manual provider reconciliation; retryable failures return to RETRY/REQUESTED; terminal failures become FAILED.';

revoke execute on function public.request_exit_documents(uuid, text[], boolean) from public;
revoke execute on function public.request_exit_documents(uuid, text[], boolean) from anon;
grant execute on function public.request_exit_documents(uuid, text[], boolean) to authenticated;
grant execute on function public.request_exit_documents(uuid, text[], boolean) to service_role;

revoke execute on function public.claim_exit_document_job(uuid) from public;
revoke execute on function public.claim_exit_document_job(uuid) from anon;
revoke execute on function public.claim_exit_document_job(uuid) from authenticated;
grant execute on function public.claim_exit_document_job(uuid) to service_role;

revoke execute on function public.record_exit_document_job_failure(uuid, text, boolean, text) from public;
revoke execute on function public.record_exit_document_job_failure(uuid, text, boolean, text) from anon;
revoke execute on function public.record_exit_document_job_failure(uuid, text, boolean, text) from authenticated;
grant execute on function public.record_exit_document_job_failure(uuid, text, boolean, text) to service_role;

commit;
