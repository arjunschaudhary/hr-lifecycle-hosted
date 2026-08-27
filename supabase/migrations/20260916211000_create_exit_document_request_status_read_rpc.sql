begin;

-- Phase 2 read contract. Requests are intentionally service-role owned, so HR
-- clients receive only grouped display status through this secure RPC.
create or replace function public.get_hr_exit_document_request_statuses(
    p_exit_case_ids uuid[] default null
)
returns table (
    exit_case_id uuid,
    certificate_status text,
    lor_status text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using
            errcode = '42501',
            message = 'Authorized HR access is required.';
    end if;

    return query
    select
        ecr.exit_case_id,
        case
            when count(*) filter (
                where ecr.document_variant in (
                    'CERTIFICATE_INTERN',
                    'CERTIFICATE_POD_LEAD',
                    'CERTIFICATE_VOLUNTEER'
                )
            ) = 0 then 'NOT_REQUESTED'
            when bool_or(ecr.status = 'PROCESSING') filter (
                where ecr.document_variant in (
                    'CERTIFICATE_INTERN',
                    'CERTIFICATE_POD_LEAD',
                    'CERTIFICATE_VOLUNTEER'
                )
            ) then 'PROCESSING'
            when bool_or(ecr.status = 'REQUESTED') filter (
                where ecr.document_variant in (
                    'CERTIFICATE_INTERN',
                    'CERTIFICATE_POD_LEAD',
                    'CERTIFICATE_VOLUNTEER'
                )
            ) then 'REQUESTED'
            when bool_or(ecr.status = 'GENERATED') filter (
                where ecr.document_variant in (
                    'CERTIFICATE_INTERN',
                    'CERTIFICATE_POD_LEAD',
                    'CERTIFICATE_VOLUNTEER'
                )
            ) then 'GENERATED'
            when bool_or(ecr.status = 'FAILED') filter (
                where ecr.document_variant in (
                    'CERTIFICATE_INTERN',
                    'CERTIFICATE_POD_LEAD',
                    'CERTIFICATE_VOLUNTEER'
                )
            ) then 'FAILED'
            else 'EMAILED'
        end::text,
        case
            when count(*) filter (
                where ecr.document_variant in (
                    'LOR_INTERN',
                    'LOR_POD_LEAD',
                    'LOR_OPERATIONS_ASSOCIATE'
                )
            ) = 0 then 'NOT_REQUESTED'
            when bool_or(ecr.status = 'PROCESSING') filter (
                where ecr.document_variant in (
                    'LOR_INTERN',
                    'LOR_POD_LEAD',
                    'LOR_OPERATIONS_ASSOCIATE'
                )
            ) then 'PROCESSING'
            when bool_or(ecr.status = 'REQUESTED') filter (
                where ecr.document_variant in (
                    'LOR_INTERN',
                    'LOR_POD_LEAD',
                    'LOR_OPERATIONS_ASSOCIATE'
                )
            ) then 'REQUESTED'
            when bool_or(ecr.status = 'GENERATED') filter (
                where ecr.document_variant in (
                    'LOR_INTERN',
                    'LOR_POD_LEAD',
                    'LOR_OPERATIONS_ASSOCIATE'
                )
            ) then 'GENERATED'
            when bool_or(ecr.status = 'FAILED') filter (
                where ecr.document_variant in (
                    'LOR_INTERN',
                    'LOR_POD_LEAD',
                    'LOR_OPERATIONS_ASSOCIATE'
                )
            ) then 'FAILED'
            else 'EMAILED'
        end::text
    from public.exit_document_requests ecr
    where p_exit_case_ids is null
       or ecr.exit_case_id = any(p_exit_case_ids)
    group by ecr.exit_case_id;
end;
$function$;

comment on function public.get_hr_exit_document_request_statuses(uuid[]) is
    'Returns grouped Certificate and LOR request statuses for authorized HR users without granting direct access to exit_document_requests.';

revoke execute on function public.get_hr_exit_document_request_statuses(uuid[]) from public;
revoke execute on function public.get_hr_exit_document_request_statuses(uuid[]) from anon;
grant execute on function public.get_hr_exit_document_request_statuses(uuid[]) to authenticated;
grant execute on function public.get_hr_exit_document_request_statuses(uuid[]) to service_role;

commit;
