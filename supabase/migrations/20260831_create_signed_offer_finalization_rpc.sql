create or replace function public.finalize_current_candidate_signed_offer(
    p_object_path text,
    p_original_filename text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, storage, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_app_user_id uuid;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_storage_object storage.objects%rowtype;
    v_verification_id uuid;
    v_file_id uuid;
    v_object_path text;
    v_original_filename text;
    v_mime_type text;
    v_size_text text;
    v_file_size_bytes bigint;
    v_now timestamptz := pg_catalog.now();
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_role('CANDIDATE') is not true then
        raise insufficient_privilege
            using message = 'Candidate signed-offer access is not available.';
    end if;

    v_app_user_id := public.current_app_user_id();
    v_candidate_id := public.current_candidate_id();

    if v_app_user_id is null or v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate signed-offer access is not available.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'candidate-signed-offer:' || v_candidate_id::text,
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
                message = 'Candidate lifecycle record is not available.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    if v_lifecycle.lifecycle_status is distinct from 'ACTIVE' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate is not eligible for signed-offer submission.';
    end if;

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

    v_mime_type := pg_catalog.lower(
        pg_catalog.btrim(v_storage_object.metadata ->> 'mimetype')
    );
    v_size_text := pg_catalog.btrim(v_storage_object.metadata ->> 'size');

    -- MIME metadata validation does not perform PDF-content or malware scanning.
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

    if exists (
        select 1
        from public.candidate_signed_offer_files f
        where f.object_path = v_object_path
    ) then
        raise exception using
            errcode = '23505',
            message = 'This signed-offer file has already been finalized.';
    end if;

    if exists (
        select 1
        from public.candidate_signed_offer_files f
        where f.candidate_id = v_candidate_id
          and f.file_status in ('SUBMITTED', 'VERIFIED', 'MISMATCH_REVIEW')
    ) then
        raise exception using
            errcode = '23505',
            message = 'A current signed-offer file already exists.';
    end if;

    if exists (
        select 1
        from public.signed_offer_verifications sov
        where sov.candidate_id = v_candidate_id
          and (
              sov.signed_offer_submitted_at is not null
              or sov.signed_offer_status in (
                  'SIGNED_OFFER_SUBMITTED',
                  'SIGNED_OFFER_VERIFIED',
                  'MISMATCH_REVIEW'
              )
          )
    ) then
        raise exception using
            errcode = '23505',
            message = 'A signed-offer submission already exists.';
    end if;

    insert into public.signed_offer_verifications (
        candidate_id,
        signed_offer_status,
        signed_offer_submitted_at,
        created_at,
        updated_at
    ) values (
        v_candidate_id,
        'SIGNED_OFFER_SUBMITTED',
        v_now,
        v_now,
        v_now
    )
    returning verification_id into v_verification_id;

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
        v_verification_id,
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
    returning file_id into v_file_id;

    update public.hr_lifecycle
    set lifecycle_status = 'SIGNED_OFFER_SUBMITTED',
        updated_at = v_now
    where lifecycle_id = v_lifecycle.lifecycle_id
      and lifecycle_status = 'ACTIVE';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status changed during submission.';
    end if;

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
        'ACTIVE',
        'SIGNED_OFFER_SUBMITTED',
        'Signed offer PDF submitted securely by candidate',
        'SUCCESS',
        v_app_user_id::text,
        v_now,
        v_now,
        v_now
    );

    return jsonb_build_object(
        'fileId', v_file_id,
        'candidateId', v_candidate_id,
        'verificationId', v_verification_id,
        'objectPath', v_object_path,
        'signedOfferStatus', 'SIGNED_OFFER_SUBMITTED',
        'lifecycleStatus', 'SIGNED_OFFER_SUBMITTED',
        'submittedAt', v_now
    );
end;
$function$;

comment on function public.finalize_current_candidate_signed_offer(text, text) is
    'Atomically finalizes one private signed-offer PDF for the current active candidate, records its metadata, updates the signed-offer and lifecycle states, and writes the activity log.';

revoke execute on function public.finalize_current_candidate_signed_offer(text, text) from public;
revoke execute on function public.finalize_current_candidate_signed_offer(text, text) from anon;
grant execute on function public.finalize_current_candidate_signed_offer(text, text) to authenticated;
grant execute on function public.finalize_current_candidate_signed_offer(text, text) to service_role;
