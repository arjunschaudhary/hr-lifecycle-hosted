insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
) values (
    'candidate-signed-offers',
    'candidate-signed-offers',
    false,
    10485760,
    array['application/pdf']::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['application/pdf']::text[];

-- Storage policies need a security-definer lifecycle check because the underlying
-- lifecycle and verification tables are protected from direct candidate SELECTs.
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
    from current_candidate;
$function$;

comment on function public.current_candidate_signed_offer_upload_allowed() is
    'Internal Storage policy helper allowing a current candidate upload only while exactly one ACTIVE lifecycle row exists and no submitted signed-offer state or current file exists.';

revoke execute on function public.current_candidate_signed_offer_upload_allowed() from public;
revoke execute on function public.current_candidate_signed_offer_upload_allowed() from anon;
grant execute on function public.current_candidate_signed_offer_upload_allowed() to authenticated;
grant execute on function public.current_candidate_signed_offer_upload_allowed() to service_role;

drop policy if exists candidate_signed_offer_objects_candidate_insert
    on storage.objects;
drop policy if exists candidate_signed_offer_objects_candidate_select
    on storage.objects;
drop policy if exists candidate_signed_offer_objects_candidate_delete_orphan
    on storage.objects;
drop policy if exists candidate_signed_offer_objects_staff_select
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

create policy candidate_signed_offer_objects_candidate_select
on storage.objects
for select
to authenticated
using (
    bucket_id = 'candidate-signed-offers'
    and public.current_user_is_active() is true
    and public.current_user_has_role('CANDIDATE') is true
    and public.current_candidate_id() is not null
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and (storage.foldername(name))[3] = 'signed-offers'
);

create policy candidate_signed_offer_objects_candidate_delete_orphan
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'candidate-signed-offers'
    and public.current_user_is_active() is true
    and public.current_user_has_role('CANDIDATE') is true
    and public.current_candidate_id() is not null
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and (storage.foldername(name))[3] = 'signed-offers'
    and owner_id = auth.uid()::text
    and not exists (
        select 1
        from public.candidate_signed_offer_files f
        where f.object_path = storage.objects.name
    )
);

create policy candidate_signed_offer_objects_staff_select
on storage.objects
for select
to authenticated
using (
    bucket_id = 'candidate-signed-offers'
    and public.current_user_is_active()
    and public.current_user_has_any_role(
        array[
            'HR_SITE_CONNECT',
            'HR_SITE_CONNECT_LEAD',
            'HR_EXECUTIVE',
            'HR_EXECUTIVE_LEAD',
            'HR_LEAD',
            'FOUNDERS_OFFICE',
            'ADMIN'
        ]::text[]
    )
);
