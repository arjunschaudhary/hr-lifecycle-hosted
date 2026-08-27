begin;

-- Keep the Phase 1-3 implementations intact while placing their existing
-- role resolver behind a narrower, module-specific entry point.
alter function public.get_exit_document_eligibility(uuid)
    rename to get_exit_document_eligibility_internal;
alter function public.get_hr_exit_document_request_statuses(uuid[])
    rename to get_hr_exit_document_request_statuses_internal;
alter function public.request_exit_documents(uuid, text[], boolean)
    rename to request_exit_documents_internal;

revoke all on function public.get_exit_document_eligibility_internal(uuid) from public, anon, authenticated;
revoke all on function public.get_hr_exit_document_request_statuses_internal(uuid[]) from public, anon, authenticated;
revoke all on function public.request_exit_documents_internal(uuid, text[], boolean) from public, anon, authenticated;

create function public.get_exit_document_eligibility(p_exit_case_id uuid)
returns table (
    eligible boolean, reason text, date_matches boolean, warning_required boolean,
    exit_date date, current_end_date date, candidate_id uuid, candidate_name text,
    candidate_email text, applied_role text, is_pod_lead boolean,
    is_operations_associate boolean, allowed_variants text[],
    allowed_certificate_variants text[], allowed_lor_variants text[]
)
language plpgsql stable security definer
set search_path = public, auth, pg_temp
as $function$
begin
    if public.current_app_user_id() is null
       or not public.current_user_has_role('HR_SITE_CONNECT_LEAD') then
        raise exception using errcode = '42501', message = 'HR Site Connect Lead access is required.';
    end if;

    return query select * from public.get_exit_document_eligibility_internal(p_exit_case_id);
end;
$function$;

create function public.get_hr_exit_document_request_statuses(p_exit_case_ids uuid[] default null)
returns table (exit_case_id uuid, certificate_status text, lor_status text)
language plpgsql stable security definer
set search_path = public, auth, pg_temp
as $function$
begin
    if public.current_app_user_id() is null
       or not public.current_user_has_role('HR_SITE_CONNECT_LEAD') then
        raise exception using errcode = '42501', message = 'HR Site Connect Lead access is required.';
    end if;

    return query select * from public.get_hr_exit_document_request_statuses_internal(p_exit_case_ids);
end;
$function$;

create function public.request_exit_documents(
    p_exit_case_id uuid,
    p_document_variants text[],
    p_allow_date_mismatch boolean default false
)
returns table (request_id uuid, document_variant text, status text)
language plpgsql volatile security definer
set search_path = public, auth, pg_temp
as $function$
begin
    if public.current_app_user_id() is null
       or not public.current_user_has_role('HR_SITE_CONNECT_LEAD') then
        raise exception using errcode = '42501', message = 'HR Site Connect Lead access is required.';
    end if;

    return query
    select * from public.request_exit_documents_internal(
        p_exit_case_id,
        p_document_variants,
        p_allow_date_mismatch
    );
end;
$function$;

comment on function public.get_exit_document_eligibility(uuid) is
    'Certificate and LOR eligibility is available only to active HR_SITE_CONNECT_LEAD users.';
comment on function public.get_hr_exit_document_request_statuses(uuid[]) is
    'Certificate and LOR request statuses are available only to active HR_SITE_CONNECT_LEAD users.';
comment on function public.request_exit_documents(uuid, text[], boolean) is
    'Certificate and LOR document requests are available only to active HR_SITE_CONNECT_LEAD users.';

commit;
