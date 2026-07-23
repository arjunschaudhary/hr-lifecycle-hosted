create or replace function public.review_candidate_signed_offer(
    p_verification_id uuid,
    p_target_status text,
    p_verification_notes text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, storage, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_verification public.signed_offer_verifications%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_file public.candidate_signed_offer_files%rowtype;
    v_target_status text;
    v_verification_notes text;
    v_email_match_status text;
    v_phone_match_status text;
    v_file_status text;
    v_storage_object_count bigint;
    v_reviewed_at timestamptz := pg_catalog.now();
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
           array[
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'FOUNDERS_OFFICE',
               'ADMIN'
           ]::text[]
       ) is not true then
        raise insufficient_privilege
            using message = 'Signed-offer verification access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null then
        raise insufficient_privilege
            using message = 'Signed-offer verification access is not available.';
    end if;

    if p_verification_id is null then
        raise exception using
            errcode = '22023',
            message = 'Signed-offer verification ID is required.';
    end if;

    v_target_status := pg_catalog.upper(pg_catalog.btrim(coalesce(p_target_status, '')));

    if v_target_status not in ('SIGNED_OFFER_VERIFIED', 'MISMATCH_REVIEW') then
        raise exception using
            errcode = '22023',
            message = 'Signed-offer review decision is invalid.';
    end if;

    v_verification_notes := pg_catalog.btrim(coalesce(p_verification_notes, ''));

    if pg_catalog.length(v_verification_notes) > 2000 then
        raise exception using
            errcode = '22023',
            message = 'Signed-offer verification notes are too long.';
    end if;

    if v_target_status = 'MISMATCH_REVIEW'
       and v_verification_notes = '' then
        raise exception using
            errcode = '22023',
            message = 'Mismatch review notes are required.';
    end if;

    if v_target_status = 'SIGNED_OFFER_VERIFIED'
       and v_verification_notes = '' then
        v_verification_notes := 'Signed offer verified by HR.';
    end if;

    begin
        select sov.*
        into strict v_verification
        from public.signed_offer_verifications sov
        where sov.verification_id = p_verification_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Signed-offer verification record is not available.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Signed-offer verification record is ambiguous.';
    end;

    if v_verification.signed_offer_status is distinct from 'SIGNED_OFFER_SUBMITTED' then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer verification is no longer pending.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'candidate-signed-offer-review:' || v_verification.candidate_id::text,
            0::bigint
        )
    );

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_verification.candidate_id
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

    if v_lifecycle.lifecycle_status is distinct from 'SIGNED_OFFER_SUBMITTED' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate signed-offer status is stale.';
    end if;

    begin
        select f.*
        into strict v_file
        from public.candidate_signed_offer_files f
        where f.candidate_id = v_verification.candidate_id
          and f.verification_id = v_verification.verification_id
          and f.file_status = 'SUBMITTED'
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'No submitted signed-offer file matches this verification.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Multiple submitted signed-offer files match this verification.';
    end;

    if v_file.bucket_id is distinct from 'candidate-signed-offers' then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer file storage is invalid.';
    end if;

    select count(*)
    into v_storage_object_count
    from storage.objects o
    where o.bucket_id = 'candidate-signed-offers'
      and o.name = v_file.object_path;

    if v_storage_object_count = 0 then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer Storage object is not available.';
    end if;

    if v_storage_object_count > 1 then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer Storage object is ambiguous.';
    end if;

    if v_target_status = 'SIGNED_OFFER_VERIFIED' then
        v_email_match_status := 'MATCH';
        v_phone_match_status := 'MATCH';
        v_file_status := 'VERIFIED';
    else
        v_email_match_status := 'MISMATCH';
        v_phone_match_status := 'MISMATCH';
        v_file_status := 'MISMATCH_REVIEW';
    end if;

    update public.signed_offer_verifications
    set signed_offer_status = v_target_status,
        verified_at = case
            when v_target_status = 'SIGNED_OFFER_VERIFIED' then v_reviewed_at
            else null
        end,
        email_match_status = v_email_match_status,
        phone_match_status = v_phone_match_status,
        verification_notes = v_verification_notes,
        updated_at = v_reviewed_at
    where verification_id = v_verification.verification_id
      and signed_offer_status = 'SIGNED_OFFER_SUBMITTED';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer verification changed during review.';
    end if;

    update public.candidate_signed_offer_files
    set file_status = v_file_status,
        verified_at = case
            when v_target_status = 'SIGNED_OFFER_VERIFIED' then v_reviewed_at
            else null
        end,
        updated_at = v_reviewed_at
    where file_id = v_file.file_id
      and candidate_id = v_verification.candidate_id
      and verification_id = v_verification.verification_id
      and file_status = 'SUBMITTED';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Signed-offer file changed during review.';
    end if;

    update public.hr_lifecycle
    set lifecycle_status = v_target_status,
        updated_at = v_reviewed_at
    where lifecycle_id = v_lifecycle.lifecycle_id
      and candidate_id = v_verification.candidate_id
      and lifecycle_status = 'SIGNED_OFFER_SUBMITTED';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle changed during review.';
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
        v_verification.candidate_id,
        v_target_status,
        'SIGNED_OFFER_SUBMITTED',
        v_target_status,
        case
            when v_target_status = 'SIGNED_OFFER_VERIFIED'
                then 'Signed offer PDF verified securely by HR'
            else 'Signed offer PDF moved to mismatch review by HR'
        end,
        'SUCCESS',
        v_actor_user_id::text,
        v_reviewed_at,
        v_reviewed_at,
        v_reviewed_at
    );

    return jsonb_build_object(
        'verificationId', v_verification.verification_id,
        'candidateId', v_verification.candidate_id,
        'fileId', v_file.file_id,
        'signedOfferStatus', v_target_status,
        'lifecycleStatus', v_target_status,
        'fileStatus', v_file_status,
        'reviewedAt', v_reviewed_at
    );
end;
$function$;

comment on function public.review_candidate_signed_offer(uuid, text, text) is
    'Atomically verifies or moves one submitted private signed-offer file to mismatch review after locking and validating its verification, candidate lifecycle, Storage object, and audit record.';

revoke execute on function public.review_candidate_signed_offer(uuid, text, text) from public;
revoke execute on function public.review_candidate_signed_offer(uuid, text, text) from anon;
grant execute on function public.review_candidate_signed_offer(uuid, text, text) to authenticated;
grant execute on function public.review_candidate_signed_offer(uuid, text, text) to service_role;
