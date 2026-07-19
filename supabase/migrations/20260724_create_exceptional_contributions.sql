create table if not exists public.exceptional_contributions (
    id uuid primary key default gen_random_uuid(),
    candidate_cycle_id uuid not null,
    contribution_type text not null,
    title text not null,
    description text not null,
    points smallint not null,
    evidence_url text null,
    source_type text not null default 'MANUAL',
    external_reference_id text null,
    submitted_by_user_id uuid not null,
    approval_status text not null default 'PENDING',
    reviewed_by_user_id uuid null,
    reviewed_at timestamptz null,
    review_notes text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint exceptional_contributions_candidate_cycle_id_fk
        foreign key (candidate_cycle_id)
        references public.candidate_performance_cycles(id)
        on delete restrict,
    constraint exceptional_contributions_submitted_by_user_id_fk
        foreign key (submitted_by_user_id)
        references public.users(id)
        on delete restrict,
    constraint exceptional_contributions_reviewed_by_user_id_fk
        foreign key (reviewed_by_user_id)
        references public.users(id)
        on delete restrict,
    constraint exceptional_contributions_contribution_type_check
        check (
            contribution_type in (
                'ADDITIONAL_TASK',
                'CROSS_TEAM_SUPPORT',
                'PROCESS_IMPROVEMENT',
                'LEADERSHIP',
                'HIGH_IMPACT_WORK',
                'REFERRAL',
                'OTHER'
            )
        ),
    constraint exceptional_contributions_source_type_check
        check (source_type in ('MANUAL', 'EXTERNAL_AUTOMATION')),
    constraint exceptional_contributions_approval_status_check
        check (approval_status in ('PENDING', 'APPROVED', 'REJECTED')),
    constraint exceptional_contributions_title_not_blank_check
        check (btrim(title) <> ''),
    constraint exceptional_contributions_description_not_blank_check
        check (btrim(description) <> ''),
    constraint exceptional_contributions_points_range_check
        check (points between 1 and 10),
    constraint exceptional_contributions_referral_points_check
        check (contribution_type <> 'REFERRAL' or points = 1),
    constraint exceptional_contributions_external_reference_check
        check (
            (
                source_type = 'EXTERNAL_AUTOMATION'
                and external_reference_id is not null
                and btrim(external_reference_id) <> ''
            )
            or (
                source_type = 'MANUAL'
                and (
                    external_reference_id is null
                    or btrim(external_reference_id) <> ''
                )
            )
        ),
    constraint exceptional_contributions_approval_state_check
        check (
            (
                approval_status = 'PENDING'
                and reviewed_by_user_id is null
                and reviewed_at is null
            )
            or (
                approval_status in ('APPROVED', 'REJECTED')
                and reviewed_by_user_id is not null
                and reviewed_at is not null
            )
        ),
    constraint exceptional_contributions_evidence_url_not_blank_check
        check (
            evidence_url is null
            or btrim(evidence_url) <> ''
        ),
    constraint exceptional_contributions_review_notes_not_blank_check
        check (
            review_notes is null
            or btrim(review_notes) <> ''
        )
);

comment on table public.exceptional_contributions is
    'Only approved contributions will later count toward a candidate exceptional score, capped at 10 points per candidate cycle. Reviewer authorization and cycle-lock enforcement will be added later. This migration does not perform referral automation.';

comment on column public.exceptional_contributions.points is
    'A verified referral contributes exactly 1 point. Other contribution types may contribute from 1 to 10 points.';

comment on column public.exceptional_contributions.external_reference_id is
    'Prevents duplicate automated referral awards when Ioana''s recruitment system is integrated.';

create index if not exists idx_exceptional_contributions_candidate_cycle_status
    on public.exceptional_contributions (candidate_cycle_id, approval_status);

create index if not exists idx_exceptional_contributions_submitter_created
    on public.exceptional_contributions (submitted_by_user_id, created_at);

create index if not exists idx_exceptional_contributions_reviewer_reviewed
    on public.exceptional_contributions (reviewed_by_user_id, reviewed_at);

create index if not exists idx_exceptional_contributions_contribution_type
    on public.exceptional_contributions (contribution_type);

create unique index if not exists uq_exceptional_contributions_external_reference
    on public.exceptional_contributions (external_reference_id)
    where external_reference_id is not null;

alter table public.exceptional_contributions enable row level security;

-- RLS policies will be added separately with the HR PsyConnect permission matrix.
