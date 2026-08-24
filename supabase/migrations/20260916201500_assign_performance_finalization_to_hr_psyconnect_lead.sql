begin;

-- Final performance approval is owned by the exact active
-- HR_SITE_CONNECT_LEAD role. Calculation remains automatic, and this
-- operation continues to finalize and lock atomically.
create or replace function public.finalize_and_lock_candidate_performance(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    result_status text,
    final_score numeric,
    performance_band text,
    finalized_at timestamptz,
    locked_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_current_status text;
    v_final_score numeric;
    v_performance_band text;
    v_finalized_at timestamptz;
    v_locked_at timestamptz;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(public.current_user_has_role('HR_SITE_CONNECT_LEAD'), false) then
        raise insufficient_privilege
            using message = 'Performance finalization access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null then
        raise insufficient_privilege
            using message = 'Performance finalization access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.result_status,
            cpc.final_score,
            cpc.performance_band,
            cpc.finalized_at
        into strict
            v_current_status,
            v_final_score,
            v_performance_band,
            v_finalized_at
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle does not exist.'
                using errcode = 'P0001';
    end;

    if v_current_status not in (
        'CANDIDATE_REVIEW',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Performance result is not ready for HR Psyconnect Lead finalization.'
            using errcode = 'P0001';
    end if;

    if v_current_status = 'CANDIDATE_REVIEW' then
        perform *
        from public.finalize_candidate_cycle_performance(
            p_candidate_cycle_id,
            v_actor_user_id::text
        );
    end if;

    select locking.locked_at
    into strict v_locked_at
    from public.lock_candidate_cycle_performance(
        p_candidate_cycle_id,
        v_actor_user_id::text
    ) as locking;

    select
        cpc.result_status,
        cpc.final_score,
        cpc.performance_band,
        cpc.finalized_at
    into strict
        v_current_status,
        v_final_score,
        v_performance_band,
        v_finalized_at
    from public.candidate_performance_cycles cpc
    where cpc.id = p_candidate_cycle_id;

    if v_current_status <> 'LOCKED' then
        raise exception
            'Performance result did not reach LOCKED after finalization.'
            using errcode = 'P0001';
    end if;

    return query
    select
        p_candidate_cycle_id,
        v_current_status,
        v_final_score,
        v_performance_band,
        v_finalized_at,
        v_locked_at;
end;
$function$;

comment on function public.finalize_and_lock_candidate_performance(uuid) is
    'Authenticated exact-HR_SITE_CONNECT_LEAD operation that atomically finalizes a CANDIDATE_REVIEW result and immediately locks it, safely completes locking for an interrupted FINALIZED result, and is repeat-safe for an already LOCKED result. Legacy service-role finalize and lock functions remain unexposed to authenticated users.';

revoke execute on function public.finalize_and_lock_candidate_performance(uuid) from public;
revoke execute on function public.finalize_and_lock_candidate_performance(uuid) from anon;
grant execute on function public.finalize_and_lock_candidate_performance(uuid) to authenticated;
grant execute on function public.finalize_and_lock_candidate_performance(uuid) to service_role;

-- Keep every existing action owner unchanged except FINALIZE_RESULT.
create or replace view public.performance_action_queue_view
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
        'COMPLETE_DAILY_SCORING'::text,
        'Complete Daily Scoring'::text,
        'HR_SITE_CONNECT'::text,
        cpdv.evaluation_end_date,
        format(
            '%s eligible scoring days remain incomplete.',
            cpdv.remaining_scoring_days
        )::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.remaining_scoring_days > 0
      and current_date >= cpdv.evaluation_start_date

    union all

    select
        'SUBMIT_LEAD_REVIEW'::text,
        'Submit Lead Review'::text,
        'LEAD'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the Lead review is missing.'::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.scored_days = cpdv.eligible_days
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
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.scored_days = cpdv.eligible_days
      and cpdv.daily_summary_ready = true
      and cpdv.hr_review_ready = false
      and current_date >= cpdv.review_open_date

    union all

    select
        'SUBMIT_EXCEPTIONAL_SCORE'::text,
        'Submit Exceptional Score'::text,
        'HR'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the explicit Exceptional score is missing.'::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.scored_days = cpdv.eligible_days
      and cpdv.daily_summary_ready = true
      and cpdv.exceptional_summary_ready = false
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
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.pending_exceptional_count > 0

    union all

    select
        'FINALIZE_RESULT'::text,
        'Finalize Performance Result'::text,
        'HR_SITE_CONNECT_LEAD'::text,
        cpdv.lock_date,
        'The calculated result is ready for HR Psyconnect Lead finalization and automatic locking.'::text
    where cpdv.ready_for_finalization = true
      and cpdv.result_status = 'CANDIDATE_REVIEW'
      and cpdv.final_result_ready = true
) action (
    action_code,
    action_label,
    action_owner_scope,
    due_date,
    action_reason
);

comment on view public.performance_action_queue_view is
    'Returns outstanding Daily, Lead, HR, explicit Exceptional-score, exceptional-contribution-review, and HR Psyconnect Lead finalization actions. Calculation and locking are automatic, and NOT_EVALUATED results are terminal and excluded.';

revoke all privileges on public.performance_action_queue_view from public;
revoke all privileges on public.performance_action_queue_view from anon;
revoke all privileges on public.performance_action_queue_view from authenticated;
grant select on public.performance_action_queue_view to service_role;

commit;

