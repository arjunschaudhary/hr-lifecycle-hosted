begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'candidate-issued-documents',
    'candidate-issued-documents',
    false,
    10485760,
    array['application/pdf']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Issuance is service-role worker owned. No authenticated browser role can
-- enumerate or upload documents in this bucket. This intentionally does not
-- change global Storage privileges or policies for existing buckets.

commit;
