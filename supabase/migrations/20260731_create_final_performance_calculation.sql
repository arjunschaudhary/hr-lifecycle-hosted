create or replace function public.calculate_candidate_cycle_final_performance(
    p_candidate_cycle_id uuid
)
returns table (
    final_score numeric,
    performance_band text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_daily_component_score numeric;
    v_lead_score numeric;
    v_hr_score numeric;
    v_exceptional_score numeric;
    v_existing_final_score numeric;
    v_existing_performance_band text;
    v_existing_calculated_at timestamptz;
    v_final_score numeric;
    v_performance_band text;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.daily_component_score,
            cpc.lead_score,
            cpc.hr_score,
            cpc.exceptional_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at
        into strict
            v_daily_component_score,
            v_lead_score,
            v_hr_score,
            v_exceptional_score,
            v_existing_final_score,
            v_existing_performance_band,
            v_existing_calculated_at
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    if v_daily_component_score is null then
        raise exception
            'daily_component_score is missing for candidate performance cycle %.',
            p_candidate_cycle_id;
    end if;

    if v_lead_score is null then
        raise exception
            'lead_score is missing for candidate performance cycle %.',
            p_candidate_cycle_id;
    end if;

    if v_hr_score is null then
        raise exception
            'hr_score is missing for candidate performance cycle %.',
            p_candidate_cycle_id;
    end if;

    if v_exceptional_score is null then
        raise exception
            'exceptional_score is missing for candidate performance cycle %.',
            p_candidate_cycle_id;
    end if;

    if v_daily_component_score < 0 or v_daily_component_score > 50 then
        raise exception
            'daily_component_score % is outside the allowed range 0 to 50 for candidate performance cycle %.',
            v_daily_component_score,
            p_candidate_cycle_id;
    end if;

    if v_lead_score < 0 or v_lead_score > 25 then
        raise exception
            'lead_score % is outside the allowed range 0 to 25 for candidate performance cycle %.',
            v_lead_score,
            p_candidate_cycle_id;
    end if;

    if v_hr_score < 0 or v_hr_score > 15 then
        raise exception
            'hr_score % is outside the allowed range 0 to 15 for candidate performance cycle %.',
            v_hr_score,
            p_candidate_cycle_id;
    end if;

    if v_exceptional_score < 0 or v_exceptional_score > 10 then
        raise exception
            'exceptional_score % is outside the allowed range 0 to 10 for candidate performance cycle %.',
            v_exceptional_score,
            p_candidate_cycle_id;
    end if;

    v_final_score := round(
        v_daily_component_score
        + v_lead_score
        + v_hr_score
        + v_exceptional_score,
        2
    );

    if v_final_score < 0 or v_final_score > 100 then
        raise exception
            'Calculated final_score % is outside the allowed range 0 to 100 for candidate performance cycle %.',
            v_final_score,
            p_candidate_cycle_id;
    end if;

    v_performance_band := case
        when v_final_score >= 90 then 'OUTSTANDING'
        when v_final_score >= 80 then 'EXCELLENT'
        when v_final_score >= 70 then 'GOOD'
        when v_final_score >= 50 then 'IMPROVEMENT_REQUIRED'
        else 'FORMAL_REVIEW'
    end;

    if v_existing_calculated_at is null
       or v_existing_final_score is distinct from v_final_score
       or v_existing_performance_band is distinct from v_performance_band then
        update public.candidate_performance_cycles
        set
            final_score = v_final_score,
            performance_band = v_performance_band,
            calculated_at = now()
        where id = p_candidate_cycle_id;
    end if;

    return query
    select
        v_final_score,
        v_performance_band;
end;
$function$;

comment on function public.calculate_candidate_cycle_final_performance(uuid) is
    'Calculates the final 100-point performance score, requires all four component scores, and uses the approved performance-band thresholds. It stores the final score and performance band, records the calculation timestamp when the result changes, does not update result status, does not finalize or lock the cycle, does not modify source score records, and is safe to run repeatedly.';

revoke execute on function public.calculate_candidate_cycle_final_performance(uuid) from public;
revoke execute on function public.calculate_candidate_cycle_final_performance(uuid) from anon;
revoke execute on function public.calculate_candidate_cycle_final_performance(uuid) from authenticated;
grant execute on function public.calculate_candidate_cycle_final_performance(uuid) to service_role;
