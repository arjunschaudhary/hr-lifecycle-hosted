create or replace function public.get_signed_offer_review_queue()
returns table (
    verification_id uuid,
    candidate_id uuid,
    full_name text,
    email text,
    phone text,
    applied_role text,
    mid text,
    lifecycle_status text,
    signed_offer_status text,
    signed_offer_submitted_at timestamptz,
    verified_at timestamptz,
    email_match_status text,
    phone_match_status text,
    verification_notes text,
    file_id uuid,
    object_path text,
    original_filename text,
    mime_type text,
    file_size_bytes bigint,
    file_status text,
    uploaded_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, storage, pg_temp
as $function$
begin
    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
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
        raise insufficient_privilege
            using message = 'Signed-offer review access is not available.';
    end if;

    return query
    select
        sov.verification_id,
        sov.candidate_id,
        c.full_name::text,
        c.email::text,
        c.phone::text,
        c.applied_role::text,
        l.mid::text,
        l.lifecycle_status::text,
        sov.signed_offer_status::text,
        sov.signed_offer_submitted_at,
        sov.verified_at,
        sov.email_match_status::text,
        sov.phone_match_status::text,
        sov.verification_notes,
        f.file_id,
        f.object_path,
        f.original_filename,
        f.mime_type,
        f.file_size_bytes,
        f.file_status,
        f.uploaded_at
    from public.signed_offer_verifications sov
    join public.master_candidates c
      on c.candidate_id = sov.candidate_id
    join public.hr_lifecycle l
      on l.candidate_id = sov.candidate_id
    left join lateral (
        select
            files.file_id,
            files.object_path,
            files.original_filename,
            files.mime_type,
            files.file_size_bytes,
            files.file_status,
            files.uploaded_at
        from public.candidate_signed_offer_files files
        where files.verification_id = sov.verification_id
          and files.candidate_id = sov.candidate_id
        order by files.created_at desc, files.file_id desc
        limit 1
    ) f on true
    order by
        coalesce(
            sov.verified_at,
            sov.updated_at,
            sov.signed_offer_submitted_at,
            sov.created_at
        ) desc nulls last,
        sov.verification_id desc;
end;
$function$;

comment on function public.get_signed_offer_review_queue() is
    'Returns a safe authenticated HR signed-offer review queue with candidate, verification, and matching private-file metadata without exposing Storage metadata or public URLs.';

revoke execute on function public.get_signed_offer_review_queue() from public;
revoke execute on function public.get_signed_offer_review_queue() from anon;
grant execute on function public.get_signed_offer_review_queue() to authenticated;
grant execute on function public.get_signed_offer_review_queue() to service_role;
