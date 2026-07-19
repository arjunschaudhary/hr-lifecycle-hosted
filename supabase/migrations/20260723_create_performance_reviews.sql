create table if not exists public.performance_reviews (
    id uuid primary key default gen_random_uuid(),
    candidate_cycle_id uuid not null,
    review_type text not null,
    reviewer_user_id uuid not null,
    work_quality_score smallint null,
    role_capability_score smallint null,
    deadline_delivery_score smallint null,
    ownership_teamwork_score smallint null,
    communication_professionalism_score smallint null,
    attendance_update_discipline_score smallint null,
    reporting_policy_compliance_score smallint null,
    total_score smallint generated always as (
        coalesce(work_quality_score, 0)
        + coalesce(role_capability_score, 0)
        + coalesce(deadline_delivery_score, 0)
        + coalesce(ownership_teamwork_score, 0)
        + coalesce(communication_professionalism_score, 0)
        + coalesce(attendance_update_discipline_score, 0)
        + coalesce(reporting_policy_compliance_score, 0)
    ) stored,
    reviewer_comment text null,
    review_status text not null default 'DRAFT',
    submitted_at timestamptz null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint performance_reviews_candidate_cycle_id_fk
        foreign key (candidate_cycle_id)
        references public.candidate_performance_cycles(id)
        on delete restrict,
    constraint performance_reviews_reviewer_user_id_fk
        foreign key (reviewer_user_id)
        references public.users(id)
        on delete restrict,
    constraint performance_reviews_candidate_cycle_type_unique
        unique (candidate_cycle_id, review_type),
    constraint performance_reviews_review_type_check
        check (review_type in ('LEAD', 'HR')),
    constraint performance_reviews_work_quality_score_check
        check (work_quality_score is null or work_quality_score between 0 and 10),
    constraint performance_reviews_role_capability_score_check
        check (role_capability_score is null or role_capability_score between 0 and 5),
    constraint performance_reviews_deadline_delivery_score_check
        check (deadline_delivery_score is null or deadline_delivery_score between 0 and 5),
    constraint performance_reviews_ownership_teamwork_score_check
        check (ownership_teamwork_score is null or ownership_teamwork_score between 0 and 5),
    constraint performance_reviews_communication_professionalism_score_check
        check (
            communication_professionalism_score is null
            or communication_professionalism_score between 0 and 5
        ),
    constraint performance_reviews_attendance_update_discipline_score_check
        check (
            attendance_update_discipline_score is null
            or attendance_update_discipline_score between 0 and 5
        ),
    constraint performance_reviews_reporting_policy_compliance_score_check
        check (
            reporting_policy_compliance_score is null
            or reporting_policy_compliance_score between 0 and 5
        ),
    constraint performance_reviews_type_field_usage_check
        check (
            (
                review_type = 'LEAD'
                and communication_professionalism_score is null
                and attendance_update_discipline_score is null
                and reporting_policy_compliance_score is null
            )
            or (
                review_type = 'HR'
                and work_quality_score is null
                and role_capability_score is null
                and deadline_delivery_score is null
                and ownership_teamwork_score is null
            )
        ),
    constraint performance_reviews_type_total_score_check
        check (
            (
                review_type = 'LEAD'
                and (
                    coalesce(work_quality_score, 0)
                    + coalesce(role_capability_score, 0)
                    + coalesce(deadline_delivery_score, 0)
                    + coalesce(ownership_teamwork_score, 0)
                    + coalesce(communication_professionalism_score, 0)
                    + coalesce(attendance_update_discipline_score, 0)
                    + coalesce(reporting_policy_compliance_score, 0)
                ) between 0 and 25
            )
            or (
                review_type = 'HR'
                and (
                    coalesce(work_quality_score, 0)
                    + coalesce(role_capability_score, 0)
                    + coalesce(deadline_delivery_score, 0)
                    + coalesce(ownership_teamwork_score, 0)
                    + coalesce(communication_professionalism_score, 0)
                    + coalesce(attendance_update_discipline_score, 0)
                    + coalesce(reporting_policy_compliance_score, 0)
                ) between 0 and 15
            )
        ),
    constraint performance_reviews_submitted_scores_complete_check
        check (
            review_status <> 'SUBMITTED'
            or (
                (
                    review_type = 'LEAD'
                    and work_quality_score is not null
                    and role_capability_score is not null
                    and deadline_delivery_score is not null
                    and ownership_teamwork_score is not null
                )
                or (
                    review_type = 'HR'
                    and communication_professionalism_score is not null
                    and attendance_update_discipline_score is not null
                    and reporting_policy_compliance_score is not null
                )
            )
        ),
    constraint performance_reviews_reviewer_comment_not_blank_check
        check (
            reviewer_comment is null
            or btrim(reviewer_comment) <> ''
        ),
    constraint performance_reviews_review_status_check
        check (review_status in ('DRAFT', 'SUBMITTED')),
    constraint performance_reviews_submission_state_check
        check (
            (review_status = 'DRAFT' and submitted_at is null)
            or (review_status = 'SUBMITTED' and submitted_at is not null)
        )
);

comment on table public.performance_reviews is
    'Only one Lead review and one HR review count for each candidate cycle. Reviewer authorization, candidate-pod scope, and cycle-lock enforcement will be added later. Submitted totals will later populate the lead_score and hr_score summary fields in candidate_performance_cycles.';

comment on column public.performance_reviews.review_type is
    'A Lead review contributes up to 25 points, and an HR review contributes up to 15 points.';

comment on column public.performance_reviews.reviewer_user_id is
    'Multiple pod leads may exist, but this stores the logged-in reviewer who submits the review record.';

create index if not exists idx_performance_reviews_reviewer_status
    on public.performance_reviews (reviewer_user_id, review_status);

create index if not exists idx_performance_reviews_review_status
    on public.performance_reviews (review_status);

alter table public.performance_reviews enable row level security;

-- RLS policies will be added separately with the HR PsyConnect permission matrix.
