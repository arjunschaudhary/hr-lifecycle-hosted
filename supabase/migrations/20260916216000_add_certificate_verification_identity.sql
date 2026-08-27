begin;

alter table public.exit_documents
    add column if not exists certificate_id text,
    add column if not exists certificate_verification_url text,
    add column if not exists gmail_message_id text,
    add column if not exists emailed_at timestamptz,
    add column if not exists revoked_at timestamptz,
    add column if not exists revocation_reason text;

alter table public.exit_documents
    add constraint exit_documents_certificate_id_format_check
        check (
            certificate_id is null
            or certificate_id ~ '^CERT-[A-Za-z0-9]+$'
        ),
    add constraint exit_documents_certificate_identity_scope_check
        check (
            (document_variant in ('INTERN_CERTIFICATE', 'VOLUNTEER_CERTIFICATE', 'POD_LEAD_CERTIFICATE'))
            or (
                certificate_id is null
                and certificate_verification_url is null
                and revoked_at is null
                and revocation_reason is null
            )
        );

create unique index if not exists uq_exit_documents_certificate_id
    on public.exit_documents (certificate_id)
    where certificate_id is not null;

comment on column public.exit_documents.certificate_id is
    'Cryptographically secure certificate identity in CERT-alphanumeric format. Never used for LORs.';
comment on column public.exit_documents.certificate_verification_url is
    'Populated only after the verification portal publishes a supported URL contract. Never used for LORs.';

commit;
