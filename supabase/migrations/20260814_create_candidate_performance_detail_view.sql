create view public.candidate_performance_detail_view
with (security_invoker = true)
as
select
    cplv.*,
    daily_detail.daily_entry_count,
    daily_detail.daily_entries,
    lead_detail.lead_review,
    hr_detail.hr_review,
    exceptional_detail.exceptional_contribution_count,
    exceptional_detail.pending_exceptional_count,
    exceptional_detail.approved_exceptional_count,
    exceptional_detail.rejected_exceptional_count,
    exceptional_detail.raw_approved_exceptional_points,
    exceptional_detail.exceptional_contributions
from public.candidate_performance_list_view cplv
left join lateral (
    select
        count(dpe.id)::integer as daily_entry_count,
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'id', dpe.id,
                    'performance_date', dpe.performance_date,
                    'work_delivery_score', dpe.work_delivery_score,
                    'communication_responsibility_score',
                        dpe.communication_responsibility_score,
                    'daily_total', dpe.daily_total,
                    'reviewer_user_id', dpe.reviewer_user_id,
                    'reviewer_name', reviewer.name,
                    'reason_code', dpe.reason_code,
                    'reviewer_comment', dpe.reviewer_comment,
                    'submitted_at', dpe.submitted_at,
                    'created_at', dpe.created_at,
                    'updated_at', dpe.updated_at
                )
                order by dpe.performance_date, dpe.id
            ),
            '[]'::jsonb
        ) as daily_entries
    from public.daily_performance_entries dpe
    left join public.users reviewer
        on reviewer.id = dpe.reviewer_user_id
    where dpe.candidate_cycle_id = cplv.candidate_cycle_id
) daily_detail on true
left join lateral (
    select
        jsonb_build_object(
            'id', pr.id,
            'review_type', pr.review_type,
            'reviewer_user_id', pr.reviewer_user_id,
            'reviewer_name', reviewer.name,
            'work_quality_score', pr.work_quality_score,
            'role_capability_score', pr.role_capability_score,
            'deadline_delivery_score', pr.deadline_delivery_score,
            'ownership_teamwork_score', pr.ownership_teamwork_score,
            'communication_professionalism_score',
                pr.communication_professionalism_score,
            'attendance_update_discipline_score',
                pr.attendance_update_discipline_score,
            'reporting_policy_compliance_score',
                pr.reporting_policy_compliance_score,
            'total_score', pr.total_score,
            'reviewer_comment', pr.reviewer_comment,
            'review_status', pr.review_status,
            'submitted_at', pr.submitted_at,
            'created_at', pr.created_at,
            'updated_at', pr.updated_at
        ) as lead_review
    from public.performance_reviews pr
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id
    where pr.candidate_cycle_id = cplv.candidate_cycle_id
      and pr.review_type = 'LEAD'
) lead_detail on true
left join lateral (
    select
        jsonb_build_object(
            'id', pr.id,
            'review_type', pr.review_type,
            'reviewer_user_id', pr.reviewer_user_id,
            'reviewer_name', reviewer.name,
            'work_quality_score', pr.work_quality_score,
            'role_capability_score', pr.role_capability_score,
            'deadline_delivery_score', pr.deadline_delivery_score,
            'ownership_teamwork_score', pr.ownership_teamwork_score,
            'communication_professionalism_score',
                pr.communication_professionalism_score,
            'attendance_update_discipline_score',
                pr.attendance_update_discipline_score,
            'reporting_policy_compliance_score',
                pr.reporting_policy_compliance_score,
            'total_score', pr.total_score,
            'reviewer_comment', pr.reviewer_comment,
            'review_status', pr.review_status,
            'submitted_at', pr.submitted_at,
            'created_at', pr.created_at,
            'updated_at', pr.updated_at
        ) as hr_review
    from public.performance_reviews pr
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id
    where pr.candidate_cycle_id = cplv.candidate_cycle_id
      and pr.review_type = 'HR'
) hr_detail on true
left join lateral (
    select
        count(ec.id)::integer as exceptional_contribution_count,
        count(ec.id) filter (
            where ec.approval_status = 'PENDING'
        )::integer as pending_exceptional_count,
        count(ec.id) filter (
            where ec.approval_status = 'APPROVED'
        )::integer as approved_exceptional_count,
        count(ec.id) filter (
            where ec.approval_status = 'REJECTED'
        )::integer as rejected_exceptional_count,
        coalesce(
            sum(ec.points) filter (
                where ec.approval_status = 'APPROVED'
                  and ec.reviewed_by_user_id is not null
                  and ec.reviewed_at is not null
            ),
            0
        )::integer as raw_approved_exceptional_points,
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'id', ec.id,
                    'contribution_type', ec.contribution_type,
                    'title', ec.title,
                    'description', ec.description,
                    'points', ec.points,
                    'evidence_url', ec.evidence_url,
                    'source_type', ec.source_type,
                    'external_reference_id', ec.external_reference_id,
                    'submitted_by_user_id', ec.submitted_by_user_id,
                    'submitted_by_name', submitter.name,
                    'approval_status', ec.approval_status,
                    'reviewed_by_user_id', ec.reviewed_by_user_id,
                    'reviewed_by_name', reviewer.name,
                    'reviewed_at', ec.reviewed_at,
                    'review_notes', ec.review_notes,
                    'created_at', ec.created_at,
                    'updated_at', ec.updated_at
                )
                order by ec.created_at, ec.id
            ),
            '[]'::jsonb
        ) as exceptional_contributions
    from public.exceptional_contributions ec
    left join public.users submitter
        on submitter.id = ec.submitted_by_user_id
    left join public.users reviewer
        on reviewer.id = ec.reviewed_by_user_id
    where ec.candidate_cycle_id = cplv.candidate_cycle_id
) exceptional_detail on true;

comment on view public.candidate_performance_detail_view is
    'Returns one detailed row per candidate performance-cycle assignment by extending the candidate performance list view with ordered JSONB daily scoring history, separate Lead and HR review objects, and exceptional-contribution counts, raw approved points, and history. It exposes user names but not user email addresses, prevents detail-table row multiplication through aggregate and uniqueness-backed lateral subqueries, uses security-invoker behavior, and is intended as the detailed performance read model after access policies are added.';

revoke all privileges on public.candidate_performance_detail_view from public;
revoke all privileges on public.candidate_performance_detail_view from anon;
revoke all privileges on public.candidate_performance_detail_view from authenticated;
grant select on public.candidate_performance_detail_view to service_role;
