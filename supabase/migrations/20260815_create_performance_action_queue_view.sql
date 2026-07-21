create view public.performance_action_queue_view
with (security_invoker = true)
as
select
    cpdv.candidate_cycle_id::text || ':' || action.action_code as action_key,
    action.action_code,
    action.action_label,
    action.action_owner_scope,
    cpdv.candidate_cycle_id,
    cpdv.candidate_id,
    cpdv.full_name,
    cpdv.email,
    cpdv.applied_role,
    cpdv.role_code,
    cpdv.pod_id,
    cpdv.pod_code,
    cpdv.pod_name,
    cpdv.cycle_id,
    cpdv.cycle_code,
    cpdv.cycle_number,
    cpdv.cycle_start_date,
    cpdv.cycle_end_date,
    cpdv.evaluation_start_date,
    cpdv.evaluation_end_date,
    cpdv.review_open_date,
    cpdv.lock_date,
    cpdv.result_status,
    cpdv.eligible_days,
    cpdv.scored_days,
    cpdv.remaining_scoring_days,
    cpdv.pending_exceptional_count,
    action.due_date,
    (action.due_date - current_date)::integer as days_until_due,
    (current_date > action.due_date) as is_overdue,
    action.action_reason
from public.candidate_performance_detail_view cpdv
cross join lateral (
    select
        'COMPLETE_DAILY_SCORING'::text as action_code,
        'Complete Daily Scoring'::text as action_label,
        'LEAD'::text as action_owner_scope,
        cpdv.evaluation_end_date as due_date,
        format(
            '%s eligible scoring days remain incomplete.',
            cpdv.remaining_scoring_days
        )::text as action_reason
    where cpdv.result_status not in ('FINALIZED', 'LOCKED')
      and cpdv.eligible_days > 0
      and cpdv.remaining_scoring_days > 0
      and current_date >= cpdv.evaluation_start_date

    union all

    select
        'REVIEW_ZERO_ELIGIBLE_DAYS'::text,
        'Review Zero Eligible Days'::text,
        'HR'::text,
        cpdv.review_open_date,
        'This assignment has no eligible scoring days and requires HR review.'::text
    where cpdv.result_status not in ('FINALIZED', 'LOCKED')
      and cpdv.eligible_days = 0
      and cpdv.daily_summary_ready = false
      and cpdv.final_result_ready = false

    union all

    select
        'SUBMIT_LEAD_REVIEW'::text,
        'Submit Lead Review'::text,
        'LEAD'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the Lead review is missing.'::text
    where cpdv.result_status not in ('FINALIZED', 'LOCKED')
      and cpdv.daily_summary_ready = true
      and cpdv.lead_review_ready = false
      and current_date >= cpdv.review_open_date

    union all

    select
        'SUBMIT_HR_REVIEW'::text,
        'Submit HR Review'::text,
        'HR'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the HR review is missing.'::text
    where cpdv.result_status not in ('FINALIZED', 'LOCKED')
      and cpdv.daily_summary_ready = true
      and cpdv.hr_review_ready = false
      and current_date >= cpdv.review_open_date

    union all

    select
        'REVIEW_EXCEPTIONAL_CONTRIBUTIONS'::text,
        'Review Exceptional Contributions'::text,
        'HR'::text,
        cpdv.lock_date,
        format(
            '%s exceptional contributions are awaiting approval or rejection.',
            cpdv.pending_exceptional_count
        )::text
    where cpdv.result_status not in ('FINALIZED', 'LOCKED')
      and cpdv.pending_exceptional_count > 0

    union all

    select
        'CALCULATE_FINAL_PERFORMANCE'::text,
        'Calculate Final Performance'::text,
        'SYSTEM'::text,
        cpdv.lock_date,
        'All four performance components are available, but the final result has not been calculated.'::text
    where cpdv.result_status not in ('FINALIZED', 'LOCKED')
      and cpdv.all_components_ready = true
      and cpdv.final_result_ready = false

    union all

    select
        'FINALIZE_RESULT'::text,
        'Finalize Performance Result'::text,
        'HR'::text,
        cpdv.lock_date,
        'The calculated result is ready for protected finalization.'::text
    where cpdv.ready_for_finalization = true
      and cpdv.result_status = 'CANDIDATE_REVIEW'
      and cpdv.final_result_ready = true

    union all

    select
        'LOCK_RESULT'::text,
        'Lock Finalized Result'::text,
        'HR'::text,
        cpdv.lock_date,
        'The finalized result is ready to be locked against further edits.'::text
    where cpdv.result_status = 'FINALIZED'
      and cpdv.final_result_ready = true
) action;

comment on view public.performance_action_queue_view is
    'Returns one row per outstanding candidate-performance action using the candidate performance detail read model. It supports daily scoring, zero-eligible-day review, Lead review, HR review, exceptional review, final calculation, finalization, and locking actions; uses stable candidate-cycle/action keys; excludes locked results; allows finalized results only for the lock action; uses dynamic due-date and overdue calculations; performs no write action; uses security-invoker behavior; and is intended as the operational action queue after access policies are added.';

revoke all privileges on public.performance_action_queue_view from public;
revoke all privileges on public.performance_action_queue_view from anon;
revoke all privileges on public.performance_action_queue_view from authenticated;
grant select on public.performance_action_queue_view to service_role;
