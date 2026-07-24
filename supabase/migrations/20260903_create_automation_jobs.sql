create table public.automation_jobs (
    job_id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null,
    job_type text not null,
    job_status text not null default 'PENDING',
    payload jsonb not null default '{}'::jsonb,
    scheduled_at timestamptz not null default now(),
    attempt_count integer not null default 0,
    completed_at timestamptz null,
    error_message text null,
    idempotency_key text not null,
    provider_message_id text null,
    provider_accepted_at timestamptz null,
    requested_by uuid not null,
    last_attempt_at timestamptz null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint automation_jobs_candidate_id_fk
        foreign key (candidate_id)
        references public.master_candidates(candidate_id)
        on delete restrict,
    constraint automation_jobs_requested_by_fk
        foreign key (requested_by)
        references public.users(id)
        on delete restrict,
    constraint automation_jobs_idempotency_key_unique
        unique (idempotency_key),
    constraint automation_jobs_status_check
        check (
            job_status in (
                'PENDING',
                'PROCESSING',
                'SUCCESS',
                'FAILED',
                'RETRY',
                'CANCELLED'
            )
        ),
    constraint automation_jobs_attempt_count_non_negative_check
        check (attempt_count >= 0),
    constraint automation_jobs_payload_object_check
        check (jsonb_typeof(payload) = 'object'),
    constraint automation_jobs_error_message_length_check
        check (
            error_message is null
            or char_length(error_message) <= 1000
        ),
    constraint automation_jobs_provider_message_id_length_check
        check (
            provider_message_id is null
            or char_length(provider_message_id) <= 500
        ),
    constraint automation_jobs_job_type_not_blank_check
        check (btrim(job_type) <> ''),
    constraint automation_jobs_idempotency_key_not_blank_check
        check (btrim(idempotency_key) <> ''),
    constraint automation_jobs_success_completed_at_check
        check (job_status <> 'SUCCESS' or completed_at is not null)
);

comment on table public.automation_jobs is
    'Durable server-owned automation ledger. Welcome-email jobs use the deterministic idempotency key WELCOME_MAIL:<candidate_uuid>.';

comment on column public.automation_jobs.requested_by is
    'Active public.users.id value for the staff user who requested the automation.';

comment on column public.automation_jobs.payload is
    'Non-secret structured job metadata. Provider credentials, headers, tokens, and full provider responses must never be stored here.';

comment on column public.automation_jobs.provider_message_id is
    'Non-secret provider message identifier used to prevent a provider-accepted email from being sent again.';

create index automation_jobs_status_scheduled_at_idx
    on public.automation_jobs (job_status, scheduled_at);

create index automation_jobs_candidate_created_at_idx
    on public.automation_jobs (candidate_id, created_at desc);

create index automation_jobs_job_type_candidate_idx
    on public.automation_jobs (job_type, candidate_id);

create index automation_jobs_provider_message_id_idx
    on public.automation_jobs (provider_message_id)
    where provider_message_id is not null;

alter table public.automation_jobs enable row level security;

drop policy if exists automation_jobs_staff_select
    on public.automation_jobs;

create policy automation_jobs_staff_select
on public.automation_jobs
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

revoke all privileges on table public.automation_jobs from public;
revoke all privileges on table public.automation_jobs from anon;
revoke all privileges on table public.automation_jobs from authenticated;

grant select on table public.automation_jobs to authenticated;
grant all privileges on table public.automation_jobs to service_role;

-- Authenticated staff receive read-only access through RLS.
-- Server-side service-role code owns all job mutations.
