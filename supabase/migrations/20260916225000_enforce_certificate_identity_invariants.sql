begin;

-- Certificate identifiers are public verification keys. Normalize the
-- collision domain before enforcing case-insensitive uniqueness, and fail
-- closed if legacy data cannot be normalized without manual reconciliation.
do $block$
begin
    if exists (
        select 1
        from public.exit_documents ed
        where ed.document_variant in (
            'INTERN_CERTIFICATE',
            'VOLUNTEER_CERTIFICATE',
            'POD_LEAD_CERTIFICATE'
        )
          and (ed.certificate_id is null or btrim(ed.certificate_id) = '')
    ) then
        raise exception using
            errcode = '23514',
            message = 'Existing certificate documents require certificate identity reconciliation.';
    end if;

    if exists (
        select 1
        from public.exit_documents ed
        where (
            ed.document_variant is null
            or ed.document_variant not in (
                'INTERN_CERTIFICATE',
                'VOLUNTEER_CERTIFICATE',
                'POD_LEAD_CERTIFICATE'
            )
        )
          and ed.certificate_id is not null
    ) then
        raise exception using
            errcode = '23514',
            message = 'Non-certificate documents contain certificate identities.';
    end if;

    if exists (
        select 1
        from public.exit_documents ed
        where ed.certificate_id is not null
          and upper(btrim(ed.certificate_id)) !~ '^CERT-[A-Z0-9]+$'
    ) then
        raise exception using
            errcode = '23514',
            message = 'Existing certificate identifiers do not match the canonical format.';
    end if;

    if exists (
        select 1
        from public.exit_documents ed
        where ed.certificate_id is not null
        group by upper(btrim(ed.certificate_id))
        having count(*) > 1
    ) then
        raise exception using
            errcode = '23505',
            message = 'Case-insensitive duplicate certificate identifiers require manual reconciliation.';
    end if;
end;
$block$;

update public.exit_documents
set certificate_id = upper(btrim(certificate_id))
where certificate_id is not null
  and certificate_id is distinct from upper(btrim(certificate_id));

alter table public.exit_documents
    drop constraint if exists exit_documents_certificate_id_format_check,
    drop constraint if exists exit_documents_certificate_identity_scope_check;

alter table public.exit_documents
    add constraint exit_documents_certificate_id_format_check
        check (
            certificate_id is null
            or (
                certificate_id = upper(btrim(certificate_id))
                and certificate_id ~ '^CERT-[A-Z0-9]+$'
            )
        ),
    add constraint exit_documents_certificate_identity_scope_check
        check (
            (
                document_variant in (
                    'INTERN_CERTIFICATE',
                    'VOLUNTEER_CERTIFICATE',
                    'POD_LEAD_CERTIFICATE'
                )
                and certificate_id is not null
            )
            or (
                coalesce(
                    document_variant not in (
                        'INTERN_CERTIFICATE',
                        'VOLUNTEER_CERTIFICATE',
                        'POD_LEAD_CERTIFICATE'
                    ),
                    true
                )
                and certificate_id is null
                and certificate_verification_url is null
                and revoked_at is null
                and revocation_reason is null
            )
        );

drop index if exists public.uq_exit_documents_certificate_id;

create unique index uq_exit_documents_certificate_id
    on public.exit_documents ((upper(certificate_id)))
    where certificate_id is not null;

create or replace function public.complete_exit_document_generation(
    p_job_id uuid,
    p_document_id uuid,
    p_storage_path text,
    p_bucket_id text,
    p_template_key text,
    p_template_version text,
    p_certificate_id text default null,
    p_certificate_verification_url text default null
)
returns table (document_id uuid, candidate_id uuid, candidate_email text, document_variant text)
language plpgsql security definer set search_path = public, auth, pg_temp
as $function$
#variable_conflict use_column
declare
    v_job public.automation_jobs%rowtype;
    v_request public.exit_document_requests%rowtype;
    v_case public.exit_cases%rowtype;
    v_document public.exit_documents%rowtype;
    v_existing_document public.exit_documents%rowtype;
    v_certificate_id text;
    v_is_certificate_variant boolean;
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using errcode = '42501', message = 'Service-role worker access is required.';
    end if;

    select *
    into v_job
    from public.automation_jobs
    where job_id = p_job_id
    for update;

    if v_job.job_type <> 'EXIT_DOCUMENT' or v_job.job_status <> 'PROCESSING' then
        raise exception using errcode = 'P0001', message = 'Exit-document job is not being processed.';
    end if;

    select *
    into v_request
    from public.exit_document_requests
    where job_id = p_job_id
    for update;

    select *
    into v_case
    from public.exit_cases
    where exit_case_id = v_request.exit_case_id;

    if p_bucket_id <> 'candidate-issued-documents'
       or p_storage_path not like format(
           'candidate/%s/exit/%s/%s/%%.pdf',
           v_case.candidate_id,
           v_case.exit_case_id,
           v_request.document_variant
       ) then
        raise exception using errcode = '22023', message = 'Issued-document storage path is invalid.';
    end if;

    v_is_certificate_variant := v_request.document_variant in (
        'INTERN_CERTIFICATE',
        'VOLUNTEER_CERTIFICATE',
        'POD_LEAD_CERTIFICATE'
    );

    if v_is_certificate_variant then
        v_certificate_id := upper(btrim(p_certificate_id));

        if v_certificate_id is null or v_certificate_id = '' then
            raise exception using errcode = '22023', message = 'Certificate identity is required.';
        end if;

        if v_certificate_id !~ '^CERT-[A-Z0-9]+$' then
            raise exception using errcode = '22023', message = 'Certificate identity is invalid.';
        end if;
    else
        if p_certificate_id is not null or p_certificate_verification_url is not null then
            raise exception using errcode = '22023', message = 'Certificate identity is not allowed for this document variant.';
        end if;

        v_certificate_id := null;
    end if;

    select ed.*
    into v_existing_document
    from public.exit_documents ed
    where ed.exit_case_id = v_case.exit_case_id
      and ed.document_variant = v_request.document_variant
    for update;

    if v_existing_document.document_id is not null then
        if v_is_certificate_variant
           and v_existing_document.certificate_id is null
           and v_existing_document.storage_path is not null then
            raise exception using
                errcode = 'P0001',
                message = 'Stored certificate requires identity reconciliation before retry.';
        end if;

        if v_existing_document.certificate_id is not null
           and v_existing_document.certificate_id is distinct from v_certificate_id then
            raise exception using
                errcode = 'P0001',
                message = 'Certificate identity cannot be replaced.';
        end if;
    end if;

    insert into public.exit_documents (
        document_id,
        exit_case_id,
        document_type,
        storage_path,
        uploaded_by,
        uploaded_at,
        bucket_id,
        generated_at,
        generated_by_job_id,
        document_variant,
        template_key,
        template_version,
        certificate_id,
        certificate_verification_url
    )
    values (
        p_document_id,
        v_case.exit_case_id,
        case when v_request.document_variant like '%CERTIFICATE' then 'CERTIFICATE' else 'LOR' end,
        p_storage_path,
        null,
        now(),
        p_bucket_id,
        now(),
        p_job_id,
        v_request.document_variant,
        p_template_key,
        p_template_version,
        v_certificate_id,
        p_certificate_verification_url
    )
    on conflict (exit_case_id, document_variant) where document_variant is not null
    do update set
        storage_path = excluded.storage_path,
        bucket_id = excluded.bucket_id,
        generated_at = excluded.generated_at,
        generated_by_job_id = excluded.generated_by_job_id,
        template_key = excluded.template_key,
        template_version = excluded.template_version,
        certificate_id = coalesce(public.exit_documents.certificate_id, excluded.certificate_id),
        certificate_verification_url = excluded.certificate_verification_url
    returning * into v_document;

    update public.exit_document_requests
    set status = 'GENERATED', error_message = null
    where request_id = v_request.request_id;

    return query
    select
        v_document.document_id,
        v_case.candidate_id,
        mc.email::text,
        v_request.document_variant
    from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id;
end;
$function$;

revoke all on function public.complete_exit_document_generation(uuid,uuid,text,text,text,text,text,text)
from public, anon, authenticated;

grant execute on function public.complete_exit_document_generation(uuid,uuid,text,text,text,text,text,text)
to service_role;

comment on function public.complete_exit_document_generation(uuid,uuid,text,text,text,text,text,text) is
    'Finalizes generated Exit documents for a fenced service-role job while enforcing stable certificate identity invariants.';

commit;
