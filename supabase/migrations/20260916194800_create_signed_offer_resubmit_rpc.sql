begin;

-- Candidate re-upload RPC: called after HR sets a submission to MISMATCH_REVIEW.
-- Reuses the same storage-path convention as finalize_current_candidate_signed_offer.
-- The candidate supplies only the storage object path and original filename;
-- the candidate_id is always resolved server-side via current_candidate_id().

create or replace function public.resubmit_current_candidate_signed_offer(
    p_object_path     text,
    p_original_filename text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, storage, pg_temp
as $function$
declare
    v_candidate_id          uuid;
    v_app_user_id           uuid;
    v_lifecycle             public.hr_lifecycle%rowtype;
    v_old_file              public.candidate_signed_offer_files%rowtype;
    v_verification          public.signed_offer_verifications%rowtype;
    v_storage_object        storage.objects%rowtype;
    v_new_file_id           uuid;
    v_object_path           text;
    v_original_filename     text;
    v_mime_type             text;
    v_size_text             text;
    v_file_size_bytes       bigint;
    v_now                   timestamptz := pg_catalog.now();
begin
    -- ----------------------------------------------------------------
    -- 1. Authentication / role guard
    -- ----------------------------------------------------------------
    if public.current_user_is_active() is not true
       or public.current_user_has_role('CANDIDATE') is not true then
        raise insufficient_privilege
            using message = 'Candidate signed-offer access is not available.';
    end if;

    v_app_user_id  := public.current_app_user_id();
    v_candidate_id := public.current_candidate_id();

    if v_app_user_id is null or v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate signed-offer access is not available.';
    end if;

    -- ----------------------------------------------------------------
    -- 2. Advisory lock (same key pattern as first-submission RPC)
    -- ----------------------------------------------------------------
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'candidate-signed-offer:' || v_candidate_id::text,
            0::bigint
        )
    );

    -- ----------------------------------------------------------------
    -- 3. Load and lock the lifecycle row; verify MISMATCH_REVIEW
    -- ----------------------------------------------------------------
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
                message = 'Candidate lifecycle record is not available.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    if v_lifecycle.lifecycle_status is distinct from 'MISMATCH_REVIEW' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate is not eligible for signed-offer re-submission.';
    end if;

    -- ----------------------------------------------------------------
    -- 4. Load and lock the existing MISMATCH_REVIEW file row
    -- ----------------------------------------------------------------
    begin
        select f.*
        into strict v_old_file
        from public.candidate_signed_offer_files f
        where f.candidate_id = v_candidate_id
          and f.file_status = 'MISMATCH_REVIEW'
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'No rejected signed-offer file found for re-submission.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Multiple rejected signed-offer files found.';
    end;

    -- ----------------------------------------------------------------
    -- 5. Load the signed_offer_verifications row (same verification_id)
    -- ----------------------------------------------------------------
    begin
        select sov.*
        into strict v_verification
        from public.signed_offer_verifications sov
        where sov.verification_id = v_old_file.verification_id
          and sov.candidate_id    = v_candidate_id
          and sov.signed_offer_status = 'MISMATCH_REVIEW'
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Signed-offer verification record not found for re-submission.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Multiple signed-offer verification records found.';
    end;

    -- ----------------------------------------------------------------
    -- 6. Validate the new storage object path
    -- ----------------------------------------------------------------
    v_object_path := pg_catalog.btrim(coalesce(p_object_path, ''));

    if v_object_path = '' then
        raise exception using
            errcode = '22023',
            message = 'Signed-offer object path is required.';
    end if;

    if position('..' in v_object_path) > 0
       or v_object_path !~* (
           '^candidate/'
           || v_candidate_id::text
           || '/signed-offers/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.pdf$'
       ) then
        raise exception using
            errcode = '22023',
            message = 'Signed-offer object path is invalid.';
    end if;

    v_original_filename := pg_catalog.btrim(coalesce(p_original_filename, ''));

    if v_original_filename = ''
       or length(v_original_filename) > 255
       or position('/' in v_original_filename) > 0
       or position(pg_catalog.chr(92) in v_original_filename) > 0
       or position('..' in v_original_filename) > 0
       or v_original_filename !~* '\.pdf$' then
        raise exception using
            errcode = '22023',
            message = 'Original signed-offer filename is invalid.';
    end if;

    -- ----------------------------------------------------------------
    -- 7. Verify the Storage object was actually uploaded by this candidate
    -- ----------------------------------------------------------------
    begin
        select o.*
        into strict v_storage_object
        from storage.objects o
        where o.bucket_id = 'candidate-signed-offers'
          and o.name = v_object_path;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Uploaded signed-offer file was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Uploaded signed-offer file is ambiguous.';
    end;

    if v_storage_object.owner_id is null
       or v_storage_object.owner_id::text is distinct from auth.uid()::text then
        raise exception using
            errcode = '42501',
            message = 'Uploaded signed-offer file ownership is invalid.';
    end if;

    -- ----------------------------------------------------------------
    -- 8. Validate MIME type and file size from Storage metadata
    -- ----------------------------------------------------------------
    v_mime_type := pg_catalog.lower(
        pg_catalog.btrim(v_storage_object.metadata ->> 'mimetype')
    );
    v_size_text := pg_catalog.btrim(v_storage_object.metadata ->> 'size');

    if v_mime_type is distinct from 'application/pdf'
       or v_size_text is null
       or v_size_text !~ '^[0-9]+$' then
        raise exception using
            errcode = '22023',
            message = 'Uploaded signed-offer file metadata is invalid.';
    end if;

    begin
        v_file_size_bytes := v_size_text::bigint;
    exception
        when numeric_value_out_of_range then
            raise exception using
                errcode = '22023',
                message = 'Uploaded signed-offer file size is invalid.';
    end;

    if v_file_size_bytes <= 0 or v_file_size_bytes > 10485760 then
        raise exception using
            errcode = '22023',
            message = 'Uploaded signed-offer file size is invalid.';
    end if;

    -- ----------------------------------------------------------------
    -- 9. Guard against accidentally re-finalizing the same path
    -- ----------------------------------------------------------------
    if exists (
        select 1
        from public.candidate_signed_offer_files f
        where f.object_path = v_object_path
    ) then
        raise exception using
            errcode = '23505',
            message = 'This signed-offer file has already been finalized.';
    end if;

    -- ----------------------------------------------------------------
    -- 10. Mark the old file as REPLACED
    -- ----------------------------------------------------------------
    -- replaced_by_file_id is set after we obtain v_new_file_id (two-step).
    update public.candidate_signed_offer_files
    set file_status  = 'REPLACED',
        replaced_at  = v_now,
        updated_at   = v_now
    where file_id        = v_old_file.file_id
      and candidate_id   = v_candidate_id
      and file_status    = 'MISMATCH_REVIEW';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Rejected signed-offer file changed during re-submission.';
    end if;

    -- ----------------------------------------------------------------
    -- 11. Reset the existing verification record for the new submission
    -- ----------------------------------------------------------------
    update public.signed_offer_verifications
    set signed_offer_status      = 'SIGNED_OFFER_SUBMITTED',
        signed_offer_submitted_at = v_now,
        verified_at              = null,
        email_match_status       = null,
        phone_match_status       = null,
        verification_notes       = null,
        updated_at               = v_now
    where verification_id        = v_verification.verification_id
      and candidate_id           = v_candidate_id
      and signed_offer_status    = 'MISMATCH_REVIEW';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer verification changed during re-submission.';
    end if;

    -- ----------------------------------------------------------------
    -- 12. Insert the new candidate_signed_offer_files row
    -- ----------------------------------------------------------------
    insert into public.candidate_signed_offer_files (
        candidate_id,
        verification_id,
        bucket_id,
        object_path,
        original_filename,
        mime_type,
        file_size_bytes,
        file_status,
        uploaded_by,
        uploaded_at,
        submitted_at,
        created_at,
        updated_at
    ) values (
        v_candidate_id,
        v_verification.verification_id,
        'candidate-signed-offers',
        v_object_path,
        v_original_filename,
        'application/pdf',
        v_file_size_bytes,
        'SUBMITTED',
        v_app_user_id,
        v_now,
        v_now,
        v_now,
        v_now
    )
    returning file_id into v_new_file_id;

    -- ----------------------------------------------------------------
    -- 13. Back-fill replaced_by_file_id on the old row now that we have
    --     the new file_id (the schema column exists per inspection)
    -- ----------------------------------------------------------------
    update public.candidate_signed_offer_files
    set replaced_by_file_id = v_new_file_id,
        updated_at           = v_now
    where file_id = v_old_file.file_id
      and candidate_id = v_candidate_id;

    -- ----------------------------------------------------------------
    -- 14. Move lifecycle back to SIGNED_OFFER_SUBMITTED
    -- ----------------------------------------------------------------
    update public.hr_lifecycle
    set lifecycle_status = 'SIGNED_OFFER_SUBMITTED',
        updated_at       = v_now
    where lifecycle_id       = v_lifecycle.lifecycle_id
      and lifecycle_status   = 'MISMATCH_REVIEW';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle changed during re-submission.';
    end if;

    -- ----------------------------------------------------------------
    -- 15. Audit log
    -- ----------------------------------------------------------------
    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        from_status,
        to_status,
        remarks,
        activity_status,
        performed_by,
        performed_at,
        created_at,
        updated_at
    ) values (
        v_candidate_id,
        'SIGNED_OFFER_SUBMITTED',
        'MISMATCH_REVIEW',
        'SIGNED_OFFER_SUBMITTED',
        'Corrected signed offer PDF re-submitted by candidate after mismatch review',
        'SUCCESS',
        v_app_user_id::text,
        v_now,
        v_now,
        v_now
    );

    -- ----------------------------------------------------------------
    -- 16. Return same shape as finalize_current_candidate_signed_offer
    -- ----------------------------------------------------------------
    return jsonb_build_object(
        'fileId',             v_new_file_id,
        'candidateId',        v_candidate_id,
        'verificationId',     v_verification.verification_id,
        'objectPath',         v_object_path,
        'signedOfferStatus',  'SIGNED_OFFER_SUBMITTED',
        'lifecycleStatus',    'SIGNED_OFFER_SUBMITTED',
        'submittedAt',        v_now
    );
end;
$function$;

comment on function public.resubmit_current_candidate_signed_offer(text, text) is
    'Atomically replaces a rejected (MISMATCH_REVIEW) signed-offer file with a corrected re-upload. Marks the previous file REPLACED, resets the verification record, inserts the new file as SUBMITTED, restores lifecycle to SIGNED_OFFER_SUBMITTED, and writes an audit log entry. The candidate_id is always resolved server-side; no caller-supplied ID is accepted.';

revoke execute on function public.resubmit_current_candidate_signed_offer(text, text) from public;
revoke execute on function public.resubmit_current_candidate_signed_offer(text, text) from anon;
grant execute on function public.resubmit_current_candidate_signed_offer(text, text) to authenticated;
grant execute on function public.resubmit_current_candidate_signed_offer(text, text) to service_role;

commit;
