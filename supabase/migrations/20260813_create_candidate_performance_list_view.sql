create view public.candidate_performance_list_view
with (security_invoker = true)
as
select
    cpc.id as candidate_cycle_id,
    cpc.cycle_id,
    pc.cycle_code,
    pc.cycle_number,
    pc.start_date as cycle_start_date,
    pc.end_date as cycle_end_date,
    pc.review_open_date,
    pc.lock_date,
    pc.cycle_status,
    cpc.candidate_id,
    mc.full_name,
    mc.email,
    mc.applied_role,
    mc.role_code,
    mc.department,
    cpc.pod_id,
    p.pod_code,
    p.pod_name,
    cpc.evaluation_start_date,
    cpc.evaluation_end_date,
    cpc.is_partial_cycle,
    cpc.eligible_days,
    cpc.scored_days,
    greatest(cpc.eligible_days - cpc.scored_days, 0)::integer
        as remaining_scoring_days,
    case
        when cpc.eligible_days > 0 then
            round(
                cpc.scored_days::numeric
                / cpc.eligible_days::numeric
                * 100,
                2
            )
        else 0::numeric
    end as scoring_completion_percent,
    cpc.daily_average,
    cpc.daily_component_score,
    cpc.lead_score,
    cpc.hr_score,
    cpc.exceptional_score,
    cpc.final_score,
    cpc.performance_band,
    cpc.result_status,
    (cpc.daily_component_score is not null) as daily_summary_ready,
    (cpc.lead_score is not null) as lead_review_ready,
    (cpc.hr_score is not null) as hr_review_ready,
    (cpc.exceptional_score is not null) as exceptional_summary_ready,
    (
        cpc.daily_component_score is not null
        and cpc.lead_score is not null
        and cpc.hr_score is not null
        and cpc.exceptional_score is not null
    ) as all_components_ready,
    (
        cpc.final_score is not null
        and cpc.performance_band is not null
    ) as final_result_ready,
    (cpc.result_status = 'CANDIDATE_REVIEW') as ready_for_finalization,
    (cpc.result_status in ('FINALIZED', 'LOCKED')) as is_protected,
    cpc.calculated_at,
    cpc.finalized_at,
    cpc.created_at as assignment_created_at,
    cpc.updated_at as assignment_updated_at
from public.candidate_performance_cycles cpc
join public.performance_cycles pc
    on pc.id = cpc.cycle_id
join public.master_candidates mc
    on mc.candidate_id = cpc.candidate_id
join public.pods p
    on p.id = cpc.pod_id;

comment on view public.candidate_performance_list_view is
    'Returns one operational row per candidate performance-cycle assignment and combines cycle, candidate, pod, scoring, review, result-summary, readiness, and protected-state fields. It does not join hr_lifecycle because candidate lifecycle uniqueness is not database-enforced, does not expose unnecessary candidate personal information, uses security-invoker behavior, and is intended as the candidate-level performance list read model after access policies are added.';

revoke all privileges on public.candidate_performance_list_view from public;
revoke all privileges on public.candidate_performance_list_view from anon;
revoke all privileges on public.candidate_performance_list_view from authenticated;
grant select on public.candidate_performance_list_view to service_role;
