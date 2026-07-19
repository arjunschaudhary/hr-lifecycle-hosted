create table if not exists public.performance_cycles (
    id uuid primary key default gen_random_uuid(),
    cycle_code text not null,
    cycle_number integer not null,
    start_date date not null,
    end_date date not null,
    review_open_date date not null,
    lock_date date not null,
    cycle_status text not null default 'DRAFT',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint performance_cycles_cycle_code_unique unique (cycle_code),
    constraint performance_cycles_cycle_code_not_empty_check check (btrim(cycle_code) <> ''),
    constraint performance_cycles_cycle_number_check check (cycle_number in (1, 2, 3)),
    constraint performance_cycles_date_range_check check (end_date >= start_date),
    constraint performance_cycles_review_open_date_check check (review_open_date > end_date),
    constraint performance_cycles_lock_date_check check (lock_date > review_open_date),
    constraint performance_cycles_status_check check (
        cycle_status in (
            'DRAFT',
            'OPEN',
            'REVIEW_OPEN',
            'READY_TO_CALCULATE',
            'CANDIDATE_REVIEW',
            'FINALIZED',
            'LOCKED'
        )
    ),
    constraint performance_cycles_date_range_unique unique (start_date, end_date)
);

comment on table public.performance_cycles is
    'Cycle 1 normally represents the 1st-10th, Cycle 2 the 11th-20th, and Cycle 3 the 21st through the last calendar day. Exact cycle generation logic will be added separately.';

create table if not exists public.candidate_performance_cycles (
    id uuid primary key default gen_random_uuid(),
    cycle_id uuid not null,
    candidate_id uuid not null,
    pod_id uuid not null,
    evaluation_start_date date not null,
    evaluation_end_date date not null,
    is_partial_cycle boolean not null default false,
    eligible_days integer not null default 0,
    scored_days integer not null default 0,
    daily_average numeric(5,2) null,
    daily_component_score numeric(5,2) null,
    lead_score numeric(5,2) null,
    hr_score numeric(5,2) null,
    exceptional_score numeric(5,2) null,
    final_score numeric(5,2) null,
    performance_band text null,
    result_status text not null default 'PENDING',
    calculated_at timestamptz null,
    finalized_at timestamptz null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint candidate_performance_cycles_cycle_id_fk
        foreign key (cycle_id) references public.performance_cycles(id) on delete restrict,
    constraint candidate_performance_cycles_candidate_id_fk
        foreign key (candidate_id) references public.master_candidates(candidate_id) on delete restrict,
    constraint candidate_performance_cycles_pod_id_fk
        foreign key (pod_id) references public.pods(id) on delete restrict,
    constraint candidate_performance_cycles_cycle_candidate_unique unique (cycle_id, candidate_id),
    constraint candidate_performance_cycles_evaluation_date_range_check
        check (evaluation_end_date >= evaluation_start_date),
    constraint candidate_performance_cycles_eligible_days_non_negative_check
        check (eligible_days >= 0),
    constraint candidate_performance_cycles_scored_days_non_negative_check
        check (scored_days >= 0),
    constraint candidate_performance_cycles_scored_days_eligible_check
        check (scored_days <= eligible_days),
    constraint candidate_performance_cycles_daily_average_check
        check (daily_average is null or daily_average between -10 and 10),
    constraint candidate_performance_cycles_daily_component_score_check
        check (daily_component_score is null or daily_component_score between 0 and 50),
    constraint candidate_performance_cycles_lead_score_check
        check (lead_score is null or lead_score between 0 and 25),
    constraint candidate_performance_cycles_hr_score_check
        check (hr_score is null or hr_score between 0 and 15),
    constraint candidate_performance_cycles_exceptional_score_check
        check (exceptional_score is null or exceptional_score between 0 and 10),
    constraint candidate_performance_cycles_final_score_check
        check (final_score is null or final_score between 0 and 100),
    constraint candidate_performance_cycles_performance_band_check
        check (
            performance_band is null
            or performance_band in (
                'OUTSTANDING',
                'EXCELLENT',
                'GOOD',
                'IMPROVEMENT_REQUIRED',
                'FORMAL_REVIEW'
            )
        ),
    constraint candidate_performance_cycles_result_status_check
        check (
            result_status in (
                'PENDING',
                'DAILY_SCORING',
                'AWAITING_REVIEWS',
                'READY_TO_CALCULATE',
                'CANDIDATE_REVIEW',
                'FINALIZED',
                'LOCKED'
            )
        )
);

comment on table public.candidate_performance_cycles is
    'Candidate performance-cycle summary records. Score fields are summary fields and will be populated only after later scoring and review logic is added.';

comment on column public.candidate_performance_cycles.evaluation_start_date is
    'May be later than the company cycle start when a candidate joins midway.';

comment on column public.candidate_performance_cycles.evaluation_end_date is
    'May be earlier than the company cycle end when an internship ends midway.';

comment on column public.candidate_performance_cycles.eligible_days is
    'Sundays and approved leave will later be excluded from eligible days.';

comment on column public.candidate_performance_cycles.pod_id is
    'Historical pod snapshot for this candidate and company cycle.';

create index if not exists idx_performance_cycles_end_date
    on public.performance_cycles (end_date);

create index if not exists idx_performance_cycles_cycle_status
    on public.performance_cycles (cycle_status);

create index if not exists idx_candidate_performance_cycles_result_status
    on public.candidate_performance_cycles (result_status);

create index if not exists idx_candidate_performance_cycles_pod_cycle
    on public.candidate_performance_cycles (pod_id, cycle_id);

create index if not exists idx_candidate_performance_cycles_candidate_evaluation_start
    on public.candidate_performance_cycles (candidate_id, evaluation_start_date);

alter table public.performance_cycles enable row level security;
alter table public.candidate_performance_cycles enable row level security;

-- RLS policies will be added separately with the HR PsyConnect permission matrix.
