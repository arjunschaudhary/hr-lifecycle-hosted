begin;

-- Core retry-safety fields for EXIT_DOCUMENT automation.
-- Dispatcher/cron will be added in later migrations only after the worker
-- has been proven safe.

alter table public.automation_jobs
    add column if not exists
        exit_document_processing_lease_expires_at timestamptz;

comment on column
    public.automation_jobs.exit_document_processing_lease_expires_at
is
    'Explicit processing lease for EXIT_DOCUMENT jobs. Only stale pre-email work may be reclaimed automatically.';


alter table public.exit_document_requests
    add column if not exists reserved_document_id uuid,
    add column if not exists reserved_storage_path text,
    add column if not exists reserved_certificate_id text,
    add column if not exists reserved_certificate_verification_url text,
    add column if not exists drive_file_id text,
    add column if not exists drive_uploaded_at timestamptz,
    add column if not exists email_attempted_at timestamptz;


comment on column public.exit_document_requests.reserved_document_id is
    'Stable document UUID reserved before external generation so retries reuse the same artifact identity.';

comment on column public.exit_document_requests.reserved_storage_path is
    'Stable private Storage object path paired with reserved_document_id.';

comment on column public.exit_document_requests.reserved_certificate_id is
    'Stable certificate identity reserved before rendering. NULL for LOR variants.';

comment on column public.exit_document_requests.reserved_certificate_verification_url is
    'Verification URL paired with reserved_certificate_id. NULL for LOR variants.';

comment on column public.exit_document_requests.drive_file_id is
    'Durable Google Drive archive file ID for the generated PDF.';

comment on column public.exit_document_requests.drive_uploaded_at is
    'Timestamp when the Drive archive ID was durably recorded.';

comment on column public.exit_document_requests.email_attempted_at is
    'Timestamp when the current Gmail send attempt crossed the external-send boundary.';


do $block$
begin

    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid =
              'public.exit_document_requests'::pg_catalog.regclass
          and conname =
              'exit_document_requests_reservation_pair_check'
    ) then

        alter table public.exit_document_requests
            add constraint
                exit_document_requests_reservation_pair_check
            check (
                (
                    reserved_document_id is null
                    and reserved_storage_path is null
                )
                or
                (
                    reserved_document_id is not null
                    and reserved_storage_path is not null
                )
            );

    end if;


    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid =
              'public.exit_document_requests'::pg_catalog.regclass
          and conname =
              'exit_document_requests_reserved_identity_scope_check'
    ) then

        alter table public.exit_document_requests
            add constraint
                exit_document_requests_reserved_identity_scope_check
            check (

                (
                    document_variant in (
                        'INTERN_CERTIFICATE',
                        'VOLUNTEER_CERTIFICATE',
                        'POD_LEAD_CERTIFICATE'
                    )
                    and
                    (
                        (
                            reserved_certificate_id is null
                            and
                            reserved_certificate_verification_url is null
                        )
                        or
                        (
                            reserved_certificate_id is not null
                            and
                            reserved_certificate_verification_url is not null

                            and reserved_certificate_id =
                                upper(
                                    btrim(
                                        reserved_certificate_id
                                    )
                                )

                            and reserved_certificate_id
                                ~ '^CERT-[A-Z0-9]+$'

                            and
                            reserved_certificate_verification_url
                                like 'https://%'
                        )
                    )
                )

                or

                (
                    document_variant not in (
                        'INTERN_CERTIFICATE',
                        'VOLUNTEER_CERTIFICATE',
                        'POD_LEAD_CERTIFICATE'
                    )

                    and reserved_certificate_id is null

                    and
                    reserved_certificate_verification_url
                        is null
                )

            );

    end if;


    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid =
              'public.exit_document_requests'::pg_catalog.regclass
          and conname =
              'exit_document_requests_drive_pair_check'
    ) then

        alter table public.exit_document_requests
            add constraint
                exit_document_requests_drive_pair_check
            check (
                (
                    drive_file_id is null
                    and drive_uploaded_at is null
                )
                or
                (
                    drive_file_id is not null
                    and btrim(drive_file_id) <> ''
                    and drive_uploaded_at is not null
                )
            );

    end if;

end;
$block$;


create unique index if not exists
    uq_exit_document_requests_reserved_document_id
on public.exit_document_requests (
    reserved_document_id
)
where reserved_document_id is not null;


create unique index if not exists
    uq_exit_document_requests_reserved_storage_path
on public.exit_document_requests (
    reserved_storage_path
)
where reserved_storage_path is not null;


create unique index if not exists
    uq_exit_document_requests_reserved_certificate_id
on public.exit_document_requests (
    (upper(reserved_certificate_id))
)
where reserved_certificate_id is not null;


create index if not exists
    idx_automation_jobs_exit_document_recovery
on public.automation_jobs (
    job_status,
    scheduled_at,
    exit_document_processing_lease_expires_at,
    created_at
)
where job_type = 'EXIT_DOCUMENT'
  and job_status in (
      'PENDING',
      'RETRY',
      'PROCESSING'
  );

create or replace function public.reserve_exit_document_generation(
    p_job_id uuid,
    p_certificate_id text default null,
    p_certificate_verification_url text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
#variable_conflict use_column
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_case public.exit_cases%rowtype;
    v_existing_document public.exit_documents%rowtype;

    v_document_id uuid;
    v_storage_path text;

    v_certificate_id text;
    v_verification_url text;

    v_is_certificate boolean;
begin

    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;


    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;


    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'exit-document-job:' || p_job_id::text,
            0
        )
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


    if v_request.request_id is null then

        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request was not found for automation job.';

    end if;


    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.exit_case_id = v_request.exit_case_id;


    if v_case.exit_case_id is null
       or v_case.candidate_id is distinct from v_job.candidate_id then

        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request is not linked to a valid exit case.';

    end if;


    v_is_certificate :=
        v_request.document_variant in (
            'INTERN_CERTIFICATE',
            'VOLUNTEER_CERTIFICATE',
            'POD_LEAD_CERTIFICATE'
        );


    /*
     * If generation was already finalized on an earlier worker attempt,
     * adopt that existing document as the reservation instead of creating
     * another UUID/path.
     *
     * Example:
     *
     * generation succeeded
     * -> Gmail definitely NOT_SENT
     * -> job RETRY
     * -> retry must reuse the same generated PDF.
     */
    select ed.*
    into v_existing_document
    from public.exit_documents ed
    where ed.exit_case_id = v_request.exit_case_id
      and ed.document_variant = v_request.document_variant
    for update;


    if v_existing_document.document_id is not null
       and v_request.reserved_document_id is null then

        if v_existing_document.storage_path is null
           or btrim(v_existing_document.storage_path) = '' then

            raise exception using
                errcode = 'P0001',
                message = 'Existing Exit document has no reusable Storage path.';

        end if;


        if v_existing_document.bucket_id
            is distinct from 'candidate-issued-documents' then

            raise exception using
                errcode = 'P0001',
                message = 'Existing Exit document is not stored in the issued-document bucket.';

        end if;


        if v_existing_document.storage_path
            not like pg_catalog.format(
                'candidate/%s/exit/%s/%s/%%.pdf',
                v_case.candidate_id,
                v_case.exit_case_id,
                v_request.document_variant
            ) then

            raise exception using
                errcode = 'P0001',
                message = 'Existing Exit-document Storage path does not match the request.';

        end if;


        if v_is_certificate then

            if v_existing_document.certificate_id is null
               or btrim(v_existing_document.certificate_id) = ''
               or v_existing_document.certificate_verification_url is null
               or btrim(
                    v_existing_document.certificate_verification_url
                  ) = '' then

                raise exception using
                    errcode = 'P0001',
                    message = 'Existing certificate requires controlled identity reconciliation before retry.';

            end if;


            if v_existing_document.certificate_id
                    <> upper(
                        btrim(
                            v_existing_document.certificate_id
                        )
                    )
               or v_existing_document.certificate_id
                    !~ '^CERT-[A-Z0-9]+$' then

                raise exception using
                    errcode = 'P0001',
                    message = 'Existing certificate identity is not canonical.';

            end if;


            if v_existing_document.certificate_verification_url
                    not like 'https://%' then

                raise exception using
                    errcode = 'P0001',
                    message = 'Existing certificate verification URL is invalid.';

            end if;


            /*
             * Any identity supplied by the worker must match the
             * already-issued certificate exactly.
             */
            if p_certificate_id is not null
               and upper(
                    btrim(
                        p_certificate_id
                    )
                   )
                   is distinct from
                       v_existing_document.certificate_id then

                raise exception using
                    errcode = 'P0001',
                    message = 'Existing certificate identity cannot be replaced.';

            end if;


            if p_certificate_verification_url is not null
               and btrim(
                    p_certificate_verification_url
                   )
                   is distinct from
                       v_existing_document.certificate_verification_url then

                raise exception using
                    errcode = 'P0001',
                    message = 'Existing certificate verification URL cannot be replaced.';

            end if;


            v_certificate_id :=
                v_existing_document.certificate_id;


            v_verification_url :=
                v_existing_document.certificate_verification_url;


        else

            if v_existing_document.certificate_id is not null
               or v_existing_document.certificate_verification_url
                    is not null then

                raise exception using
                    errcode = 'P0001',
                    message = 'Existing LOR contains an unexpected certificate identity.';

            end if;


            if p_certificate_id is not null
               or p_certificate_verification_url is not null then

                raise exception using
                    errcode = '22023',
                    message = 'Certificate identity is not allowed for this document variant.';

            end if;


            v_certificate_id := null;
            v_verification_url := null;

        end if;


        update public.exit_document_requests
        set
            reserved_document_id =
                v_existing_document.document_id,

            reserved_storage_path =
                v_existing_document.storage_path,

            reserved_certificate_id =
                v_certificate_id,

            reserved_certificate_verification_url =
                v_verification_url

        where request_id = v_request.request_id

        returning *
        into v_request;


        return pg_catalog.jsonb_build_object(
            'requestId',
                v_request.request_id,

            'documentId',
                v_request.reserved_document_id,

            'storagePath',
                v_request.reserved_storage_path,

            'certificateId',
                v_request.reserved_certificate_id,

            'certificateVerificationUrl',
                v_request.reserved_certificate_verification_url,

            'driveFileId',
                v_request.drive_file_id,

            'adoptedExistingDocument',
                true
        );

    end if;


    /*
     * Existing reservation is authoritative.
     *
     * A retry must NEVER create:
     * - another document UUID
     * - another Storage path
     * - another certificate ID
     * - another verification URL
     */
    if v_request.reserved_document_id is not null then

        if v_request.reserved_storage_path is null then

            raise exception using
                errcode = 'P0001',
                message = 'Exit-document reservation is incomplete.';

        end if;


        if v_is_certificate then

            if v_request.reserved_certificate_id is null
               or
               v_request.reserved_certificate_verification_url is null then

                raise exception using
                    errcode = 'P0001',
                    message = 'Certificate reservation is incomplete.';

            end if;


            if p_certificate_id is not null
               and upper(btrim(p_certificate_id))
                   is distinct from
                       v_request.reserved_certificate_id then

                raise exception using
                    errcode = 'P0001',
                    message = 'Certificate reservation cannot be replaced.';

            end if;


            if p_certificate_verification_url is not null
               and btrim(p_certificate_verification_url)
                   is distinct from
                       v_request.reserved_certificate_verification_url then

                raise exception using
                    errcode = 'P0001',
                    message = 'Certificate verification URL cannot be replaced.';

            end if;

        else

            if p_certificate_id is not null
               or p_certificate_verification_url is not null then

                raise exception using
                    errcode = '22023',
                    message = 'Certificate identity is not allowed for this document variant.';

            end if;

        end if;


        return pg_catalog.jsonb_build_object(
            'requestId',
                v_request.request_id,

            'documentId',
                v_request.reserved_document_id,

            'storagePath',
                v_request.reserved_storage_path,

            'certificateId',
                v_request.reserved_certificate_id,

            'certificateVerificationUrl',
                v_request.reserved_certificate_verification_url,

            'driveFileId',
                v_request.drive_file_id
        );

    end if;


    /*
     * Reserve exactly one durable artifact identity.
     */
    v_document_id := gen_random_uuid();


    v_storage_path := pg_catalog.format(
        'candidate/%s/exit/%s/%s/%s.pdf',
        v_case.candidate_id,
        v_case.exit_case_id,
        v_request.document_variant,
        v_document_id
    );


    if v_is_certificate then

        v_certificate_id :=
            upper(btrim(p_certificate_id));


        v_verification_url :=
            btrim(p_certificate_verification_url);


        if v_certificate_id is null
           or v_certificate_id = ''
           or v_certificate_id !~ '^CERT-[A-Z0-9]+$' then

            raise exception using
                errcode = '22023',
                message = 'A canonical certificate identity is required for reservation.';

        end if;


        if v_verification_url is null
           or v_verification_url = ''
           or v_verification_url not like 'https://%' then

            raise exception using
                errcode = '22023',
                message = 'An HTTPS certificate verification URL is required.';

        end if;


        /*
         * Lock the certificate namespace before checking both:
         *
         * 1. already-issued certificate IDs
         * 2. certificate IDs reserved by in-flight jobs
         */
        perform pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                'exit-document-certificate:' || v_certificate_id,
                0
            )
        );


        if exists (
            select 1
            from public.exit_documents ed
            where upper(ed.certificate_id) = v_certificate_id
        )
        or exists (
            select 1
            from public.exit_document_requests ecr
            where upper(ecr.reserved_certificate_id) = v_certificate_id
              and ecr.request_id <> v_request.request_id
        ) then

            raise exception using
                errcode = '23505',
                message = 'Certificate identity is already reserved or issued.';

        end if;


    else

        if p_certificate_id is not null
           or p_certificate_verification_url is not null then

            raise exception using
                errcode = '22023',
                message = 'Certificate identity is not allowed for this document variant.';

        end if;


        v_certificate_id := null;
        v_verification_url := null;

    end if;


    update public.exit_document_requests
    set
        reserved_document_id =
            v_document_id,

        reserved_storage_path =
            v_storage_path,

        reserved_certificate_id =
            v_certificate_id,

        reserved_certificate_verification_url =
            v_verification_url

    where request_id = v_request.request_id

    returning *
    into v_request;


    return pg_catalog.jsonb_build_object(
        'requestId',
            v_request.request_id,

        'documentId',
            v_request.reserved_document_id,

        'storagePath',
            v_request.reserved_storage_path,

        'certificateId',
            v_request.reserved_certificate_id,

        'certificateVerificationUrl',
            v_request.reserved_certificate_verification_url,

        'driveFileId',
            v_request.drive_file_id
    );

end;
$function$;


revoke all privileges
    on function public.reserve_exit_document_generation(
        uuid,
        text,
        text
    )
    from public;


revoke all privileges
    on function public.reserve_exit_document_generation(
        uuid,
        text,
        text
    )
    from anon;


revoke all privileges
    on function public.reserve_exit_document_generation(
        uuid,
        text,
        text
    )
    from authenticated;


grant execute
    on function public.reserve_exit_document_generation(
        uuid,
        text,
        text
    )
    to service_role;


comment on function public.reserve_exit_document_generation(
    uuid,
    text,
    text
) is
    'Service-role reservation of one stable Exit-document artifact identity/path and, for certificates, one immutable public verification identity before external generation.';

create or replace function public.claim_exit_document_job(
    p_job_id uuid
)
returns jsonb
language plpgsql
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

    v_allowed_variants text[] :=
        array[
            'INTERN_CERTIFICATE',
            'VOLUNTEER_CERTIFICATE',
            'INTERN_LOR'
        ]::text[];

    v_now timestamptz := pg_catalog.now();

    v_is_stale_processing boolean := false;
begin

    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;


    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;


    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'exit-document-job:' || p_job_id::text,
            0
        )
    );


    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;


    if v_job.job_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document automation job was not found.';
    end if;


    if v_job.job_type is distinct from 'EXIT_DOCUMENT' then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not an exit-document job.';
    end if;


    if v_job.job_status not in (
        'PENDING',
        'RETRY',
        'PROCESSING'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job is not claimable.';
    end if;


    /*
     * Five total worker claims are allowed.
     *
     * A stale PROCESSING reclaim is a new worker attempt and therefore
     * consumes another attempt from the same budget.
     */
    if v_job.attempt_count >= 5 then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job exhausted its automatic retry budget.';
    end if;


    /*
     * Revalidate immutable job payload identifiers.
     */
    begin

        v_payload_case_id :=
            (v_job.payload ->> 'exit_case_id')::uuid;

        v_payload_request_id :=
            (v_job.payload ->> 'exit_document_request_id')::uuid;

    exception
        when invalid_text_representation then

            raise exception using
                errcode = 'P0001',
                message = 'Exit-document job payload identifiers are invalid.';

    end;


    v_variant :=
        v_job.payload ->> 'document_variant';


    if v_payload_case_id is null
       or v_payload_request_id is null
       or v_variant not in (
            'INTERN_CERTIFICATE',
            'POD_LEAD_CERTIFICATE',
            'VOLUNTEER_CERTIFICATE',
            'INTERN_LOR',
            'POD_LEAD_LOR',
            'OPERATIONS_ASSOCIATE_LOR'
       ) then

        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job payload is incomplete or invalid.';

    end if;


    select ecr.*
    into v_request
    from public.exit_document_requests ecr
    where ecr.request_id = v_payload_request_id
    for update;


    if v_request.request_id is null
       or v_request.exit_case_id
            is distinct from v_payload_case_id
       or v_request.document_variant
            is distinct from v_variant
       or v_request.job_id
            is distinct from v_job.job_id
       or v_request.requested_by
            is distinct from v_job.requested_by then

        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request does not match its automation job.';

    end if;


    /*
     * A PROCESSING job is reclaimable only when:
     *
     * 1. its explicit lease has expired, or a legacy job has been
     *    PROCESSING for at least 15 minutes;
     * 2. Gmail has not crossed its external-send boundary;
     * 3. no Gmail provider acceptance evidence exists.
     */
    v_is_stale_processing :=
        v_job.job_status = 'PROCESSING'

        and coalesce(
            v_job.exit_document_processing_lease_expires_at,
            coalesce(
                v_job.last_attempt_at,
                v_job.created_at
            ) + interval '15 minutes'
        ) <= v_now

        and v_request.email_attempted_at is null

        and v_job.provider_message_id is null

        and v_job.provider_accepted_at is null;


    if v_job.job_status = 'PROCESSING'
       and not v_is_stale_processing then

        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job is already being processed or requires reconciliation.';

    end if;


    if v_job.job_status in ('PENDING', 'RETRY') then

        /*
         * Retry backoff cannot be bypassed by a direct worker invocation.
         */
        if v_job.scheduled_at > v_now then

            raise exception using
                errcode = 'P0001',
                message = 'Exit-document job is not scheduled yet.';

        end if;


        if v_job.provider_message_id is not null
           or v_job.provider_accepted_at is not null then

            raise exception using
                errcode = 'P0001',
                message = 'Exit-document job has an unexpected provider state.';

        end if;


        if v_request.email_attempted_at is not null then

            raise exception using
                errcode = 'P0001',
                message = 'Exit-document request has an unresolved email attempt.';

        end if;


        if v_request.status not in (
            'REQUESTED',
            'FAILED'
        ) then

            raise exception using
                errcode = 'P0001',
                message = 'Exit-document request is not claimable.';

        end if;


    else

        /*
         * This is the stale PROCESSING recovery branch.
         */
        if v_request.status is distinct from 'PROCESSING' then

            raise exception using
                errcode = 'P0001',
                message = 'Stale exit-document job has an inconsistent request state.';

        end if;

    end if;


    /*
     * Re-run the same business eligibility checks used by the current
     * production worker claim.
     */
    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.exit_case_id = v_payload_case_id
    for share;


    if v_case.exit_case_id is null then

        raise exception using
            errcode = 'P0001',
            message = 'Exit case was not found during document job revalidation.';

    end if;


    select hl.*
    into v_lifecycle
    from public.hr_lifecycle hl
    where hl.lifecycle_id = v_case.lifecycle_id
    for share;


    if v_lifecycle.lifecycle_id is null
       or v_lifecycle.candidate_id
            is distinct from v_case.candidate_id then

        raise exception using
            errcode = 'P0001',
            message = 'Exit case lifecycle was not found during document job revalidation.';

    end if;


    select mc.*
    into v_candidate
    from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id
    for share;


    if v_candidate.candidate_id is null
       or v_job.candidate_id
            is distinct from v_case.candidate_id then

        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job candidate is invalid.';

    end if;


    /*
     * IMPORTANT:
     * Preserve historical Pod Lead authorization.
     * Do NOT replace this with current membership.
     */
    v_is_pod_lead :=
        public.exit_case_candidate_was_historical_pod_lead(
            v_case.exit_case_id
        );


    v_is_operations_associate :=
        v_candidate.applied_role =
            'Operations Associate Intern';


    v_date_matches :=
        v_case.exit_date
            is not distinct from
        v_lifecycle.current_end_date;


    if v_is_pod_lead then

        v_allowed_variants :=
            v_allowed_variants
            ||
            array[
                'POD_LEAD_CERTIFICATE',
                'POD_LEAD_LOR'
            ]::text[];

    end if;


    if v_is_operations_associate then

        v_allowed_variants :=
            v_allowed_variants
            ||
            array[
                'OPERATIONS_ASSOCIATE_LOR'
            ]::text[];

    end if;


    if v_variant <> all(v_allowed_variants) then

        raise exception using
            errcode = 'P0001',
            message = 'Requested document variant is no longer allowed.';

    end if;


    if not v_date_matches
       and not v_request.date_mismatch_override_approved then

        raise exception using
            errcode = 'P0001',
            message = 'Exit date mismatch requires an explicit HR override before document processing.';

    end if;


    /*
     * Claim/reclaim the job.
     *
     * The lease is explicit so updated_at is never used as a proxy for
     * worker ownership.
     */
    update public.automation_jobs
    set
        job_status = 'PROCESSING',

        attempt_count =
            attempt_count + 1,

        last_attempt_at =
            v_now,

        completed_at =
            null,

        error_message =
            null,

        exit_document_processing_lease_expires_at =
            v_now + interval '15 minutes',

        updated_at =
            v_now

    where job_id = v_job.job_id

    returning *
    into v_job;


    update public.exit_document_requests
    set
        status = 'PROCESSING',

        error_message = null,

        email_attempted_at = null

    where request_id = v_request.request_id;


    return pg_catalog.jsonb_build_object(
        'jobId',
            v_job.job_id,

        'jobStatus',
            v_job.job_status,

        'attemptCount',
            v_job.attempt_count,

        'leaseExpiresAt',
            v_job.exit_document_processing_lease_expires_at,

        'exitCaseId',
            v_payload_case_id,

        'exitDocumentRequestId',
            v_payload_request_id,

        'documentVariant',
            v_variant,

        'staleProcessingReclaim',
            v_is_stale_processing
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
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_error_message text;
    v_provider_outcome text;
    v_now timestamptz := pg_catalog.now();
    v_retry_at timestamptz;
    v_terminal boolean := false;
begin
    if p_job_id is null or p_retryable is null then
        raise exception using
            errcode = '22023',
            message = 'Job ID and retryability are required.';
    end if;

    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;

    v_error_message := left(
        coalesce(nullif(btrim(p_error_message), ''), 'Exit-document worker failure.'),
        1000
    );

    v_provider_outcome := upper(
        coalesce(nullif(btrim(p_provider_outcome), ''), 'NOT_STARTED')
    );

    if v_provider_outcome not in ('NOT_STARTED', 'UNKNOWN', 'ACCEPTED') then
        raise exception using
            errcode = '22023',
            message = 'Provider outcome must be NOT_STARTED, UNKNOWN, or ACCEPTED.';
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

    if v_job.job_status is distinct from 'PROCESSING' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document job is not being processed.';
    end if;

    select ecr.*
    into v_request
    from public.exit_document_requests ecr
    where ecr.job_id = v_job.job_id
    for update;

    if v_request.request_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document request was not found for automation job.';
    end if;

    if v_provider_outcome = 'ACCEPTED'
       and (
            v_job.provider_message_id is null
            or v_job.provider_accepted_at is null
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'ACCEPTED provider outcome requires durable provider evidence.';
    end if;

    if v_provider_outcome in ('UNKNOWN', 'ACCEPTED') then
        update public.automation_jobs
        set
            error_message = v_error_message,
            exit_document_processing_lease_expires_at = null,
            updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;

        update public.exit_document_requests
        set error_message = v_error_message
        where request_id = v_request.request_id
        returning * into v_request;

        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'requestStatus', v_request.status,
            'providerOutcome', v_provider_outcome,
            'providerMessageId', v_job.provider_message_id,
            'providerAcceptedAt', v_job.provider_accepted_at,
            'attemptCount', v_job.attempt_count
        );
    end if;

    if v_job.provider_message_id is not null
       or v_job.provider_accepted_at is not null then
        raise exception using
            errcode = 'P0001',
            message = 'NOT_STARTED failure cannot overwrite durable provider evidence.';
    end if;

    v_terminal := (not p_retryable) or v_job.attempt_count >= 5;

    if v_terminal then
        update public.automation_jobs
        set
            job_status = 'FAILED',
            error_message = v_error_message,
            completed_at = null,
            exit_document_processing_lease_expires_at = null,
            updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;

        update public.exit_document_requests
        set
            status = 'FAILED',
            error_message = v_error_message,
            email_attempted_at = null
        where request_id = v_request.request_id
        returning * into v_request;
    else
        v_retry_at :=
            v_now
            + case v_job.attempt_count
                when 1 then interval '5 minutes'
                when 2 then interval '10 minutes'
                when 3 then interval '20 minutes'
                else interval '40 minutes'
              end;

        update public.automation_jobs
        set
            job_status = 'RETRY',
            scheduled_at = v_retry_at,
            error_message = v_error_message,
            completed_at = null,
            exit_document_processing_lease_expires_at = null,
            updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;

        update public.exit_document_requests
        set
            status = 'REQUESTED',
            error_message = v_error_message,
            email_attempted_at = null
        where request_id = v_request.request_id
        returning * into v_request;
    end if;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status,
        'requestStatus', v_request.status,
        'providerOutcome', v_provider_outcome,
        'scheduledAt', v_job.scheduled_at,
        'attemptCount', v_job.attempt_count
    );
end;
$function$;


revoke all privileges
    on function public.claim_exit_document_job(
        uuid
    )
    from public;

revoke all privileges
    on function public.claim_exit_document_job(
        uuid
    )
    from anon;

revoke all privileges
    on function public.claim_exit_document_job(
        uuid
    )
    from authenticated;

grant execute
    on function public.claim_exit_document_job(
        uuid
    )
    to service_role;



revoke all privileges
    on function public.record_exit_document_job_failure(
        uuid,
        text,
        boolean,
        text
    )
    from public;

revoke all privileges
    on function public.record_exit_document_job_failure(
        uuid,
        text,
        boolean,
        text
    )
    from anon;

revoke all privileges
    on function public.record_exit_document_job_failure(
        uuid,
        text,
        boolean,
        text
    )
    from authenticated;

grant execute
    on function public.record_exit_document_job_failure(
        uuid,
        text,
        boolean,
        text
    )
    to service_role;



comment on function public.claim_exit_document_job(
    uuid
) is
    'Claims or safely reclaims an Exit-document job with a five-attempt budget and explicit 15-minute processing lease. Stale PROCESSING work is reclaimable only before the Gmail send boundary.';


comment on function public.record_exit_document_job_failure(
    uuid,
    text,
    boolean,
    text
) is
    'Records bounded Exit-document failure recovery with 5/10/20/40 minute retry backoff. UNKNOWN provider outcomes remain PROCESSING for explicit reconciliation and cannot be automatically resent.';




/*
 * STEP 1D
 * Durable external-side-effect evidence:
 * - Google Drive archive ID
 * - Gmail send boundary
 * - Gmail provider acceptance
 *
 * IMPORTANT DEPLOYMENT NOTE:
 * This migration intentionally does NOT replace
 * complete_exit_document_generation() or complete_exit_document_email().
 * The currently deployed worker must remain compatible while the new worker
 * is deployed. Strict finalizer enforcement is added only after the worker
 * has switched to reservations/provider evidence.
 */

create unique index if not exists
    uq_exit_document_requests_drive_file_id
on public.exit_document_requests (drive_file_id)
where drive_file_id is not null;


create or replace function public.record_exit_document_drive_archive(
    p_job_id uuid,
    p_drive_file_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_drive_file_id text;
    v_now timestamptz := pg_catalog.now();
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;

    v_drive_file_id := nullif(btrim(p_drive_file_id), '');

    if p_job_id is null or v_drive_file_id is null then
        raise exception using
            errcode = '22023',
            message = 'Job ID and Drive file ID are required.';
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
       or v_request.reserved_document_id is null
       or v_request.reserved_storage_path is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document artifact reservation is missing.';
    end if;

    if v_request.drive_file_id is not null
       and v_request.drive_file_id is distinct from v_drive_file_id then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document Drive archive cannot be replaced.';
    end if;

    update public.exit_document_requests
    set
        drive_file_id = coalesce(drive_file_id, v_drive_file_id),
        drive_uploaded_at = coalesce(drive_uploaded_at, v_now)
    where request_id = v_request.request_id
    returning * into v_request;

    return pg_catalog.jsonb_build_object(
        'requestId', v_request.request_id,
        'driveFileId', v_request.drive_file_id,
        'driveUploadedAt', v_request.drive_uploaded_at
    );
end;
$function$;


create or replace function public.mark_exit_document_email_attempt(
    p_job_id uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_document public.exit_documents%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role worker access is required.';
    end if;

    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Job ID is required.';
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

    if v_job.provider_message_id is not null
       or v_job.provider_accepted_at is not null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document provider acceptance is already recorded.';
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
            message = 'Exit document is not ready for an email attempt.';
    end if;

    select ed.*
    into v_document
    from public.exit_documents ed
    where ed.exit_case_id = v_request.exit_case_id
      and ed.document_variant = v_request.document_variant
    for share;

    if v_document.document_id is null
       or v_document.storage_path is null
       or btrim(v_document.storage_path) = '' then
        raise exception using
            errcode = 'P0001',
            message = 'Generated Exit document was not found before email attempt.';
    end if;

    update public.exit_document_requests
    set email_attempted_at = coalesce(email_attempted_at, v_now)
    where request_id = v_request.request_id
    returning * into v_request;

    return v_request.email_attempted_at;
end;
$function$;


create or replace function public.record_exit_document_provider_acceptance(
    p_job_id uuid,
    p_gmail_message_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
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
       or v_request.email_attempted_at is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document email attempt was not recorded.';
    end if;

    if v_job.provider_message_id is not null
       and v_job.provider_message_id is distinct from v_message_id then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document Gmail provider message ID cannot be replaced.';
    end if;

    if v_job.provider_accepted_at is not null
       and v_job.provider_message_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document provider acceptance evidence is inconsistent.';
    end if;

    update public.automation_jobs
    set
        provider_message_id = coalesce(provider_message_id, v_message_id),
        provider_accepted_at = coalesce(provider_accepted_at, v_now),
        exit_document_processing_lease_expires_at = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'providerMessageId', v_job.provider_message_id,
        'providerAcceptedAt', v_job.provider_accepted_at
    );
end;
$function$;



revoke all privileges
    on function public.record_exit_document_drive_archive(uuid, text)
    from public, anon, authenticated;

grant execute
    on function public.record_exit_document_drive_archive(uuid, text)
    to service_role;


revoke all privileges
    on function public.mark_exit_document_email_attempt(uuid)
    from public, anon, authenticated;

grant execute
    on function public.mark_exit_document_email_attempt(uuid)
    to service_role;


revoke all privileges
    on function public.record_exit_document_provider_acceptance(uuid, text)
    from public, anon, authenticated;

grant execute
    on function public.record_exit_document_provider_acceptance(uuid, text)
    to service_role;



comment on function public.record_exit_document_drive_archive(uuid, text) is
    'Durably records one immutable Google Drive archive file ID for a reserved Exit document.';

comment on function public.mark_exit_document_email_attempt(uuid) is
    'Marks the Gmail external-send boundary before provider invocation so stale PROCESSING work cannot be blindly resent.';

comment on function public.record_exit_document_provider_acceptance(uuid, text) is
    'Durably records Gmail provider acceptance and removes the processing lease before final email completion.';

commit;