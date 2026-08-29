begin;

/*
 * The fenced worker deployed with migration 226000 is now canonical.
 * These internal finalizers remain as implementation dependencies of the
 * fenced wrappers, but service_role can no longer invoke them directly.
 */

create or replace function public.complete_exit_document_generation(
    p_job_id uuid,
    p_document_id uuid,
    p_storage_path text,
    p_bucket_id text,
    p_template_key text,
    p_template_version text,
    p_certificate_id text default null,
    p_certificate_verification_url text default null
)
returns table (
    document_id uuid,
    candidate_id uuid,
    candidate_email text,
    document_variant text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
#variable_conflict use_column
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_case public.exit_cases%rowtype;
    v_document public.exit_documents%rowtype;
    v_existing_document public.exit_documents%rowtype;
    v_is_certificate_variant boolean;
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;

    if p_job_id is null or p_document_id is null then
        raise exception using
            errcode = '22023',
            message = 'Job ID and document ID are required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-document-job:' || p_job_id::text, 0)
    );

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_id is null
       or v_job.job_type is distinct from 'EXIT_DOCUMENT'
       or v_job.job_status is distinct from 'PROCESSING' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job is not being processed.';
    end if;

    select ecr.*
    into v_request
    from public.exit_document_requests ecr
    where ecr.job_id = p_job_id
    for update;

    if v_request.request_id is null
       or v_request.status not in ('PROCESSING', 'GENERATED') then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request is not ready for generation finalization.';
    end if;

    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.exit_case_id = v_request.exit_case_id
    for share;

    if v_case.exit_case_id is null
       or v_case.candidate_id is distinct from v_job.candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request is not linked to the job candidate.';
    end if;

    if v_request.reserved_document_id is null
       or v_request.reserved_storage_path is null
       or btrim(v_request.reserved_storage_path) = '' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document reservation is missing.';
    end if;

    if p_document_id is distinct from v_request.reserved_document_id
       or p_storage_path is distinct from v_request.reserved_storage_path then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document finalization does not match its reservation.';
    end if;

    if p_bucket_id is distinct from 'candidate-issued-documents'
       or v_request.reserved_storage_path not like pg_catalog.format(
           'candidate/%s/exit/%s/%s/%%.pdf',
           v_case.candidate_id,
           v_case.exit_case_id,
           v_request.document_variant
       ) then
        raise exception using
            errcode = '22023',
            message = 'Issued-document storage path is invalid.';
    end if;

    if v_request.drive_file_id is null
       or btrim(v_request.drive_file_id) = ''
       or v_request.drive_uploaded_at is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document Drive archive evidence is required before finalization.';
    end if;

    v_is_certificate_variant :=
        v_request.document_variant in (
            'INTERN_CERTIFICATE',
            'VOLUNTEER_CERTIFICATE',
            'POD_LEAD_CERTIFICATE'
        );

    if v_is_certificate_variant then
        if v_request.reserved_certificate_id is null
           or btrim(v_request.reserved_certificate_id) = ''
           or v_request.reserved_certificate_verification_url is null
           or btrim(v_request.reserved_certificate_verification_url) = '' then
            raise exception using
                errcode = 'P0001',
                message = 'Reserved certificate identity is incomplete.';
        end if;

        if p_certificate_id is distinct from v_request.reserved_certificate_id
           or p_certificate_verification_url is distinct from
                v_request.reserved_certificate_verification_url then
            raise exception using
                errcode = 'P0001',
                message = 'Certificate finalization does not match its reserved identity.';
        end if;

        if v_request.reserved_certificate_id
                <> upper(btrim(v_request.reserved_certificate_id))
           or v_request.reserved_certificate_id !~ '^CERT-[A-Z0-9]+$'
           or v_request.reserved_certificate_verification_url not like 'https://%' then
            raise exception using
                errcode = 'P0001',
                message = 'Reserved certificate identity is invalid.';
        end if;
    else
        if v_request.reserved_certificate_id is not null
           or v_request.reserved_certificate_verification_url is not null
           or p_certificate_id is not null
           or p_certificate_verification_url is not null then
            raise exception using
                errcode = '22023',
                message = 'Certificate identity is not allowed for this document variant.';
        end if;
    end if;

    select ed.*
    into v_existing_document
    from public.exit_documents ed
    where ed.exit_case_id = v_case.exit_case_id
      and ed.document_variant = v_request.document_variant
    for update;

    if v_existing_document.document_id is not null
       and (
            v_existing_document.document_id is distinct from
                v_request.reserved_document_id
            or v_existing_document.storage_path is distinct from
                v_request.reserved_storage_path
            or v_existing_document.bucket_id is distinct from
                'candidate-issued-documents'
            or v_existing_document.certificate_id is distinct from
                v_request.reserved_certificate_id
            or v_existing_document.certificate_verification_url is distinct from
                v_request.reserved_certificate_verification_url
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Existing Exit document does not match its durable reservation.';
    end if;

    insert into public.exit_documents (
        document_id,
        exit_case_id,
        document_type,
        storage_path,
        uploaded_by,
        uploaded_at,
        bucket_id,
        generated_at,
        generated_by_job_id,
        document_variant,
        template_key,
        template_version,
        certificate_id,
        certificate_verification_url
    )
    values (
        v_request.reserved_document_id,
        v_case.exit_case_id,
        case
            when v_request.document_variant like '%CERTIFICATE'
                then 'CERTIFICATE'
            else 'LOR'
        end,
        v_request.reserved_storage_path,
        null,
        pg_catalog.now(),
        'candidate-issued-documents',
        pg_catalog.now(),
        p_job_id,
        v_request.document_variant,
        p_template_key,
        p_template_version,
        v_request.reserved_certificate_id,
        v_request.reserved_certificate_verification_url
    )
    on conflict (exit_case_id, document_variant)
        where document_variant is not null
    do update set
        storage_path = excluded.storage_path,
        bucket_id = excluded.bucket_id,
        generated_at = excluded.generated_at,
        generated_by_job_id = excluded.generated_by_job_id,
        template_key = excluded.template_key,
        template_version = excluded.template_version,
        certificate_id = excluded.certificate_id,
        certificate_verification_url = excluded.certificate_verification_url
    returning * into v_document;

    update public.exit_document_requests
    set
        status = 'GENERATED',
        error_message = null
    where request_id = v_request.request_id;

    return query
    select
        v_document.document_id,
        v_case.candidate_id,
        mc.email::text,
        v_request.document_variant
    from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id;
end;
$function$;


create or replace function public.complete_exit_document_email(
    p_job_id uuid,
    p_gmail_message_id text
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_document public.exit_documents%rowtype;
    v_message_id text;
    v_now timestamptz := pg_catalog.now();
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;

    v_message_id := nullif(btrim(p_gmail_message_id), '');

    if p_job_id is null or v_message_id is null then
        raise exception using
            errcode = '22023',
            message = 'Job ID and Gmail message ID are required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-document-job:' || p_job_id::text, 0)
    );

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_id is null
       or v_job.job_type is distinct from 'EXIT_DOCUMENT' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document automation job was not found.';
    end if;

    select ecr.*
    into v_request
    from public.exit_document_requests ecr
    where ecr.job_id = p_job_id
    for update;

    if v_request.request_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request was not found for automation job.';
    end if;

    if v_job.job_status = 'SUCCESS'
       and v_request.status = 'EMAILED' then
        if v_job.provider_message_id is distinct from v_message_id
           or v_job.provider_accepted_at is null then
            raise exception using
                errcode = 'P0001',
                message = 'Completed Exit-document email evidence is inconsistent.';
        end if;

        return;
    end if;

    if v_job.job_status is distinct from 'PROCESSING'
       or v_request.status is distinct from 'GENERATED' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit document is not ready for email completion.';
    end if;

    if v_request.email_attempted_at is null
       or v_job.provider_message_id is null
       or v_job.provider_accepted_at is null
       or v_job.provider_message_id is distinct from v_message_id then
        raise exception using
            errcode = 'P0001',
            message = 'Durable Gmail provider acceptance is required before email completion.';
    end if;

    if v_request.reserved_document_id is null
       or v_request.reserved_storage_path is null
       or v_request.drive_file_id is null
       or v_request.drive_uploaded_at is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document artifact evidence is incomplete.';
    end if;

    select ed.*
    into v_document
    from public.exit_documents ed
    where ed.exit_case_id = v_request.exit_case_id
      and ed.document_variant = v_request.document_variant
    for update;

    if v_document.document_id is null
       or v_document.document_id is distinct from v_request.reserved_document_id
       or v_document.storage_path is distinct from v_request.reserved_storage_path
       or v_document.bucket_id is distinct from 'candidate-issued-documents'
       or v_document.generated_by_job_id is distinct from p_job_id
       or v_document.certificate_id is distinct from
            v_request.reserved_certificate_id
       or v_document.certificate_verification_url is distinct from
            v_request.reserved_certificate_verification_url then
        raise exception using
            errcode = 'P0001',
            message = 'Generated Exit document does not match its durable reservation.';
    end if;

    if v_document.gmail_message_id is not null
       and v_document.gmail_message_id is distinct from v_message_id then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document Gmail message ID cannot be replaced.';
    end if;

    update public.exit_documents
    set
        gmail_message_id = coalesce(gmail_message_id, v_message_id),
        emailed_at = coalesce(emailed_at, v_now)
    where document_id = v_document.document_id;

    update public.exit_document_requests
    set
        status = 'EMAILED',
        error_message = null
    where request_id = v_request.request_id;

    update public.automation_jobs
    set
        job_status = 'SUCCESS',
        completed_at = coalesce(completed_at, v_now),
        error_message = null,
        exit_document_processing_lease_expires_at = null,
        updated_at = v_now
    where job_id = p_job_id;
end;
$function$;


/*
 * Only the fenced post-claim API remains callable by service_role. The
 * SECURITY DEFINER owner of each wrapper can still invoke its corresponding
 * legacy implementation inside the already-fenced transaction.
 */
revoke all privileges
    on function public.reserve_exit_document_generation(
        uuid,
        text,
        text
    )
    from public, anon, authenticated, service_role;

revoke all privileges
    on function public.record_exit_document_drive_archive(uuid, text)
    from public, anon, authenticated, service_role;

revoke all privileges
    on function public.complete_exit_document_generation(
        uuid,
        uuid,
        text,
        text,
        text,
        text,
        text,
        text
    )
    from public, anon, authenticated, service_role;

revoke all privileges
    on function public.mark_exit_document_email_attempt(uuid)
    from public, anon, authenticated, service_role;

revoke all privileges
    on function public.record_exit_document_provider_acceptance(uuid, text)
    from public, anon, authenticated, service_role;

revoke all privileges
    on function public.complete_exit_document_email(uuid, text)
    from public, anon, authenticated, service_role;

revoke all privileges
    on function public.record_exit_document_job_failure(
        uuid,
        text,
        boolean,
        text
    )
    from public, anon, authenticated, service_role;

grant execute
    on function public.reserve_exit_document_generation_fenced(
        uuid,
        integer,
        text,
        text
    )
    to service_role;

grant execute
    on function public.record_exit_document_drive_archive_fenced(
        uuid,
        integer,
        text
    )
    to service_role;

grant execute
    on function public.complete_exit_document_generation_fenced(
        uuid,
        integer,
        uuid,
        text,
        text,
        text,
        text,
        text,
        text
    )
    to service_role;

grant execute
    on function public.mark_exit_document_email_attempt_fenced(
        uuid,
        integer
    )
    to service_role;

grant execute
    on function public.record_exit_document_provider_acceptance_fenced(
        uuid,
        integer,
        text
    )
    to service_role;

grant execute
    on function public.complete_exit_document_email_fenced(
        uuid,
        integer,
        text
    )
    to service_role;

grant execute
    on function public.record_exit_document_job_failure_fenced(
        uuid,
        integer,
        text,
        boolean,
        text
    )
    to service_role;

comment on function public.complete_exit_document_generation(
    uuid,
    uuid,
    text,
    text,
    text,
    text,
    text,
    text
) is
    'Internal implementation for the claim-attempt-fenced Exit-document generation finalizer. Direct service-role execution is revoked.';

comment on function public.complete_exit_document_email(uuid, text) is
    'Internal implementation for the claim-attempt-fenced Exit-document email finalizer. Requires durable provider acceptance; direct service-role execution is revoked.';

commit;
