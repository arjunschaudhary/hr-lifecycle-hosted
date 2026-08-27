begin;

create or replace function public.current_candidate_can_read_issued_document(
    p_bucket_id text,
    p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
    with current_candidate as (
        select public.current_candidate_id() as candidate_id
    )
    select current_candidate.candidate_id is not null
       and exists (
           select 1
           from public.exit_documents ed
           join public.exit_cases ec
             on ec.exit_case_id = ed.exit_case_id
           where ed.bucket_id = p_bucket_id
             and ed.storage_path = p_storage_path
             and ed.revoked_at is null
             and ec.candidate_id = current_candidate.candidate_id
       )
    from current_candidate;
$function$;

comment on function public.current_candidate_can_read_issued_document(text, text) is
    'Internal Storage policy helper that permits an active candidate to read only their own non-revoked issued-document object.';

revoke all on function public.current_candidate_can_read_issued_document(text, text) from public;
revoke all on function public.current_candidate_can_read_issued_document(text, text) from anon;
grant execute on function public.current_candidate_can_read_issued_document(text, text) to authenticated;

drop policy if exists candidate_issued_documents_candidate_select
    on storage.objects;

create policy candidate_issued_documents_candidate_select
on storage.objects
for select
to authenticated
using (
    bucket_id = 'candidate-issued-documents'
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and public.current_candidate_can_read_issued_document(bucket_id, name)
);

commit;
