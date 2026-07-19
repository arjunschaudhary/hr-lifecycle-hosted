create table if not exists public.daily_performance_entries (
    id uuid primary key default gen_random_uuid(),
    candidate_cycle_id uuid not null,
    performance_date date not null,
    work_delivery_score smallint not null,
    communication_responsibility_score smallint not null,
    daily_total smallint generated always as (
        work_delivery_score + communication_responsibility_score
    ) stored,
    reviewer_user_id uuid not null,
    reason_code text null,
    reviewer_comment text null,
    submitted_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint daily_performance_entries_candidate_cycle_id_fk
        foreign key (candidate_cycle_id)
        references public.candidate_performance_cycles(id)
        on delete restrict,
    constraint daily_performance_entries_reviewer_user_id_fk
        foreign key (reviewer_user_id)
        references public.users(id)
        on delete restrict,
    constraint daily_performance_entries_candidate_cycle_date_unique
        unique (candidate_cycle_id, performance_date),
    constraint daily_performance_entries_work_delivery_score_check
        check (work_delivery_score between -5 and 5),
    constraint daily_performance_entries_communication_responsibility_score_check
        check (communication_responsibility_score between -5 and 5),
    constraint daily_performance_entries_reason_code_check
        check (
            reason_code is null
            or reason_code in (
                'WORK_COMPLETED',
                'PARTIAL_COMPLETION',
                'QUALITY_ISSUE',
                'DEADLINE_DELAY',
                'BLOCKER_COMMUNICATED',
                'MISSED_UPDATE',
                'STRONG_OWNERSHIP',
                'MEETING_ABSENCE',
                'FALSE_UPDATE',
                'OTHER'
            )
        ),
    constraint daily_performance_entries_reason_required_check
        check (
            not (
                (work_delivery_score + communication_responsibility_score) <= -5
                or (work_delivery_score + communication_responsibility_score) = 10
            )
            or reason_code is not null
        ),
    constraint daily_performance_entries_reviewer_comment_not_blank_check
        check (
            reviewer_comment is null
            or btrim(reviewer_comment) <> ''
        ),
    constraint daily_performance_entries_minimum_score_comment_required_check
        check (
            (work_delivery_score + communication_responsibility_score) <> -10
            or (
                reviewer_comment is not null
                and btrim(reviewer_comment) <> ''
            )
        )
);

comment on table public.daily_performance_entries is
    'Daily performance scores. Sunday and approved-leave eligibility will be enforced later through controlled scoring logic. Reviewer authorization and cycle-lock checks will be added later through RLS, services, or database functions.';

comment on column public.daily_performance_entries.work_delivery_score is
    'Work Delivery and Quality score from -5 to 5.';

comment on column public.daily_performance_entries.communication_responsibility_score is
    'Communication and Responsibility score from -5 to 5.';

comment on column public.daily_performance_entries.daily_total is
    'Database-generated sum of both score columns from -10 to 10; it cannot be entered manually.';

create index if not exists idx_daily_performance_entries_performance_date
    on public.daily_performance_entries (performance_date);

create index if not exists idx_daily_performance_entries_reviewer_date
    on public.daily_performance_entries (reviewer_user_id, performance_date);

alter table public.daily_performance_entries enable row level security;

-- RLS policies will be added separately with the HR PsyConnect permission matrix.
