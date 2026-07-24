begin;

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

    if (
        v_final_score is not null
        or v_performance_band is not null
    ) and (
        v_eligible_days <= 0
        or v_scored_days <> v_eligible_days
        or v_daily_component_score is null
    ) then
        raise exception
            'Candidate performance cycle % has stored final performance with incomplete daily scoring (% of % eligible days scored).',
            p_candidate_cycle_id,
            v_scored_days,
            v_eligible_days;
    end if;

    if v_old_status in ('FINALIZED', 'LOCKED') then
        return query
        select
            v_old_status,
            v_old_status;
        return;
    end if;

    v_new_status := case
        when v_final_score is not null
             and v_performance_band is not null
            then 'CANDIDATE_REVIEW'
        when v_eligible_days > 0
             and v_scored_days = v_eligible_days
             and v_daily_component_score is not null
             and v_lead_score is not null
             and v_hr_score is not null
             and v_exceptional_score is not null
             and v_final_score is null
             and v_performance_band is null
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
    v_eligible_days integer;
    v_scored_days integer;
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
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.lead_score,
            cpc.hr_score,
            cpc.exceptional_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at
        into strict
            v_eligible_days,
            v_scored_days,
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

    if v_eligible_days <= 0 then
        raise exception
            'eligible_days must be greater than zero for candidate performance cycle %.',
            p_candidate_cycle_id;
    end if;

    if v_scored_days is distinct from v_eligible_days then
        raise exception
            'Daily scoring is incomplete for candidate performance cycle %: % of % eligible days are scored.',
            p_candidate_cycle_id,
            v_scored_days,
            v_eligible_days;
    end if;

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

create or replace function public.bulk_calculate_candidate_cycle_final_performance(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_final_score numeric,
    calculated_final_score numeric,
    previous_performance_band text,
    calculated_performance_band text,
    calculation_outcome text,
    details text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_cycle_start_date date;
    v_cycle_end_date date;
    v_assignment record;
    v_missing_components text;
    v_calculated_final_score numeric;
    v_calculated_performance_band text;
    v_expected_performance_band text;
begin
    if p_cycle_id is null then
        raise exception 'p_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    select
        pc.start_date,
        pc.end_date
    into
        v_cycle_start_date,
        v_cycle_end_date
    from public.performance_cycles pc
    where pc.id = p_cycle_id;

    if not found then
        raise exception 'Performance cycle % does not exist.', p_cycle_id;
    end if;

    if v_cycle_start_date is null or v_cycle_end_date is null then
        raise exception 'Performance cycle % must have both start_date and end_date.', p_cycle_id;
    end if;

    if v_cycle_start_date > v_cycle_end_date then
        raise exception
            'Performance cycle % has start_date % later than end_date %.',
            p_cycle_id,
            v_cycle_start_date,
            v_cycle_end_date;
    end if;

    for v_assignment in
        select
            cpc.id as candidate_cycle_id,
            cpc.candidate_id,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.lead_score,
            cpc.hr_score,
            cpc.exceptional_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at,
            cpc.result_status
        from public.candidate_performance_cycles cpc
        where cpc.cycle_id = p_cycle_id
        order by
            cpc.candidate_id,
            cpc.id
        for update of cpc
    loop
        if v_assignment.result_status in ('FINALIZED', 'LOCKED') then
            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.final_score::numeric,
                v_assignment.final_score::numeric,
                v_assignment.performance_band::text,
                v_assignment.performance_band::text,
                'SKIPPED'::text,
                format(
                    'Final performance cannot be recalculated because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        if v_assignment.eligible_days <= 0 then
            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.final_score::numeric,
                v_assignment.final_score::numeric,
                v_assignment.performance_band::text,
                v_assignment.performance_band::text,
                'SKIPPED'::text,
                format(
                    'Final performance requires eligible_days greater than zero; current eligible_days is %s.',
                    v_assignment.eligible_days
                )::text;
            continue;
        end if;

        if v_assignment.scored_days
           is distinct from v_assignment.eligible_days then
            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.final_score::numeric,
                v_assignment.final_score::numeric,
                v_assignment.performance_band::text,
                v_assignment.performance_band::text,
                'SKIPPED'::text,
                format(
                    'Incomplete daily scoring: %s of %s eligible days are scored.',
                    v_assignment.scored_days,
                    v_assignment.eligible_days
                )::text;
            continue;
        end if;

        v_missing_components := concat_ws(
            ', ',
            case
                when v_assignment.daily_component_score is null then
                    'daily_component_score'
            end,
            case
                when v_assignment.lead_score is null then
                    'lead_score'
            end,
            case
                when v_assignment.hr_score is null then
                    'hr_score'
            end,
            case
                when v_assignment.exceptional_score is null then
                    'exceptional_score'
            end
        );

        if v_missing_components <> '' then
            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.final_score::numeric,
                v_assignment.final_score::numeric,
                v_assignment.performance_band::text,
                v_assignment.performance_band::text,
                'SKIPPED'::text,
                format(
                    'Missing required components: %s.',
                    v_missing_components
                )::text;
            continue;
        end if;

        begin
            begin
                select
                    calculation.final_score,
                    calculation.performance_band
                into strict
                    v_calculated_final_score,
                    v_calculated_performance_band
                from public.calculate_candidate_cycle_final_performance(
                    v_assignment.candidate_cycle_id
                ) as calculation;
            exception
                when no_data_found then
                    raise exception
                        'Final-performance calculation returned no row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                when too_many_rows then
                    raise exception
                        'Final-performance calculation returned more than one row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
            end;

            if v_calculated_final_score is null then
                raise exception
                    'Final-performance calculation returned null final_score for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_calculated_performance_band is null then
                raise exception
                    'Final-performance calculation returned null performance_band for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_calculated_final_score not between 0 and 100 then
                raise exception
                    'Final-performance calculation returned final_score % outside 0 to 100 for candidate performance cycle %.',
                    v_calculated_final_score,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_calculated_performance_band not in (
                'OUTSTANDING',
                'EXCELLENT',
                'GOOD',
                'IMPROVEMENT_REQUIRED',
                'FORMAL_REVIEW'
            ) then
                raise exception
                    'Final-performance calculation returned invalid performance_band % for candidate performance cycle %.',
                    v_calculated_performance_band,
                    v_assignment.candidate_cycle_id;
            end if;

            v_expected_performance_band := case
                when v_calculated_final_score >= 90 then 'OUTSTANDING'
                when v_calculated_final_score >= 80 then 'EXCELLENT'
                when v_calculated_final_score >= 70 then 'GOOD'
                when v_calculated_final_score >= 50 then 'IMPROVEMENT_REQUIRED'
                else 'FORMAL_REVIEW'
            end;

            if v_calculated_performance_band <> v_expected_performance_band then
                raise exception
                    'Final-performance calculation returned band % inconsistent with final_score % for candidate performance cycle %; expected %.',
                    v_calculated_performance_band,
                    v_calculated_final_score,
                    v_assignment.candidate_cycle_id,
                    v_expected_performance_band;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.final_score::numeric,
                v_calculated_final_score,
                v_assignment.performance_band::text,
                v_calculated_performance_band,
                'CALCULATED'::text,
                case
                    when v_calculated_final_score
                             is not distinct from v_assignment.final_score
                         and v_calculated_performance_band
                             is not distinct from v_assignment.performance_band then
                        'Final performance calculated and remained unchanged.'::text
                    else
                        'Final performance calculated successfully and changed.'::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.final_score::numeric,
                    null::numeric,
                    v_assignment.performance_band::text,
                    null::text,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_calculate_candidate_cycle_final_performance(uuid) is
    'Calculates final performance results for every ready assignment in one performance cycle by reusing the existing single-assignment final-calculation function. It skips assignments with missing components, skips finalized and locked results, uses the approved 100-point formula and performance bands, returns calculated, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not refresh component scores, change statuses, finalize, or lock results, and is safe to run repeatedly.';

revoke execute on function public.bulk_calculate_candidate_cycle_final_performance(uuid) from public;
revoke execute on function public.bulk_calculate_candidate_cycle_final_performance(uuid) from anon;
revoke execute on function public.bulk_calculate_candidate_cycle_final_performance(uuid) from authenticated;
grant execute on function public.bulk_calculate_candidate_cycle_final_performance(uuid) to service_role;

commit;
