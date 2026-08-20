begin;

-- The live pre-migration inspection found no duplicate offer rows or nonblank
-- offer numbers. Refuse to guess or rewrite data if that changes before apply.
do $block$
begin
    if exists (
        select 1
        from public.hr_offer_letters hol
        group by hol.candidate_id
        having pg_catalog.count(*) > 1
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Duplicate candidate offer-letter rows must be reconciled before this migration can be applied.';
    end if;

    if exists (
        select 1
        from public.hr_offer_letters hol
        where nullif(pg_catalog.btrim(hol.offer_letter_number), '') is not null
        group by hol.offer_letter_number
        having pg_catalog.count(*) > 1
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Duplicate offer-letter numbers must be reconciled before this migration can be applied.';
    end if;
end;
$block$;

alter table public.hr_offer_letters
    add column if not exists google_doc_file_id text,
    add column if not exists google_pdf_file_id text,
    add column if not exists documents_prepared_at timestamptz,
    add column if not exists email_attempted_at timestamptz,
    add column if not exists gmail_message_id text,
    add column if not exists provider_accepted_at timestamptz;

do $block$
begin
    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.hr_offer_letters'::pg_catalog.regclass
          and conname = 'hr_offer_letters_google_doc_file_id_check'
    ) then
        alter table public.hr_offer_letters
            add constraint hr_offer_letters_google_doc_file_id_check
            check (
                google_doc_file_id is null
                or (
                    pg_catalog.btrim(google_doc_file_id) <> ''
                    and pg_catalog.char_length(google_doc_file_id) <= 255
                )
            );
    end if;

    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.hr_offer_letters'::pg_catalog.regclass
          and conname = 'hr_offer_letters_google_pdf_file_id_check'
    ) then
        alter table public.hr_offer_letters
            add constraint hr_offer_letters_google_pdf_file_id_check
            check (
                google_pdf_file_id is null
                or (
                    pg_catalog.btrim(google_pdf_file_id) <> ''
                    and pg_catalog.char_length(google_pdf_file_id) <= 255
                )
            );
    end if;

    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.hr_offer_letters'::pg_catalog.regclass
          and conname = 'hr_offer_letters_documents_prepared_check'
    ) then
        alter table public.hr_offer_letters
            add constraint hr_offer_letters_documents_prepared_check
            check (
                documents_prepared_at is null
                or (
                    google_doc_file_id is not null
                    and google_pdf_file_id is not null
                )
            );
    end if;

    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.hr_offer_letters'::pg_catalog.regclass
          and conname = 'hr_offer_letters_gmail_message_id_check'
    ) then
        alter table public.hr_offer_letters
            add constraint hr_offer_letters_gmail_message_id_check
            check (
                gmail_message_id is null
                or (
                    pg_catalog.btrim(gmail_message_id) <> ''
                    and pg_catalog.char_length(gmail_message_id) <= 500
                )
            );
    end if;

    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.hr_offer_letters'::pg_catalog.regclass
          and conname = 'hr_offer_letters_provider_acceptance_pair_check'
    ) then
        alter table public.hr_offer_letters
            add constraint hr_offer_letters_provider_acceptance_pair_check
            check (
                (gmail_message_id is null and provider_accepted_at is null)
                or
                (gmail_message_id is not null and provider_accepted_at is not null)
            );
    end if;
end;
$block$;

create unique index if not exists uq_hr_offer_letters_candidate_id
    on public.hr_offer_letters (candidate_id);

create unique index if not exists uq_hr_offer_letters_number_nonblank
    on public.hr_offer_letters (offer_letter_number)
    where nullif(pg_catalog.btrim(offer_letter_number), '') is not null;

comment on column public.hr_offer_letters.google_doc_file_id is
    'Private Google Drive file ID for the generated offer-letter Google Doc. A job-scoped private Drive appProperties marker recovers uncertain copy outcomes, and the resolved ID is persisted before later external steps.';

comment on column public.hr_offer_letters.google_pdf_file_id is
    'Private Google Drive file ID reserved for the generated offer-letter PDF. The ID is persisted before upload so retries reuse the same Drive identity.';

comment on column public.hr_offer_letters.documents_prepared_at is
    'Set only after the reserved Google Doc and PDF IDs both refer to successfully prepared private Drive files.';

comment on column public.hr_offer_letters.email_attempted_at is
    'Set immediately before each Gmail send request so stale workers can distinguish a safe pre-send interruption from an unknown delivery outcome.';

comment on column public.hr_offer_letters.gmail_message_id is
    'Non-secret Gmail provider message ID persisted immediately after provider acceptance.';

comment on column public.hr_offer_letters.provider_accepted_at is
    'Timestamp at which Gmail provider acceptance was durably recorded.';

create or replace function public.claim_offer_letter_job(
    p_candidate_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_is_service_call boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
    v_candidate public.master_candidates%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_job public.automation_jobs%rowtype;
    v_offer public.hr_offer_letters%rowtype;
    v_now timestamptz := pg_catalog.now();
    v_idempotency_key text;
    v_mid text;
    v_offer_letter_number text;
    v_full_name text;
    v_email text;
    v_applied_role text;
    v_role_code text;
    v_expected_end_date date;
    v_documents_ready boolean := false;
    v_stale_processing_timeout interval := interval '15 minutes';
begin
    if p_candidate_id is null then
        raise exception using
            errcode = '22023',
            message = 'Candidate ID is required.';
    end if;

    if not v_is_service_call then
        v_actor_user_id := public.current_app_user_id();

        if public.current_user_is_active() is not true
           or v_actor_user_id is null then
            raise exception using
                errcode = '42501',
                message = 'Active application-user authorization is required.';
        end if;

        if public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT',
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD',
                'FOUNDERS_OFFICE',
                'ADMIN'
            ]::text[]
        ) is not true then
            raise exception using
                errcode = '42501',
                message = 'An approved HR staff role is required.';
        end if;
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || p_candidate_id::text,
            0::bigint
        )
    );

    begin
        select c.*
        into strict v_candidate
        from public.master_candidates c
        where c.candidate_id = p_candidate_id
        for share;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate was not found.';
    end;

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = p_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    v_idempotency_key := 'OFFER_LETTER:' || p_candidate_id::text;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.idempotency_key = v_idempotency_key
    for update;

    if v_job.job_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter automation job was not found.';
    end if;

    if v_job.job_type is distinct from 'OFFER_LETTER'
       or v_job.candidate_id is distinct from p_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter automation job state is inconsistent.';
    end if;

    if v_is_service_call then
        v_actor_user_id := v_job.requested_by;
    end if;

    v_mid := nullif(pg_catalog.btrim(v_lifecycle.mid), '');
    v_offer_letter_number := case
        when v_mid is null then null
        else 'OL-' || v_mid
    end;
    v_full_name := nullif(pg_catalog.btrim(v_candidate.full_name), '');
    v_email := nullif(
        pg_catalog.lower(pg_catalog.btrim(v_candidate.email)),
        ''
    );
    v_applied_role := nullif(pg_catalog.btrim(v_candidate.applied_role), '');
    v_role_code := nullif(
        pg_catalog.upper(pg_catalog.btrim(v_candidate.role_code)),
        ''
    );
    v_expected_end_date := coalesce(
        v_lifecycle.current_end_date,
        v_lifecycle.original_end_date,
        v_lifecycle.probation_end_date
    );

    if v_mid is null or v_offer_letter_number is null then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate MID is required for offer preparation.';
    end if;

    if v_full_name is null then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate full name is required for offer preparation.';
    end if;

    if v_email is null
       or v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate email is not valid for offer delivery.';
    end if;

    if v_applied_role is null or v_role_code is null then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate role information is required for offer preparation.';
    end if;

    if v_lifecycle.probation_start_date is null
       or v_expected_end_date is null
       or v_lifecycle.internship_duration_months is null then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate internship dates and duration are required for offer preparation.';
    end if;

    if v_job.payload ->> 'mid' is distinct from v_mid
       or v_job.payload ->> 'offerLetterNumber'
          is distinct from v_offer_letter_number then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter automation payload does not match authoritative lifecycle data.';
    end if;

    select hol.*
    into v_offer
    from public.hr_offer_letters hol
    where hol.candidate_id = p_candidate_id
    for update;

    if v_offer.offer_letter_id is null then
        insert into public.hr_offer_letters (
            candidate_id,
            offer_status,
            offer_letter_number,
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            'NOT_STARTED',
            v_offer_letter_number,
            v_now,
            v_now
        )
        returning * into v_offer;
    elsif nullif(pg_catalog.btrim(v_offer.offer_letter_number), '') is null then
        update public.hr_offer_letters
        set
            offer_letter_number = v_offer_letter_number,
            updated_at = v_now
        where offer_letter_id = v_offer.offer_letter_id
        returning * into v_offer;
    elsif v_offer.offer_letter_number is distinct from v_offer_letter_number then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter number conflicts with the candidate MID.';
    end if;

    if (v_job.provider_message_id is null)
       is distinct from (v_job.provider_accepted_at is null) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter job provider acceptance state is inconsistent.';
    end if;

    if (v_offer.gmail_message_id is null)
       is distinct from (v_offer.provider_accepted_at is null) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter provider acceptance state is inconsistent.';
    end if;

    if v_offer.google_pdf_file_id is not null
       and v_offer.google_doc_file_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter document state is inconsistent.';
    end if;

    v_documents_ready := v_offer.documents_prepared_at is not null
        and v_offer.google_doc_file_id is not null
        and v_offer.google_pdf_file_id is not null;

    if v_job.provider_message_id is not null
       and (
           v_offer.gmail_message_id is distinct from v_job.provider_message_id
           or v_offer.provider_accepted_at
              is distinct from v_job.provider_accepted_at
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter provider acceptance records do not match.';
    end if;

    if v_job.provider_message_id is null
       and v_offer.gmail_message_id is not null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter provider acceptance records do not match.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        if v_lifecycle.lifecycle_status is distinct from 'ACTIVE'
           or v_offer.offer_status is distinct from 'OFFER_LETTER_SENT'
           or not v_documents_ready
           or v_job.provider_message_id is null then
            raise exception using
                errcode = 'P0001',
                message = 'Completed offer-letter automation state is inconsistent.';
        end if;

        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', p_candidate_id,
            'offerLetterId', v_offer.offer_letter_id,
            'jobStatus', v_job.job_status,
            'attemptCount', v_job.attempt_count,
            'shouldProcessExternal', false,
            'needsFinalization', false,
            'alreadyCompleted', true,
            'fullName', v_full_name,
            'email', v_email,
            'phone', v_candidate.phone,
            'address', v_candidate.address,
            'appliedRole', v_applied_role,
            'roleCode', v_role_code,
            'mid', v_mid,
            'offerLetterNumber', v_offer_letter_number,
            'joiningDate', v_lifecycle.probation_start_date,
            'expectedEndDate', v_expected_end_date,
            'internshipDurationMonths',
                v_lifecycle.internship_duration_months,
            'offerDate',
                (coalesce(v_offer.created_at, v_now)
                    at time zone 'Asia/Kolkata')::date,
            'googleDocFileId', v_offer.google_doc_file_id,
            'googlePdfFileId', v_offer.google_pdf_file_id,
            'documentsPreparedAt', v_offer.documents_prepared_at,
            'emailAttemptedAt', v_offer.email_attempted_at,
            'gmailMessageId', v_offer.gmail_message_id
        );
    end if;

    if v_job.job_status = 'CANCELLED' then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter automation job is cancelled.';
    end if;

    if v_job.provider_message_id is not null then
        if not v_documents_ready then
            raise exception using
                errcode = 'P0001',
                message = 'Offer-letter provider acceptance exists without prepared documents.';
        end if;

        update public.automation_jobs
        set
            job_status = 'PROCESSING',
            attempt_count = attempt_count + 1,
            requested_by = v_actor_user_id,
            last_attempt_at = v_now,
            completed_at = null,
            error_message = null,
            updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;

        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', p_candidate_id,
            'offerLetterId', v_offer.offer_letter_id,
            'jobStatus', v_job.job_status,
            'attemptCount', v_job.attempt_count,
            'shouldProcessExternal', false,
            'needsFinalization', true,
            'alreadyCompleted', false,
            'fullName', v_full_name,
            'email', v_email,
            'phone', v_candidate.phone,
            'address', v_candidate.address,
            'appliedRole', v_applied_role,
            'roleCode', v_role_code,
            'mid', v_mid,
            'offerLetterNumber', v_offer_letter_number,
            'joiningDate', v_lifecycle.probation_start_date,
            'expectedEndDate', v_expected_end_date,
            'internshipDurationMonths',
                v_lifecycle.internship_duration_months,
            'offerDate',
                (coalesce(v_offer.created_at, v_now)
                    at time zone 'Asia/Kolkata')::date,
            'googleDocFileId', v_offer.google_doc_file_id,
            'googlePdfFileId', v_offer.google_pdf_file_id,
            'documentsPreparedAt', v_offer.documents_prepared_at,
            'emailAttemptedAt', v_offer.email_attempted_at,
            'gmailMessageId', v_offer.gmail_message_id
        );
    end if;

    if v_lifecycle.lifecycle_status not in (
        'MID_GENERATED',
        'OFFER_LETTER_GENERATED'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle is not eligible for offer preparation.';
    end if;

    if v_job.job_status = 'PROCESSING' then
        if coalesce(
            v_job.last_attempt_at,
            v_job.updated_at,
            v_job.created_at
        ) > v_now - v_stale_processing_timeout then
            raise exception using
                errcode = 'P0001',
                message = 'Offer-letter job is already being processed.';
        end if;

        if v_documents_ready and v_offer.email_attempted_at is not null then
            raise exception using
                errcode = 'P0001',
                message = 'Previous offer-email attempt has an unknown delivery outcome. Check the sender Sent folder before retrying.';
        end if;
    elsif v_job.job_status not in ('PENDING', 'FAILED', 'RETRY') then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter automation job is not claimable.';
    end if;

    update public.automation_jobs
    set
        job_status = 'PROCESSING',
        attempt_count = attempt_count + 1,
        requested_by = v_actor_user_id,
        last_attempt_at = v_now,
        completed_at = null,
        error_message = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', p_candidate_id,
        'offerLetterId', v_offer.offer_letter_id,
        'jobStatus', v_job.job_status,
        'attemptCount', v_job.attempt_count,
        'shouldProcessExternal', true,
        'needsFinalization', false,
        'alreadyCompleted', false,
        'fullName', v_full_name,
        'email', v_email,
        'phone', v_candidate.phone,
        'address', v_candidate.address,
        'appliedRole', v_applied_role,
        'roleCode', v_role_code,
        'mid', v_mid,
        'offerLetterNumber', v_offer_letter_number,
        'joiningDate', v_lifecycle.probation_start_date,
        'expectedEndDate', v_expected_end_date,
        'internshipDurationMonths',
            v_lifecycle.internship_duration_months,
        'offerDate',
            (coalesce(v_offer.created_at, v_now)
                at time zone 'Asia/Kolkata')::date,
        'googleDocFileId', v_offer.google_doc_file_id,
        'googlePdfFileId', v_offer.google_pdf_file_id,
        'documentsPreparedAt', v_offer.documents_prepared_at,
        'emailAttemptedAt', v_offer.email_attempted_at,
        'gmailMessageId', v_offer.gmail_message_id
    );
end;
$function$;

comment on function public.claim_offer_letter_job(uuid) is
    'Authorizes approved HR callers or service-role workers, serializes one offer-letter claim, returns authoritative candidate/lifecycle data, supports document/finalization recovery, and blocks automatic resend after an unknown Gmail delivery outcome.';

create or replace function public.record_offer_letter_documents(
    p_job_id uuid,
    p_claim_attempt_count integer,
    p_google_doc_file_id text,
    p_google_pdf_file_id text,
    p_documents_ready boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_offer public.hr_offer_letters%rowtype;
    v_doc_file_id text;
    v_pdf_file_id text;
    v_now timestamptz := pg_catalog.now();
    v_ready boolean;
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    if p_claim_attempt_count is null or p_claim_attempt_count <= 0 then
        raise exception using
            errcode = '22023',
            message = 'A valid claim attempt count is required.';
    end if;

    v_doc_file_id := nullif(pg_catalog.btrim(p_google_doc_file_id), '');
    v_pdf_file_id := nullif(pg_catalog.btrim(p_google_pdf_file_id), '');

    if v_doc_file_id is null
       or pg_catalog.char_length(v_doc_file_id) > 255 then
        raise exception using
            errcode = '22023',
            message = 'A valid Google Doc file ID is required.';
    end if;

    if p_google_pdf_file_id is not null
       and (
           v_pdf_file_id is null
           or pg_catalog.char_length(v_pdf_file_id) > 255
       ) then
        raise exception using
            errcode = '22023',
            message = 'Google PDF file ID is invalid.';
    end if;

    if p_documents_ready is null then
        raise exception using
            errcode = '22023',
            message = 'Document readiness is required.';
    end if;

    select aj.candidate_id
    into v_candidate_id
    from public.automation_jobs aj
    where aj.job_id = p_job_id;

    if v_candidate_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job was not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_type is distinct from 'OFFER_LETTER'
       or v_job.candidate_id is distinct from v_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a valid offer-letter job.';
    end if;

    if v_job.attempt_count is distinct from p_claim_attempt_count then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter claim is no longer current.';
    end if;

    select hol.*
    into v_offer
    from public.hr_offer_letters hol
    where hol.candidate_id = v_candidate_id
    for update;

    if v_offer.offer_letter_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter record was not found.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        if v_offer.google_doc_file_id is distinct from v_doc_file_id
           or (
               v_pdf_file_id is not null
               and v_offer.google_pdf_file_id is distinct from v_pdf_file_id
           ) then
            raise exception using
                errcode = 'P0001',
                message = 'Completed offer-letter document IDs cannot be changed.';
        end if;

        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', v_candidate_id,
            'offerLetterId', v_offer.offer_letter_id,
            'lifecycleStatus', v_lifecycle.lifecycle_status,
            'googleDocFileId', v_offer.google_doc_file_id,
            'googlePdfFileId', v_offer.google_pdf_file_id,
            'documentsPreparedAt', v_offer.documents_prepared_at,
            'documentsReady', v_offer.documents_prepared_at is not null
        );
    end if;

    if v_job.job_status not in ('PROCESSING', 'RETRY') then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter job is not ready to record documents.';
    end if;

    if v_offer.google_doc_file_id is not null
       and v_offer.google_doc_file_id is distinct from v_doc_file_id then
        raise exception using
            errcode = 'P0001',
            message = 'Google Doc file ID conflicts with the stored value.';
    end if;

    if v_pdf_file_id is not null
       and v_offer.google_pdf_file_id is not null
       and v_offer.google_pdf_file_id is distinct from v_pdf_file_id then
        raise exception using
            errcode = 'P0001',
            message = 'Google PDF file ID conflicts with the stored value.';
    end if;

    if p_documents_ready
       and coalesce(v_pdf_file_id, v_offer.google_pdf_file_id) is null then
        raise exception using
            errcode = '22023',
            message = 'Google PDF file ID is required before documents are ready.';
    end if;

    update public.hr_offer_letters
    set
        google_doc_file_id = coalesce(
            google_doc_file_id,
            v_doc_file_id
        ),
        google_pdf_file_id = coalesce(
            google_pdf_file_id,
            v_pdf_file_id
        ),
        documents_prepared_at = case
            when p_documents_ready then coalesce(
                documents_prepared_at,
                v_now
            )
            else documents_prepared_at
        end,
        updated_at = v_now
    where offer_letter_id = v_offer.offer_letter_id
    returning * into v_offer;

    v_ready := v_offer.documents_prepared_at is not null
        and v_offer.google_doc_file_id is not null
        and v_offer.google_pdf_file_id is not null;

    if v_ready then
        if v_lifecycle.lifecycle_status = 'MID_GENERATED' then
            update public.hr_lifecycle
            set
                lifecycle_status = 'OFFER_LETTER_GENERATED',
                updated_at = v_now
            where lifecycle_id = v_lifecycle.lifecycle_id
            returning * into v_lifecycle;

            insert into public.hr_activity_logs (
                candidate_id,
                activity_type,
                from_status,
                to_status,
                remarks,
                activity_status,
                metadata,
                performed_by,
                performed_at
            ) values (
                v_candidate_id,
                'OFFER_LETTER_GENERATED',
                'MID_GENERATED',
                'OFFER_LETTER_GENERATED',
                'Offer letter documents generated automatically',
                'SUCCESS',
                pg_catalog.jsonb_build_object(
                    'jobId', v_job.job_id,
                    'offerLetterId', v_offer.offer_letter_id,
                    'googleDocFileId', v_offer.google_doc_file_id,
                    'googlePdfFileId', v_offer.google_pdf_file_id
                ),
                'HR AUTOMATION',
                v_now
            );
        elsif v_lifecycle.lifecycle_status
              is distinct from 'OFFER_LETTER_GENERATED' then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle is not ready for generated offer documents.';
        end if;

        update public.hr_offer_letters
        set
            offer_status = 'OFFER_LETTER_GENERATED',
            generated_at = coalesce(generated_at, v_now),
            updated_at = v_now
        where offer_letter_id = v_offer.offer_letter_id
        returning * into v_offer;
    elsif v_lifecycle.lifecycle_status not in (
        'MID_GENERATED',
        'OFFER_LETTER_GENERATED'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle is not ready for offer documents.';
    end if;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_candidate_id,
        'offerLetterId', v_offer.offer_letter_id,
        'lifecycleStatus', v_lifecycle.lifecycle_status,
        'googleDocFileId', v_offer.google_doc_file_id,
        'googlePdfFileId', v_offer.google_pdf_file_id,
        'documentsPreparedAt', v_offer.documents_prepared_at,
        'documentsReady', v_ready
    );
end;
$function$;

comment on function public.record_offer_letter_documents(uuid, integer, text, text, boolean) is
    'Service-role-only persistence for reserved Google Doc/PDF identities and final document readiness. The ready transition atomically records OFFER_LETTER_GENERATED and its activity log.';

create or replace function public.begin_offer_letter_email_send(
    p_job_id uuid,
    p_claim_attempt_count integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_offer public.hr_offer_letters%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    if p_claim_attempt_count is null or p_claim_attempt_count <= 0 then
        raise exception using
            errcode = '22023',
            message = 'A valid claim attempt count is required.';
    end if;

    select aj.candidate_id
    into v_candidate_id
    from public.automation_jobs aj
    where aj.job_id = p_job_id;

    if v_candidate_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job was not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_type is distinct from 'OFFER_LETTER'
       or v_job.candidate_id is distinct from v_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a valid offer-letter job.';
    end if;

    if v_job.attempt_count is distinct from p_claim_attempt_count then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter claim is no longer current.';
    end if;

    select hol.*
    into v_offer
    from public.hr_offer_letters hol
    where hol.candidate_id = v_candidate_id
    for update;

    if v_offer.offer_letter_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter record was not found.';
    end if;

    if v_job.job_status is distinct from 'PROCESSING' then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter job is not ready to send email.';
    end if;

    if v_job.provider_message_id is not null
       or v_job.provider_accepted_at is not null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer email already has provider acceptance.';
    end if;

    if v_offer.documents_prepared_at is null
       or v_offer.google_doc_file_id is null
       or v_offer.google_pdf_file_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter documents are not ready for email delivery.';
    end if;

    if v_lifecycle.lifecycle_status
       is distinct from 'OFFER_LETTER_GENERATED' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle is not ready for offer-email delivery.';
    end if;

    update public.hr_offer_letters
    set
        email_attempted_at = v_now,
        updated_at = v_now
    where offer_letter_id = v_offer.offer_letter_id
    returning * into v_offer;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_candidate_id,
        'offerLetterId', v_offer.offer_letter_id,
        'jobStatus', v_job.job_status,
        'emailAttemptedAt', v_offer.email_attempted_at,
        'readyToSend', true
    );
end;
$function$;

comment on function public.begin_offer_letter_email_send(uuid, integer) is
    'Service-role-only durable send-intent marker written immediately before Gmail. Stale claims with no marker can resume safely; stale marked claims require delivery reconciliation.';

create or replace function public.record_offer_letter_provider_acceptance(
    p_job_id uuid,
    p_claim_attempt_count integer,
    p_provider_message_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_offer public.hr_offer_letters%rowtype;
    v_provider_message_id text;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    if p_claim_attempt_count is null or p_claim_attempt_count <= 0 then
        raise exception using
            errcode = '22023',
            message = 'A valid claim attempt count is required.';
    end if;

    v_provider_message_id := nullif(
        pg_catalog.btrim(p_provider_message_id),
        ''
    );

    if v_provider_message_id is null
       or pg_catalog.char_length(v_provider_message_id) > 500 then
        raise exception using
            errcode = '22023',
            message = 'A valid provider message ID is required.';
    end if;

    select aj.candidate_id
    into v_candidate_id
    from public.automation_jobs aj
    where aj.job_id = p_job_id;

    if v_candidate_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job was not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_type is distinct from 'OFFER_LETTER'
       or v_job.candidate_id is distinct from v_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a valid offer-letter job.';
    end if;

    if v_job.attempt_count is distinct from p_claim_attempt_count then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter claim is no longer current.';
    end if;

    select hol.*
    into v_offer
    from public.hr_offer_letters hol
    where hol.candidate_id = v_candidate_id
    for update;

    if v_offer.offer_letter_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter record was not found.';
    end if;

    if (v_job.provider_message_id is null)
       is distinct from (v_job.provider_accepted_at is null) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter job provider acceptance state is inconsistent.';
    end if;

    if (v_offer.gmail_message_id is null)
       is distinct from (v_offer.provider_accepted_at is null) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter provider acceptance state is inconsistent.';
    end if;

    if v_job.provider_message_id is not null
       and v_job.provider_message_id is distinct from v_provider_message_id then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter provider message ID conflicts with the stored value.';
    end if;

    if v_offer.gmail_message_id is not null
       and v_offer.gmail_message_id is distinct from v_provider_message_id then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter Gmail message ID conflicts with the stored value.';
    end if;

    if v_job.provider_message_id = v_provider_message_id
       and v_job.provider_accepted_at is not null
       and v_offer.gmail_message_id = v_provider_message_id
       and v_offer.provider_accepted_at is not null then
        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', v_candidate_id,
            'jobStatus', v_job.job_status,
            'providerAccepted', true,
            'providerAcceptedAt', v_job.provider_accepted_at
        );
    end if;

    if v_job.job_status not in ('PROCESSING', 'RETRY') then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter job is not ready for provider acceptance.';
    end if;

    if v_offer.documents_prepared_at is null
       or v_offer.google_doc_file_id is null
       or v_offer.google_pdf_file_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter documents are not ready for email delivery.';
    end if;

    if v_offer.email_attempted_at is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-email send intent was not recorded.';
    end if;

    if v_lifecycle.lifecycle_status not in (
        'OFFER_LETTER_GENERATED',
        'OFFER_LETTER_SENT',
        'ACTIVE'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle is not ready for offer-email acceptance.';
    end if;

    update public.automation_jobs
    set
        provider_message_id = v_provider_message_id,
        provider_accepted_at = coalesce(provider_accepted_at, v_now),
        job_status = 'RETRY',
        completed_at = null,
        error_message = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    update public.hr_offer_letters
    set
        gmail_message_id = v_provider_message_id,
        provider_accepted_at = coalesce(provider_accepted_at, v_now),
        updated_at = v_now
    where offer_letter_id = v_offer.offer_letter_id
    returning * into v_offer;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_candidate_id,
        'jobStatus', v_job.job_status,
        'providerAccepted', true,
        'providerAcceptedAt', v_job.provider_accepted_at
    );
end;
$function$;

comment on function public.record_offer_letter_provider_acceptance(uuid, integer, text) is
    'Service-role-only persistence of matching automation-job and offer-letter Gmail acceptance metadata before lifecycle finalization.';

create or replace function public.record_offer_letter_failure(
    p_job_id uuid,
    p_claim_attempt_count integer,
    p_error_message text,
    p_retryable boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_offer public.hr_offer_letters%rowtype;
    v_raw_error text;
    v_safe_error text;
    v_next_status text;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    if p_claim_attempt_count is null or p_claim_attempt_count <= 0 then
        raise exception using
            errcode = '22023',
            message = 'A valid claim attempt count is required.';
    end if;

    if p_retryable is null then
        raise exception using
            errcode = '22023',
            message = 'Retry classification is required.';
    end if;

    select aj.candidate_id
    into v_candidate_id
    from public.automation_jobs aj
    where aj.job_id = p_job_id;

    if v_candidate_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job was not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_type is distinct from 'OFFER_LETTER'
       or v_job.candidate_id is distinct from v_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a valid offer-letter job.';
    end if;

    if v_job.attempt_count is distinct from p_claim_attempt_count then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter claim is no longer current.';
    end if;

    select hol.*
    into v_offer
    from public.hr_offer_letters hol
    where hol.candidate_id = v_candidate_id
    for update;

    if v_offer.offer_letter_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter record was not found.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', v_candidate_id,
            'jobStatus', v_job.job_status
        );
    end if;

    if v_job.job_status = 'CANCELLED' then
        raise exception using
            errcode = 'P0001',
            message = 'Cancelled offer-letter job cannot record a failure.';
    end if;

    if v_job.provider_message_id is not null
       or v_job.provider_accepted_at is not null then
        raise exception using
            errcode = 'P0001',
            message = 'Provider-accepted offer email must be finalized, not failed.';
    end if;

    v_raw_error := pg_catalog.btrim(coalesce(p_error_message, ''));

    if v_raw_error = '' then
        v_safe_error := 'Offer-letter automation failed.';
    elsif v_raw_error ~ E'[\r\n]'
          or pg_catalog.lower(v_raw_error) ~
              '(authorization|bearer|api[ _-]?key|access[ _-]?token|refresh[ _-]?token|secret|password|cookie|headers?)'
          or pg_catalog.left(v_raw_error, 1) in ('{', '[') then
        v_safe_error :=
            'Offer-letter provider request failed. Sensitive details were omitted.';
    else
        v_safe_error := pg_catalog.left(
            pg_catalog.regexp_replace(
                v_raw_error,
                '[[:space:]]+',
                ' ',
                'g'
            ),
            1000
        );
    end if;

    v_next_status := case
        when p_retryable then 'RETRY'
        else 'FAILED'
    end;

    update public.automation_jobs
    set
        job_status = v_next_status,
        completed_at = case
            when p_retryable then null
            else v_now
        end,
        error_message = v_safe_error,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_candidate_id,
        'jobStatus', v_job.job_status
    );
end;
$function$;

comment on function public.record_offer_letter_failure(uuid, integer, text, boolean) is
    'Service-role-only storage of sanitized definite failure/retry state. It preserves reserved document identities and refuses to downgrade provider-accepted delivery.';

create or replace function public.finalize_offer_letter_success(
    p_job_id uuid,
    p_claim_attempt_count integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_offer public.hr_offer_letters%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    if p_claim_attempt_count is null or p_claim_attempt_count <= 0 then
        raise exception using
            errcode = '22023',
            message = 'A valid claim attempt count is required.';
    end if;

    select aj.candidate_id
    into v_candidate_id
    from public.automation_jobs aj
    where aj.job_id = p_job_id;

    if v_candidate_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job was not found.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.job_id = p_job_id
    for update;

    if v_job.job_type is distinct from 'OFFER_LETTER'
       or v_job.candidate_id is distinct from v_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a valid offer-letter job.';
    end if;

    if v_job.attempt_count is distinct from p_claim_attempt_count then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter claim is no longer current.';
    end if;

    select hol.*
    into v_offer
    from public.hr_offer_letters hol
    where hol.candidate_id = v_candidate_id
    for update;

    if v_offer.offer_letter_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter record was not found.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        if v_lifecycle.lifecycle_status is distinct from 'ACTIVE'
           or v_offer.offer_status is distinct from 'OFFER_LETTER_SENT' then
            raise exception using
                errcode = 'P0001',
                message = 'Completed offer-letter automation state is inconsistent.';
        end if;

        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', v_candidate_id,
            'offerLetterId', v_offer.offer_letter_id,
            'jobStatus', v_job.job_status,
            'lifecycleStatus', v_lifecycle.lifecycle_status,
            'offerStatus', v_offer.offer_status,
            'providerAcceptedAt', v_job.provider_accepted_at,
            'completedAt', v_job.completed_at
        );
    end if;

    if v_job.provider_message_id is null
       or v_job.provider_accepted_at is null
       or v_offer.gmail_message_id is distinct from v_job.provider_message_id
       or v_offer.provider_accepted_at
          is distinct from v_job.provider_accepted_at then
        raise exception using
            errcode = 'P0001',
            message = 'Offer email has not been durably accepted by the provider.';
    end if;

    if v_offer.documents_prepared_at is null
       or v_offer.google_doc_file_id is null
       or v_offer.google_pdf_file_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter documents are not ready for finalization.';
    end if;

    if v_offer.email_attempted_at is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-email send intent was not recorded.';
    end if;

    if v_job.job_status not in ('PROCESSING', 'RETRY') then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter job is not ready for finalization.';
    end if;

    if v_lifecycle.lifecycle_status = 'OFFER_LETTER_GENERATED' then
        update public.hr_lifecycle
        set
            lifecycle_status = 'OFFER_LETTER_SENT',
            updated_at = v_now
        where lifecycle_id = v_lifecycle.lifecycle_id
        returning * into v_lifecycle;

        insert into public.hr_activity_logs (
            candidate_id,
            activity_type,
            from_status,
            to_status,
            remarks,
            activity_status,
            metadata,
            performed_by,
            performed_at
        ) values (
            v_candidate_id,
            'OFFER_LETTER_SENT',
            'OFFER_LETTER_GENERATED',
            'OFFER_LETTER_SENT',
            'Offer letter email accepted by Gmail',
            'SUCCESS',
            pg_catalog.jsonb_build_object(
                'jobId', v_job.job_id,
                'offerLetterId', v_offer.offer_letter_id,
                'gmailMessageId', v_job.provider_message_id
            ),
            'HR AUTOMATION',
            v_now
        );
    elsif v_lifecycle.lifecycle_status not in (
        'OFFER_LETTER_SENT',
        'ACTIVE'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle is not ready for offer finalization.';
    end if;

    if v_lifecycle.lifecycle_status = 'OFFER_LETTER_SENT' then
        update public.hr_lifecycle
        set
            lifecycle_status = 'ACTIVE',
            updated_at = v_now
        where lifecycle_id = v_lifecycle.lifecycle_id
        returning * into v_lifecycle;

        insert into public.hr_activity_logs (
            candidate_id,
            activity_type,
            from_status,
            to_status,
            remarks,
            activity_status,
            metadata,
            performed_by,
            performed_at
        ) values (
            v_candidate_id,
            'ACTIVE',
            'OFFER_LETTER_SENT',
            'ACTIVE',
            'Candidate activated automatically after offer email acceptance',
            'SUCCESS',
            pg_catalog.jsonb_build_object(
                'jobId', v_job.job_id,
                'offerLetterId', v_offer.offer_letter_id
            ),
            'HR AUTOMATION',
            v_now
        );
    end if;

    update public.hr_offer_letters
    set
        offer_status = 'OFFER_LETTER_SENT',
        sent_at = coalesce(sent_at, v_job.provider_accepted_at, v_now),
        updated_at = v_now
    where offer_letter_id = v_offer.offer_letter_id
    returning * into v_offer;

    update public.automation_jobs
    set
        job_status = 'SUCCESS',
        completed_at = v_now,
        error_message = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_candidate_id,
        'offerLetterId', v_offer.offer_letter_id,
        'jobStatus', v_job.job_status,
        'lifecycleStatus', v_lifecycle.lifecycle_status,
        'offerStatus', v_offer.offer_status,
        'providerAcceptedAt', v_job.provider_accepted_at,
        'completedAt', v_job.completed_at
    );
end;
$function$;

comment on function public.finalize_offer_letter_success(uuid, integer) is
    'After durable Gmail acceptance, atomically records OFFER_LETTER_SENT and ACTIVE lifecycle history, updates the offer record, and completes the OFFER_LETTER automation job. Repeated SUCCESS calls do not duplicate logs.';

revoke all privileges
    on function public.claim_offer_letter_job(uuid)
    from public;
revoke all privileges
    on function public.claim_offer_letter_job(uuid)
    from anon;
revoke all privileges
    on function public.claim_offer_letter_job(uuid)
    from authenticated;
grant execute
    on function public.claim_offer_letter_job(uuid)
    to authenticated;
grant execute
    on function public.claim_offer_letter_job(uuid)
    to service_role;

revoke all privileges
    on function public.record_offer_letter_documents(
        uuid,
        integer,
        text,
        text,
        boolean
    )
    from public;
revoke all privileges
    on function public.record_offer_letter_documents(
        uuid,
        integer,
        text,
        text,
        boolean
    )
    from anon;
revoke all privileges
    on function public.record_offer_letter_documents(
        uuid,
        integer,
        text,
        text,
        boolean
    )
    from authenticated;
grant execute
    on function public.record_offer_letter_documents(
        uuid,
        integer,
        text,
        text,
        boolean
    )
    to service_role;

revoke all privileges
    on function public.begin_offer_letter_email_send(uuid, integer)
    from public;
revoke all privileges
    on function public.begin_offer_letter_email_send(uuid, integer)
    from anon;
revoke all privileges
    on function public.begin_offer_letter_email_send(uuid, integer)
    from authenticated;
grant execute
    on function public.begin_offer_letter_email_send(uuid, integer)
    to service_role;

revoke all privileges
    on function public.record_offer_letter_provider_acceptance(uuid, integer, text)
    from public;
revoke all privileges
    on function public.record_offer_letter_provider_acceptance(uuid, integer, text)
    from anon;
revoke all privileges
    on function public.record_offer_letter_provider_acceptance(uuid, integer, text)
    from authenticated;
grant execute
    on function public.record_offer_letter_provider_acceptance(uuid, integer, text)
    to service_role;

revoke all privileges
    on function public.record_offer_letter_failure(uuid, integer, text, boolean)
    from public;
revoke all privileges
    on function public.record_offer_letter_failure(uuid, integer, text, boolean)
    from anon;
revoke all privileges
    on function public.record_offer_letter_failure(uuid, integer, text, boolean)
    from authenticated;
grant execute
    on function public.record_offer_letter_failure(uuid, integer, text, boolean)
    to service_role;

revoke all privileges
    on function public.finalize_offer_letter_success(uuid, integer)
    from public;
revoke all privileges
    on function public.finalize_offer_letter_success(uuid, integer)
    from anon;
revoke all privileges
    on function public.finalize_offer_letter_success(uuid, integer)
    from authenticated;
grant execute
    on function public.finalize_offer_letter_success(uuid, integer)
    to service_role;

commit;
