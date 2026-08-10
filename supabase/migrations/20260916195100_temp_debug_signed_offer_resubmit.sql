begin;

-- Temporary diagnostic RPC for debugging signed-offer upload eligibility.
-- Called from the authenticated candidate browser session only.
-- Returns the exact result of every sub-condition inside
-- current_candidate_signed_offer_upload_allowed() so the failing guard
-- can be identified precisely without weakening or bypassing RLS.
--
-- This function is intentionally read-only (stable) and exposes no
-- candidate data beyond what is needed for the debug session.
-- It should be removed once the root cause is confirmed and fixed.

create or replace function public.debug_signed_offer_resubmit_eligibility()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, storage, pg_temp
as $function$
declare
    v_candidate_id              uuid;
    v_user_is_active            boolean;
    v_is_candidate              boolean;
    v_lifecycle_status          text;
    v_lifecycle_count           int;
    v_lifecycle_is_active       boolean;
    v_lifecycle_is_mismatch     boolean;
    v_file_mismatch_exists      boolean;
    v_file_submitted_verified   boolean;
    v_sov_status                text;
    v_sov_mismatch_exists       boolean;
    v_storage_objects_exist     boolean;
    v_upload_allowed            boolean;
    -- Case 1 parts
    v_c1_lifecycle_ok           boolean;
    v_c1_no_active_file         boolean;
    v_c1_no_active_sov          boolean;
    v_c1_no_storage_objects     boolean;
    -- Case 2 parts
    v_c2_lifecycle_ok           boolean;
    v_c2_mismatch_file_exists   boolean;
    v_c2_no_submitted_verified  boolean;
    v_c2_mismatch_sov_exists    boolean;
begin
    v_user_is_active := coalesce(public.current_user_is_active(), false);
    v_is_candidate   := coalesce(public.current_user_has_role('CANDIDATE'), false);
    v_candidate_id   := public.current_candidate_id();

    -- Lifecycle
    select count(*)::int,
           bool_and(l.lifecycle_status = 'ACTIVE'),
           bool_and(l.lifecycle_status = 'MISMATCH_REVIEW'),
           max(l.lifecycle_status)
    into   v_lifecycle_count,
           v_lifecycle_is_active,
           v_lifecycle_is_mismatch,
           v_lifecycle_status
    from   public.hr_lifecycle l
    where  l.candidate_id = v_candidate_id;

    -- File statuses
    select exists(
        select 1 from public.candidate_signed_offer_files f
        where  f.candidate_id = v_candidate_id
          and  f.file_status = 'MISMATCH_REVIEW'
    ) into v_file_mismatch_exists;

    select exists(
        select 1 from public.candidate_signed_offer_files f
        where  f.candidate_id = v_candidate_id
          and  f.file_status in ('SUBMITTED', 'VERIFIED')
    ) into v_file_submitted_verified;

    -- Verification status
    select exists(
        select 1 from public.signed_offer_verifications sov
        where  sov.candidate_id = v_candidate_id
          and  sov.signed_offer_status = 'MISMATCH_REVIEW'
    ) into v_sov_mismatch_exists;

    select max(sov.signed_offer_status)
    into   v_sov_status
    from   public.signed_offer_verifications sov
    where  sov.candidate_id = v_candidate_id;

    -- Storage objects in candidate path
    select exists(
        select 1 from storage.objects o
        where  o.bucket_id = 'candidate-signed-offers'
          and  pg_catalog.left(
                   o.name,
                   pg_catalog.length(
                       'candidate/' || v_candidate_id::text || '/signed-offers/'
                   )
               ) = 'candidate/' || v_candidate_id::text || '/signed-offers/'
    ) into v_storage_objects_exist;

    -- Case 1 sub-conditions
    v_c1_lifecycle_ok        := coalesce(v_lifecycle_count = 1 and v_lifecycle_is_active, false);
    v_c1_no_active_file      := not coalesce(
        exists(
            select 1 from public.candidate_signed_offer_files f
            where  f.candidate_id = v_candidate_id
              and  f.file_status in ('SUBMITTED', 'VERIFIED', 'MISMATCH_REVIEW')
        ), false);
    v_c1_no_active_sov       := not coalesce(
        exists(
            select 1 from public.signed_offer_verifications sov
            where  sov.candidate_id = v_candidate_id
              and (sov.signed_offer_submitted_at is not null
                   or sov.signed_offer_status in ('SIGNED_OFFER_SUBMITTED','SIGNED_OFFER_VERIFIED','MISMATCH_REVIEW'))
        ), false);
    v_c1_no_storage_objects  := not coalesce(v_storage_objects_exist, false);

    -- Case 2 sub-conditions
    v_c2_lifecycle_ok         := coalesce(v_lifecycle_count = 1 and v_lifecycle_is_mismatch, false);
    v_c2_mismatch_file_exists := coalesce(v_file_mismatch_exists, false);
    v_c2_no_submitted_verified:= not coalesce(v_file_submitted_verified, false);
    v_c2_mismatch_sov_exists  := coalesce(v_sov_mismatch_exists, false);

    -- Final upload_allowed result (mirrors the policy helper exactly)
    v_upload_allowed := coalesce(public.current_candidate_signed_offer_upload_allowed(), false);

    return jsonb_build_object(
        -- Session
        'sessionUserId',         auth.uid(),
        'candidateId',           v_candidate_id,
        'userIsActive',          v_user_is_active,
        'isCandidate',           v_is_candidate,

        -- Lifecycle
        'lifecycleCount',        v_lifecycle_count,
        'lifecycleStatus',       v_lifecycle_status,
        'lifecycleIsActive',     v_lifecycle_is_active,
        'lifecycleIsMismatch',   v_lifecycle_is_mismatch,

        -- Files
        'fileMismatchExists',    v_file_mismatch_exists,
        'fileSubmittedOrVerifiedExists', v_file_submitted_verified,

        -- Verifications
        'sovStatus',             v_sov_status,
        'sovMismatchExists',     v_sov_mismatch_exists,

        -- Storage
        'storageObjectsExist',   v_storage_objects_exist,

        -- Case 1 breakdown
        'case1',  jsonb_build_object(
            'lifecycleOk',       v_c1_lifecycle_ok,
            'noActiveFile',      v_c1_no_active_file,
            'noActiveSov',       v_c1_no_active_sov,
            'noStorageObjects',  v_c1_no_storage_objects,
            'passes',            v_c1_lifecycle_ok and v_c1_no_active_file and v_c1_no_active_sov and v_c1_no_storage_objects
        ),

        -- Case 2 breakdown
        'case2', jsonb_build_object(
            'lifecycleOk',           v_c2_lifecycle_ok,
            'mismatchFileExists',    v_c2_mismatch_file_exists,
            'noSubmittedOrVerified', v_c2_no_submitted_verified,
            'mismatchSovExists',     v_c2_mismatch_sov_exists,
            'passes',                v_c2_lifecycle_ok and v_c2_mismatch_file_exists and v_c2_no_submitted_verified and v_c2_mismatch_sov_exists
        ),

        -- Final result from the real policy helper
        'uploadAllowed',         v_upload_allowed
    );
end;
$function$;

comment on function public.debug_signed_offer_resubmit_eligibility() is
    'TEMPORARY diagnostic: returns each sub-condition of current_candidate_signed_offer_upload_allowed() from the callers authenticated session. Remove after root cause is confirmed.';

revoke execute on function public.debug_signed_offer_resubmit_eligibility() from public;
revoke execute on function public.debug_signed_offer_resubmit_eligibility() from anon;
grant execute on function public.debug_signed_offer_resubmit_eligibility() to authenticated;
grant execute on function public.debug_signed_offer_resubmit_eligibility() to service_role;

commit;
