create view public.performance_cycle_overview_view
with (security_invoker = true)
as
select
    pc.id as cycle_id,
    pc.cycle_code,
    pc.cycle_number,
    pc.start_date,
    pc.end_date,
    pc.review_open_date,
    pc.lock_date,
    pc.cycle_status,
    count(cpc.id)::integer as assignment_count,
    count(distinct cpc.pod_id)::integer as pod_count,
    count(cpc.id) filter (
        where cpc.is_partial_cycle = true
    )::integer as partial_cycle_count,
    coalesce(sum(cpc.eligible_days), 0)::integer as total_eligible_days,
    coalesce(sum(cpc.scored_days), 0)::integer as total_scored_days,
    case
        when coalesce(sum(cpc.eligible_days), 0) > 0 then
            round(
                coalesce(sum(cpc.scored_days), 0)::numeric
                / coalesce(sum(cpc.eligible_days), 0)::numeric
                * 100,
                2
            )
        else 0::numeric
    end as scoring_completion_percent,
    count(cpc.id) filter (
        where cpc.result_status = 'PENDING'
    )::integer as pending_count,
    count(cpc.id) filter (
        where cpc.result_status = 'DAILY_SCORING'
    )::integer as daily_scoring_count,
    count(cpc.id) filter (
        where cpc.result_status = 'AWAITING_REVIEWS'
    )::integer as awaiting_reviews_count,
    count(cpc.id) filter (
        where cpc.result_status = 'READY_TO_CALCULATE'
    )::integer as ready_to_calculate_count,
    count(cpc.id) filter (
        where cpc.result_status = 'CANDIDATE_REVIEW'
    )::integer as candidate_review_count,
    count(cpc.id) filter (
        where cpc.result_status = 'FINALIZED'
    )::integer as finalized_count,
    count(cpc.id) filter (
        where cpc.result_status = 'LOCKED'
    )::integer as locked_count,
    count(cpc.id) filter (
        where cpc.daily_component_score is not null
    )::integer as daily_summary_ready_count,
    count(cpc.id) filter (
        where cpc.lead_score is not null
    )::integer as lead_review_ready_count,
    count(cpc.id) filter (
        where cpc.hr_score is not null
    )::integer as hr_review_ready_count,
    count(cpc.id) filter (
        where cpc.lead_score is not null
          and cpc.hr_score is not null
    )::integer as review_summary_ready_count,
    count(cpc.id) filter (
        where cpc.exceptional_score is not null
    )::integer as exceptional_summary_ready_count,
    count(cpc.id) filter (
        where cpc.final_score is not null
          and cpc.performance_band is not null
    )::integer as final_result_count,
    round(avg(cpc.final_score), 2)::numeric as average_final_score,
    pc.created_at as cycle_created_at,
    pc.updated_at as cycle_updated_at
from public.performance_cycles pc
left join public.candidate_performance_cycles cpc
    on cpc.cycle_id = pc.id
group by
    pc.id,
    pc.cycle_code,
    pc.cycle_number,
    pc.start_date,
    pc.end_date,
    pc.review_open_date,
    pc.lock_date,
    pc.cycle_status,
    pc.created_at,
    pc.updated_at;

comment on view public.performance_cycle_overview_view is
    'Returns one aggregate row per performance cycle, including cycles with no assignments, and summarizes assignment counts, scoring progress, result statuses, readiness, and calculated results without exposing candidate personal information. It uses security-invoker behavior and is intended as the cycle-level read model for secure backend and frontend use after access policies are added.';

revoke all privileges on public.performance_cycle_overview_view from public;
revoke all privileges on public.performance_cycle_overview_view from anon;
revoke all privileges on public.performance_cycle_overview_view from authenticated;
grant select on public.performance_cycle_overview_view to service_role;
