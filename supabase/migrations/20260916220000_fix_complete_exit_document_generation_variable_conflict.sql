begin;

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
declare v_job public.automation_jobs%rowtype; v_request public.exit_document_requests%rowtype; v_case public.exit_cases%rowtype; v_document public.exit_documents%rowtype;
begin
    if auth.role() is distinct from 'service_role' then raise exception using errcode='42501', message='Service-role worker access is required.'; end if;
    select * into v_job from public.automation_jobs where job_id=p_job_id for update;
    if v_job.job_type <> 'EXIT_DOCUMENT' or v_job.job_status <> 'PROCESSING' then raise exception using errcode='P0001', message='Exit-document job is not being processed.'; end if;
    select * into v_request from public.exit_document_requests where job_id=p_job_id for update;
    select * into v_case from public.exit_cases where exit_case_id=v_request.exit_case_id;
    if p_bucket_id <> 'candidate-issued-documents'
       or p_storage_path not like format('candidate/%s/exit/%s/%s/%%.pdf', v_case.candidate_id, v_case.exit_case_id, v_request.document_variant) then
        raise exception using errcode='22023', message='Issued-document storage path is invalid.';
    end if;
    insert into public.exit_documents (document_id, exit_case_id, document_type, storage_path, uploaded_by, uploaded_at, bucket_id, generated_at, generated_by_job_id, document_variant, template_key, template_version, certificate_id, certificate_verification_url)
    values (p_document_id, v_case.exit_case_id, case when v_request.document_variant like '%CERTIFICATE' then 'CERTIFICATE' else 'LOR' end, p_storage_path, null, now(), p_bucket_id, now(), p_job_id, v_request.document_variant, p_template_key, p_template_version, p_certificate_id, p_certificate_verification_url)
    on conflict (exit_case_id, document_variant) where document_variant is not null do update set storage_path=excluded.storage_path, bucket_id=excluded.bucket_id, generated_at=excluded.generated_at, generated_by_job_id=excluded.generated_by_job_id, template_key=excluded.template_key, template_version=excluded.template_version, certificate_id=coalesce(public.exit_documents.certificate_id, excluded.certificate_id), certificate_verification_url=excluded.certificate_verification_url
    returning * into v_document;
    update public.exit_document_requests set status='GENERATED', error_message=null where request_id=v_request.request_id;
    return query select v_document.document_id, v_case.candidate_id, mc.email::text, v_request.document_variant from public.master_candidates mc where mc.candidate_id=v_case.candidate_id;
end;
$function$;

commit;
