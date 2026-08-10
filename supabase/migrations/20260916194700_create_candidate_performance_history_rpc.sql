begin;

-- Create a candidate-scoped RPC so a logged-in candidate can fetch their own
-- performance cycle history. Uses current_candidate_id() to resolve the caller
-- from the authenticated session — the candidate never supplies their own id.
-- The function filters candidate_performance_list_view by that resolved id so
-- each candidate sees only their own records.  HR roles are not required.

create or replace function public.get_current_candidate_performance_history()
returns table (
    candidate_cycle_id        uuid,
    cycle_id                  uuid,
    cycle_code                text,
    cycle_number              integer,
    cycle_start_date          date,
    cycle_end_date            date,
    cycle_status              text,
    evaluation_start_date     date,
    evaluation_end_date       date,
    is_partial_cycle          boolean,
    eligible_days             integer,
    scored_days               integer,
    daily_average             numeric,
    daily_component_score     numeric,
    lead_score                numeric,
    hr_score                  numeric,
    exceptional_score         numeric,
    final_score               numeric,
    performance_band          text,
    result_status             text,
    final_result_ready        boolean,
    finalized_at              timestamptz,
    assignment_created_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_candidate_id uuid;
begin
    -- Require an active session with the CANDIDATE role
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(public.current_user_has_role('CANDIDATE'), false) then
        raise insufficient_privilege
            using message = 'Candidate performance history access is not available.';
    end if;

    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate performance history access is not available.';
    end if;

    return query
    select
        cplv.candidate_cycle_id,
        cplv.cycle_id,
        cplv.cycle_code,
        cplv.cycle_number,
        cplv.cycle_start_date,
        cplv.cycle_end_date,
        cplv.cycle_status,
        cplv.evaluation_start_date,
        cplv.evaluation_end_date,
        cplv.is_partial_cycle,
        cplv.eligible_days,
        cplv.scored_days,
        cplv.daily_average,
        cplv.daily_component_score,
        cplv.lead_score,
        cplv.hr_score,
        cplv.exceptional_score,
        cplv.final_score,
        cplv.performance_band,
        cplv.result_status,
        cplv.final_result_ready,
        cplv.finalized_at,
        cplv.assignment_created_at
    from public.candidate_performance_list_view cplv
    where cplv.candidate_id = v_candidate_id
    order by
        cplv.cycle_start_date asc,
        cplv.candidate_cycle_id asc;
end;
$function$;

comment on function public.get_current_candidate_performance_history() is
    'Returns all performance cycle assignments for the current authenticated candidate, resolved server-side via current_candidate_id(). No candidate_id is accepted from the caller. Results are ordered oldest cycle first.';

revoke execute on function public.get_current_candidate_performance_history() from public;
revoke execute on function public.get_current_candidate_performance_history() from anon;
grant execute on function public.get_current_candidate_performance_history() to authenticated;
grant execute on function public.get_current_candidate_performance_history() to service_role;

commit;
