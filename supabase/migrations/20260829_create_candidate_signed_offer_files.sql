create table public.candidate_signed_offer_files (
    file_id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null,
    verification_id uuid null,
    bucket_id text not null default 'candidate-signed-offers',
    object_path text not null,
    original_filename text not null,
    mime_type text not null,
    file_size_bytes bigint not null,
    file_status text not null,
    uploaded_by uuid not null,
    uploaded_at timestamptz not null default now(),
    submitted_at timestamptz null,
    verified_at timestamptz null,
    replaced_at timestamptz null,
    replaced_by_file_id uuid null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint candidate_signed_offer_files_candidate_fk
        foreign key (candidate_id)
        references public.master_candidates(candidate_id)
        on delete cascade,
    constraint candidate_signed_offer_files_verification_fk
        foreign key (verification_id)
        references public.signed_offer_verifications(verification_id)
        on delete set null,
    constraint candidate_signed_offer_files_uploaded_by_fk
        foreign key (uploaded_by)
        references public.users(id)
        on delete restrict,
    constraint candidate_signed_offer_files_replaced_by_fk
        foreign key (replaced_by_file_id)
        references public.candidate_signed_offer_files(file_id)
        on delete set null,
    constraint candidate_signed_offer_files_bucket_check
        check (bucket_id = 'candidate-signed-offers'),
    constraint candidate_signed_offer_files_object_path_check
        check (btrim(object_path) <> ''),
    constraint candidate_signed_offer_files_original_filename_check
        check (btrim(original_filename) <> ''),
    constraint candidate_signed_offer_files_mime_type_check
        check (mime_type = 'application/pdf'),
    constraint candidate_signed_offer_files_size_check
        check (file_size_bytes > 0 and file_size_bytes <= 10485760),
    constraint candidate_signed_offer_files_status_check
        check (file_status in ('SUBMITTED', 'VERIFIED', 'MISMATCH_REVIEW', 'REPLACED')),
    constraint candidate_signed_offer_files_verified_at_check
        check (
            (file_status = 'VERIFIED' and verified_at is not null)
            or (file_status <> 'VERIFIED' and verified_at is null)
        ),
    constraint candidate_signed_offer_files_replaced_at_check
        check (
            (file_status = 'REPLACED' and replaced_at is not null)
            or (file_status <> 'REPLACED' and replaced_at is null)
        )
);

comment on table public.candidate_signed_offer_files is
    'Private Storage object metadata and immutable signed-offer file history for candidates.';

comment on column public.candidate_signed_offer_files.object_path is
    'Private Storage object path; public URLs are intentionally not stored.';

create unique index candidate_signed_offer_files_object_path_uidx
    on public.candidate_signed_offer_files(object_path);

create index candidate_signed_offer_files_candidate_idx
    on public.candidate_signed_offer_files(candidate_id);

create index candidate_signed_offer_files_verification_idx
    on public.candidate_signed_offer_files(verification_id);

create index candidate_signed_offer_files_status_idx
    on public.candidate_signed_offer_files(file_status);

create unique index candidate_signed_offer_files_one_current_candidate_uidx
    on public.candidate_signed_offer_files(candidate_id)
    where file_status in ('SUBMITTED', 'VERIFIED', 'MISMATCH_REVIEW');

alter table public.candidate_signed_offer_files enable row level security;

revoke all privileges on table public.candidate_signed_offer_files from anon;
revoke all privileges on table public.candidate_signed_offer_files from authenticated;
grant select on table public.candidate_signed_offer_files to authenticated;

drop policy if exists candidate_signed_offer_files_candidate_select
    on public.candidate_signed_offer_files;
drop policy if exists candidate_signed_offer_files_staff_select
    on public.candidate_signed_offer_files;

create policy candidate_signed_offer_files_candidate_select
on public.candidate_signed_offer_files
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_role('CANDIDATE')
    and candidate_id = public.current_candidate_id()
);

create policy candidate_signed_offer_files_staff_select
on public.candidate_signed_offer_files
for select
to authenticated
using (
    public.current_user_is_active()
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
