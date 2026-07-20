create or replace function public.refresh_candidate_cycle_result_status(
    p_candidate_cycle_id uuid
)
returns table (
    old_status text,
    new_status text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_eligible_days integer;
    v_scored_days integer;
    v_daily_component_score numeric;
    v_lead_score numeric;
    v_hr_score numeric;
    v_exceptional_score numeric;
    v_final_score numeric;
    v_performance_band text;
    v_old_status text;
    v_new_status text;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.lead_score,
            cpc.hr_score,
            cpc.exceptional_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.result_status
        into strict
            v_eligible_days,
            v_scored_days,
            v_daily_component_score,
            v_lead_score,
            v_hr_score,
            v_exceptional_score,
            v_final_score,
            v_performance_band,
            v_old_status
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    if v_old_status in ('FINALIZED', 'LOCKED') then
        return query
        select
            v_old_status,
            v_old_status;
        return;
    end if;

    if v_eligible_days < 0 then
        raise exception
            'eligible_days % is negative for candidate performance cycle %.',
            v_eligible_days,
            p_candidate_cycle_id;
    end if;

    if v_scored_days < 0 then
        raise exception
            'scored_days % is negative for candidate performance cycle %.',
            v_scored_days,
            p_candidate_cycle_id;
    end if;

    if v_scored_days > v_eligible_days then
        raise exception
            'scored_days % exceeds eligible_days % for candidate performance cycle %.',
            v_scored_days,
            v_eligible_days,
            p_candidate_cycle_id;
    end if;

    if v_final_score is null and v_performance_band is not null then
        raise exception
            'Candidate performance cycle % has performance_band without final_score.',
            p_candidate_cycle_id;
    end if;

    if v_final_score is not null and v_performance_band is null then
        raise exception
            'Candidate performance cycle % has final_score without performance_band.',
            p_candidate_cycle_id;
    end if;

    v_new_status := case
        when v_final_score is not null
             and v_performance_band is not null
            then 'CANDIDATE_REVIEW'
        when v_daily_component_score is not null
             and v_lead_score is not null
             and v_hr_score is not null
             and v_exceptional_score is not null
             and (
                 v_final_score is null
                 or v_performance_band is null
             )
            then 'READY_TO_CALCULATE'
        when v_eligible_days > 0
             and v_scored_days = v_eligible_days
             and v_daily_component_score is not null
             and (
                 v_lead_score is null
                 or v_hr_score is null
                 or v_exceptional_score is null
             )
            then 'AWAITING_REVIEWS'
        when v_scored_days > 0
             and v_scored_days < v_eligible_days
            then 'DAILY_SCORING'
        else 'PENDING'
    end;

    if v_new_status is distinct from v_old_status then
        update public.candidate_performance_cycles
        set result_status = v_new_status
        where id = p_candidate_cycle_id;
    end if;

    return query
    select
        v_old_status,
        v_new_status;
end;
$function$;

comment on function public.refresh_candidate_cycle_result_status(uuid) is
    'Refreshes one candidate cycle pre-final result status using stored scoring and review results and can advance directly to the appropriate current stage. It does not calculate scores, does not finalize or lock cycles, preserves FINALIZED and LOCKED, updates only result_status, and is safe to run repeatedly.';

revoke execute on function public.refresh_candidate_cycle_result_status(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_result_status(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_result_status(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_result_status(uuid) to service_role;
