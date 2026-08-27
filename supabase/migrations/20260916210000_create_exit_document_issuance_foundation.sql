begin;

-- Phase 1: durable issuance metadata for Certificate and LOR documents.
-- Existing exit documents may predate variants, so document_variant remains nullable
-- for legacy rows. New issuance requests always use one of the approved variants.
alter table public.exit_documents
    add column if not exists document_variant text,
    add column if not exists bucket_id text,
    add column if not exists generated_at timestamptz,
    add column if not exists generated_by_job_id uuid,
    add column if not exists template_key text,
    add column if not exists template_version text;

alter table public.exit_documents
    drop constraint if exists exit_documents_document_variant_check,
    add constraint exit_documents_document_variant_check
        check (
            document_variant is null
            or document_variant in (
                'CERTIFICATE_INTERN',
                'CERTIFICATE_POD_LEAD',
                'CERTIFICATE_VOLUNTEER',
                'LOR_INTERN',
                'LOR_POD_LEAD',
                'LOR_OPERATIONS_ASSOCIATE'
            )
        ),
    drop constraint if exists exit_documents_variant_type_check,
    add constraint exit_documents_variant_type_check
        check (
            document_variant is null
            or (
                document_variant in (
                    'CERTIFICATE_INTERN',
                    'CERTIFICATE_POD_LEAD',
                    'CERTIFICATE_VOLUNTEER'
                )
                and document_type = 'CERTIFICATE'
            )
            or (
                document_variant in (
                    'LOR_INTERN',
                    'LOR_POD_LEAD',
                    'LOR_OPERATIONS_ASSOCIATE'
                )
                and document_type = 'LOR'
            )
        ),
    drop constraint if exists exit_documents_generated_by_job_id_fkey,
    add constraint exit_documents_generated_by_job_id_fkey
        foreign key (generated_by_job_id)
        references public.automation_jobs(job_id)
        on delete set null;

create unique index if not exists uq_exit_documents_case_variant
    on public.exit_documents (exit_case_id, document_variant)
    where document_variant is not null;

create index if not exists idx_exit_documents_generated_by_job
    on public.exit_documents (generated_by_job_id)
    where generated_by_job_id is not null;

create table if not exists public.exit_document_requests (
    request_id uuid primary key default gen_random_uuid(),
    exit_case_id uuid not null,
    document_variant text not null,
    status text not null default 'REQUESTED',
    requested_by uuid not null,
    requested_at timestamptz not null default now(),
    job_id uuid null,
    error_message text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint exit_document_requests_exit_case_id_fkey
        foreign key (exit_case_id)
        references public.exit_cases(exit_case_id)
        on delete cascade,
    constraint exit_document_requests_requested_by_fkey
        foreign key (requested_by)
        references public.users(id)
        on delete restrict,
    constraint exit_document_requests_job_id_fkey
        foreign key (job_id)
        references public.automation_jobs(job_id)
        on delete set null,
    constraint exit_document_requests_variant_check
        check (
            document_variant in (
                'CERTIFICATE_INTERN',
                'CERTIFICATE_POD_LEAD',
                'CERTIFICATE_VOLUNTEER',
                'LOR_INTERN',
                'LOR_POD_LEAD',
                'LOR_OPERATIONS_ASSOCIATE'
            )
        ),
    constraint exit_document_requests_status_check
        check (status in ('REQUESTED', 'PROCESSING', 'GENERATED', 'EMAILED', 'FAILED')),
    constraint exit_document_requests_error_message_length_check
        check (error_message is null or char_length(error_message) <= 1000)
);

create unique index if not exists uq_exit_document_requests_case_variant
    on public.exit_document_requests (exit_case_id, document_variant);

create index if not exists idx_exit_document_requests_status_requested_at
    on public.exit_document_requests (status, requested_at);

create index if not exists idx_exit_document_requests_job_id
    on public.exit_document_requests (job_id)
    where job_id is not null;

drop trigger if exists trg_exit_document_requests_updated_at
    on public.exit_document_requests;

create trigger trg_exit_document_requests_updated_at
before update on public.exit_document_requests
for each row
execute function public.update_updated_at_column();

alter table public.exit_document_requests enable row level security;

revoke all privileges on table public.exit_document_requests from public;
revoke all privileges on table public.exit_document_requests from anon;
revoke all privileges on table public.exit_document_requests from authenticated;
grant all privileges on table public.exit_document_requests to service_role;

create or replace function public.get_exit_document_eligibility(
    p_exit_case_id uuid
)
returns table (
    eligible boolean,
    reason text,
    exit_date date,
    current_end_date date,
    candidate_id uuid,
    candidate_name text,
    candidate_email text,
    applied_role text,
    is_pod_lead boolean,
    allowed_certificate_variants text[],
    allowed_lor_variants text[]
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_candidate public.master_candidates%rowtype;
    v_is_pod_lead boolean := false;
    v_certificate_variants text[] := array[]::text[];
    v_lor_variants text[] := array[]::text[];
    v_business_date date := (current_timestamp at time zone 'Asia/Kolkata')::date;
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

    if p_exit_case_id is null then
        raise exception using
            errcode = '22023',
            message = 'Exit case is required.';
    end if;

    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.exit_case_id = p_exit_case_id;

    if v_case.exit_case_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case was not found.';
    end if;

    -- Eligibility is deliberately bound to the lifecycle snapshot referenced by
    -- the exit case. Do not resolve a lifecycle row by candidate_id and do not
    -- fall back to original_end_date.
    select hl.*
    into v_lifecycle
    from public.hr_lifecycle hl
    where hl.lifecycle_id = v_case.lifecycle_id;

    if v_lifecycle.lifecycle_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case lifecycle record was not found.';
    end if;

    select mc.*
    into v_candidate
    from public.master_candidates mc
    where mc.candidate_id = v_case.candidate_id;

    if v_candidate.candidate_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case candidate was not found.';
    end if;

    -- This mirrors Current Pod Leads: an active, currently effective POD_LEAD
    -- membership for the candidate's mapped active application user.
    select exists (
        select 1
        from public.candidate_user_accounts cua
        join public.users u
          on u.id = cua.user_id
         and u.status = 'active'
        join public.pod_memberships pm
          on pm.user_id = u.id
         and pm.candidate_id is null
         and pm.membership_type = 'POD_LEAD'
         and pm.is_active = true
         and pm.effective_from <= v_business_date
         and (pm.effective_to is null or pm.effective_to >= v_business_date)
        where cua.candidate_id = v_case.candidate_id
          and cua.account_status = 'ACTIVE'
    ) into v_is_pod_lead;

    if v_lifecycle.current_end_date is null then
        return query
        select
            false,
            'CURRENT_END_DATE_NOT_SET'::text,
            v_case.exit_date,
            v_lifecycle.current_end_date,
            v_case.candidate_id,
            v_candidate.full_name::text,
            v_candidate.email::text,
            v_candidate.applied_role::text,
            v_is_pod_lead,
            array[]::text[],
            array[]::text[];
        return;
    end if;

    if v_case.exit_date is distinct from v_lifecycle.current_end_date then
        return query
        select
            false,
            'EXIT_DATE_DOES_NOT_MATCH_CURRENT_END_DATE'::text,
            v_case.exit_date,
            v_lifecycle.current_end_date,
            v_case.candidate_id,
            v_candidate.full_name::text,
            v_candidate.email::text,
            v_candidate.applied_role::text,
            v_is_pod_lead,
            array[]::text[],
            array[]::text[];
        return;
    end if;

    v_certificate_variants := array[
        'CERTIFICATE_INTERN',
        'CERTIFICATE_VOLUNTEER'
    ]::text[];
    v_lor_variants := array['LOR_INTERN']::text[];

    if v_is_pod_lead then
        v_certificate_variants := array_append(
            v_certificate_variants,
            'CERTIFICATE_POD_LEAD'
        );
        v_lor_variants := array_append(v_lor_variants, 'LOR_POD_LEAD');
    end if;

    -- Operations Associate is determined only from the canonical applied-role
    -- value; no other role, user-role, or pod data participates in this decision.
    if v_candidate.applied_role = 'Operations Associate Intern' then
        v_lor_variants := array_append(
            v_lor_variants,
            'LOR_OPERATIONS_ASSOCIATE'
        );
    end if;

    return query
    select
        true,
        'ELIGIBLE'::text,
        v_case.exit_date,
        v_lifecycle.current_end_date,
        v_case.candidate_id,
        v_candidate.full_name::text,
        v_candidate.email::text,
        v_candidate.applied_role::text,
        v_is_pod_lead,
        v_certificate_variants,
        v_lor_variants;
end;
$function$;

comment on function public.get_exit_document_eligibility(uuid) is
    'Returns server-derived Certificate and LOR eligibility for one Exit case. Eligibility requires exit_cases.exit_date to equal the linked hr_lifecycle.current_end_date exactly; original_end_date is never used.';

revoke execute on function public.get_exit_document_eligibility(uuid) from public;
revoke execute on function public.get_exit_document_eligibility(uuid) from anon;
grant execute on function public.get_exit_document_eligibility(uuid) to authenticated;
grant execute on function public.get_exit_document_eligibility(uuid) to service_role;

commit;
