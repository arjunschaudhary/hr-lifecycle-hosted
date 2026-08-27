begin;

-- `document_variant` is also a RETURNS TABLE output parameter. Prefer the
-- physical column in the conflict target and qualify every table reference.
-- The public wrapper retains the exact frontend-facing signature.
create or replace function public.request_exit_documents_internal(
    p_exit_case_id uuid,
    p_document_variants text[],
    p_allow_date_mismatch boolean default false
)
returns table (request_id uuid, document_variant text, status text)
language plpgsql volatile security definer
set search_path = public, auth, pg_temp
as $function$
#variable_conflict use_column
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_eligibility record;
    v_request public.exit_document_requests%rowtype;
    v_job public.automation_jobs%rowtype;
    v_variant text;
    v_idempotency_key text;
    v_now timestamptz := pg_catalog.now();
    v_override_approved boolean := false;
begin
    v_actor_user_id := public.current_app_user_id();
    if v_actor_user_id is null or not public.current_user_has_any_role(
        array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
              'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE']::text[]
    ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;
    if p_exit_case_id is null then raise exception using errcode = '22023', message = 'Exit case is required.'; end if;
    if p_allow_date_mismatch is null then raise exception using errcode = '22023', message = 'Date mismatch confirmation is required.'; end if;
    if p_document_variants is null or cardinality(p_document_variants) = 0 then raise exception using errcode = '22023', message = 'Select at least one document variant.'; end if;
    if cardinality(p_document_variants) > 6
       or exists (select 1 from unnest(p_document_variants) as requested(variant) where requested.variant not in ('INTERN_CERTIFICATE', 'POD_LEAD_CERTIFICATE', 'VOLUNTEER_CERTIFICATE', 'INTERN_LOR', 'POD_LEAD_LOR', 'OPERATIONS_ASSOCIATE_LOR'))
       or cardinality(p_document_variants) <> (select count(distinct requested.variant) from unnest(p_document_variants) as requested(variant)) then
        raise exception using errcode = '22023', message = 'Selected document variants are invalid.';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('exit-document-request:' || p_exit_case_id::text, 0));
    select ec.* into v_case from public.exit_cases ec where ec.exit_case_id = p_exit_case_id for update;
    if v_case.exit_case_id is null then raise exception using errcode = 'P0001', message = 'Exit case was not found.'; end if;
    select * into v_eligibility from public.get_exit_document_eligibility_internal(p_exit_case_id);
    if v_eligibility.warning_required and not p_allow_date_mismatch then raise exception using errcode = 'P0001', message = 'Exit date does not match the current internship end date. Explicit HR confirmation is required.'; end if;
    if exists (select 1 from unnest(p_document_variants) as requested(variant) where requested.variant <> all(v_eligibility.allowed_variants)) then raise exception using errcode = '22023', message = 'One or more selected document variants are not allowed for this candidate.'; end if;
    v_override_approved := v_eligibility.warning_required and p_allow_date_mismatch;
    foreach v_variant in array p_document_variants loop
        insert into public.exit_document_requests as ecr (exit_case_id, document_variant, status, requested_by, requested_at, date_mismatch_override_approved, created_at, updated_at)
        values (v_case.exit_case_id, v_variant, 'REQUESTED', v_actor_user_id, v_now, v_override_approved, v_now, v_now)
        on conflict (exit_case_id, document_variant) do update
        set date_mismatch_override_approved = ecr.date_mismatch_override_approved or excluded.date_mismatch_override_approved
        returning ecr.* into v_request;
        v_idempotency_key := 'EXIT_DOCUMENT:' || v_case.exit_case_id::text || ':' || v_variant;
        select aj.* into v_job from public.automation_jobs aj where aj.idempotency_key = v_idempotency_key for update;
        if v_job.job_id is null then
            insert into public.automation_jobs as aj (candidate_id, job_type, job_status, payload, scheduled_at, attempt_count, completed_at, error_message, idempotency_key, requested_by, last_attempt_at, created_at, updated_at)
            values (v_case.candidate_id, 'EXIT_DOCUMENT', 'PENDING', pg_catalog.jsonb_build_object('exit_case_id', v_case.exit_case_id, 'exit_document_request_id', v_request.request_id, 'document_variant', v_variant), v_now, 0, null, null, v_idempotency_key, v_actor_user_id, null, v_now, v_now)
            returning aj.* into v_job;
        elsif v_job.job_type is distinct from 'EXIT_DOCUMENT'
           or v_job.candidate_id is distinct from v_case.candidate_id
           or v_job.payload ->> 'exit_case_id' is distinct from v_case.exit_case_id::text
           or v_job.payload ->> 'exit_document_request_id' is distinct from v_request.request_id::text
           or v_job.payload ->> 'document_variant' is distinct from v_variant then
            raise exception using errcode = 'P0001', message = 'Exit-document automation job is inconsistent with the request.';
        end if;
        if v_request.job_id is not null and v_request.job_id is distinct from v_job.job_id then raise exception using errcode = 'P0001', message = 'Exit-document request is assigned to another automation job.'; end if;
        update public.exit_document_requests as ecr set job_id = v_job.job_id where ecr.request_id = v_request.request_id and ecr.job_id is null;
    end loop;
    return query
    select ecr.request_id, ecr.document_variant, ecr.status
    from public.exit_document_requests as ecr
    where ecr.exit_case_id = v_case.exit_case_id
      and ecr.document_variant = any(p_document_variants)
    order by ecr.document_variant;
end;
$function$;

revoke execute on function public.request_exit_documents_internal(uuid, text[], boolean) from public, anon, authenticated;
grant execute on function public.request_exit_documents_internal(uuid, text[], boolean) to service_role;

commit;
