begin;

-- Fix: Force recompilation of the candidate_signed_offer_objects_candidate_insert
-- Storage policy on storage.objects.
--
-- Context:
--   Migration 195000 updated current_candidate_signed_offer_upload_allowed() to
--   return true when lifecycle = MISMATCH_REVIEW (re-upload flow). The diagnostic
--   RPC confirmed uploadAllowed = true from the candidate's authenticated session.
--   However, the Storage INSERT into storage.objects still returns 403.
--
-- Root cause:
--   PostgreSQL (and Supabase's PgBouncer pool) may cache the compiled query plan
--   for RLS policy WITH CHECK expressions. When CREATE OR REPLACE FUNCTION replaces
--   the helper function body, the old compiled plan for the INSERT policy may still
--   hold a reference to the previous (ACTIVE-only) evaluation path.
--
-- Fix:
--   Dropping and recreating the INSERT policy forces PostgreSQL to discard any
--   cached plan and recompile the WITH CHECK expression using the current version
--   of current_candidate_signed_offer_upload_allowed(). The policy content is
--   identical to the original in 20260830_secure_candidate_signed_offer_storage.sql.

drop policy if exists candidate_signed_offer_objects_candidate_insert
    on storage.objects;

create policy candidate_signed_offer_objects_candidate_insert
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'candidate-signed-offers'
    and public.current_user_is_active() is true
    and public.current_user_has_role('CANDIDATE') is true
    and public.current_candidate_id() is not null
    and public.current_candidate_signed_offer_upload_allowed() is true
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and (storage.foldername(name))[3] = 'signed-offers'
    and storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.pdf$'
);

commit;
