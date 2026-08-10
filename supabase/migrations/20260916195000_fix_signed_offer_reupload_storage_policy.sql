begin;

-- Fix: Allow authenticated candidates to upload a replacement signed-offer PDF
-- when their lifecycle is in MISMATCH_REVIEW (HR rejected the previous file).
--
-- The original function current_candidate_signed_offer_upload_allowed() only
-- permitted uploads when lifecycle_status = 'ACTIVE' and no existing file/
-- verification in SUBMITTED/VERIFIED/MISMATCH_REVIEW existed, which permanently
-- blocked the re-upload path.
--
-- This migration replaces the function so it returns true in exactly two cases:
--   1. First-time upload: lifecycle = 'ACTIVE' AND no active file/verification.
--   2. Re-upload after rejection: lifecycle = 'MISMATCH_REVIEW' AND exactly one
--      file/verification in MISMATCH_REVIEW exists (no SUBMITTED/VERIFIED files).
--
-- All other security checks are preserved unchanged:
--   - authenticated active CANDIDATE session only
--   - candidate_id resolved server-side via current_candidate_id()
--   - path must still be  candidate/{candidate_id}/signed-offers/{uuid}.pdf
--   - still enforced by the INSERT policy on storage.objects

create or replace function public.current_candidate_signed_offer_upload_allowed()
returns boolean
language sql
stable
security definer
set search_path = public, auth, storage, pg_temp
as $function$
    with current_candidate as (
        select public.current_candidate_id() as candidate_id
    )
    select public.current_user_is_active() is true
       and public.current_user_has_role('CANDIDATE') is true
       and current_candidate.candidate_id is not null
       and (
           -- ── Case 1: First-time submission ────────────────────────────────
           -- Lifecycle must be exactly ACTIVE, no active file, no active
           -- verification, no existing storage objects in the candidate path.
           (
               (
                   select count(*) = 1
                      and bool_and(l.lifecycle_status = 'ACTIVE')
                   from public.hr_lifecycle l
                   where l.candidate_id = current_candidate.candidate_id
               )
               and not exists (
                   select 1
                   from public.candidate_signed_offer_files f
                   where f.candidate_id = current_candidate.candidate_id
                     and f.file_status in ('SUBMITTED', 'VERIFIED', 'MISMATCH_REVIEW')
               )
               and not exists (
                   select 1
                   from public.signed_offer_verifications sov
                   where sov.candidate_id = current_candidate.candidate_id
                     and (
                         sov.signed_offer_submitted_at is not null
                         or sov.signed_offer_status in (
                             'SIGNED_OFFER_SUBMITTED',
                             'SIGNED_OFFER_VERIFIED',
                             'MISMATCH_REVIEW'
                         )
                     )
               )
               and not exists (
                   select 1
                   from storage.objects o
                   where o.bucket_id = 'candidate-signed-offers'
                     and pg_catalog.left(
                             o.name,
                             pg_catalog.length(
                                 'candidate/' || current_candidate.candidate_id::text || '/signed-offers/'
                             )
                         ) = 'candidate/' || current_candidate.candidate_id::text || '/signed-offers/'
               )
           )

           or

           -- ── Case 2: Re-upload after MISMATCH_REVIEW ──────────────────────
           -- Lifecycle must be exactly MISMATCH_REVIEW, there must be exactly
           -- one file in MISMATCH_REVIEW state (the rejected one being replaced),
           -- and the verification record must also be in MISMATCH_REVIEW.
           -- No SUBMITTED or VERIFIED files may exist for this candidate.
           (
               (
                   select count(*) = 1
                      and bool_and(l.lifecycle_status = 'MISMATCH_REVIEW')
                   from public.hr_lifecycle l
                   where l.candidate_id = current_candidate.candidate_id
               )
               and exists (
                   select 1
                   from public.candidate_signed_offer_files f
                   where f.candidate_id = current_candidate.candidate_id
                     and f.file_status = 'MISMATCH_REVIEW'
               )
               and not exists (
                   select 1
                   from public.candidate_signed_offer_files f
                   where f.candidate_id = current_candidate.candidate_id
                     and f.file_status in ('SUBMITTED', 'VERIFIED')
               )
               and exists (
                   select 1
                   from public.signed_offer_verifications sov
                   where sov.candidate_id = current_candidate.candidate_id
                     and sov.signed_offer_status = 'MISMATCH_REVIEW'
               )
           )
       )
    from current_candidate;
$function$;

comment on function public.current_candidate_signed_offer_upload_allowed() is
    'Internal Storage policy helper: returns true for an active authenticated CANDIDATE when either (1) lifecycle is ACTIVE and no prior file/verification exists (first-time upload) or (2) lifecycle is MISMATCH_REVIEW and a rejected file exists to be replaced (re-upload). All other states are denied.';

-- Grants are unchanged from the original migration.
revoke execute on function public.current_candidate_signed_offer_upload_allowed() from public;
revoke execute on function public.current_candidate_signed_offer_upload_allowed() from anon;
grant execute on function public.current_candidate_signed_offer_upload_allowed() to authenticated;
grant execute on function public.current_candidate_signed_offer_upload_allowed() to service_role;

-- The INSERT policy on storage.objects references this function by name and
-- requires no changes — it continues to call
-- current_candidate_signed_offer_upload_allowed() as before.

commit;
