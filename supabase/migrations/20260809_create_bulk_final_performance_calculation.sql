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
