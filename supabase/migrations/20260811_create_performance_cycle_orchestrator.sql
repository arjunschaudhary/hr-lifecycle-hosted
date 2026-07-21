create or replace function public.run_performance_cycle_processing(
    p_cycle_id uuid
)
returns table (
    step_number integer,
    step_name text,
    processed_rows integer,
    successful_rows integer,
    skipped_rows integer,
    failed_rows integer,
    step_outcome text,
    details text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_cycle_start_date date;
    v_cycle_end_date date;
    v_processed_rows integer;
    v_successful_rows integer;
    v_skipped_rows integer;
    v_failed_rows integer;
    v_step_outcome text;
    v_step_details text;
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
    where pc.id = p_cycle_id
    for update;

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

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.assignment_outcome = 'ASSIGNED'
            )::integer,
            count(*) filter (
                where result.assignment_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.assignment_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_assign_candidates_to_performance_cycle(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                1,
                'ASSIGN_CANDIDATES'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_assign_candidates_to_performance_cycle raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_assign_candidates_to_performance_cycle processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_assign_candidates_to_performance_cycle processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_assign_candidates_to_performance_cycle processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        1,
        'ASSIGN_CANDIDATES'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.refresh_outcome = 'REFRESHED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_refresh_candidate_cycle_eligible_days(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                2,
                'REFRESH_ELIGIBLE_DAYS'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_refresh_candidate_cycle_eligible_days raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_refresh_candidate_cycle_eligible_days processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_refresh_candidate_cycle_eligible_days processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_refresh_candidate_cycle_eligible_days processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        2,
        'REFRESH_ELIGIBLE_DAYS'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.refresh_outcome = 'REFRESHED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_refresh_candidate_cycle_daily_summaries(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                3,
                'REFRESH_DAILY_SUMMARIES'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_refresh_candidate_cycle_daily_summaries raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_refresh_candidate_cycle_daily_summaries processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_refresh_candidate_cycle_daily_summaries processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_refresh_candidate_cycle_daily_summaries processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        3,
        'REFRESH_DAILY_SUMMARIES'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.refresh_outcome = 'REFRESHED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_refresh_candidate_cycle_review_summaries(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                4,
                'REFRESH_REVIEW_SUMMARIES'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_refresh_candidate_cycle_review_summaries raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_refresh_candidate_cycle_review_summaries processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_refresh_candidate_cycle_review_summaries processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_refresh_candidate_cycle_review_summaries processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        4,
        'REFRESH_REVIEW_SUMMARIES'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.refresh_outcome = 'REFRESHED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_refresh_candidate_cycle_exceptional_summaries(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                5,
                'REFRESH_EXCEPTIONAL_SUMMARIES'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_refresh_candidate_cycle_exceptional_summaries raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_refresh_candidate_cycle_exceptional_summaries processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_refresh_candidate_cycle_exceptional_summaries processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_refresh_candidate_cycle_exceptional_summaries processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        5,
        'REFRESH_EXCEPTIONAL_SUMMARIES'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.refresh_outcome = 'REFRESHED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_refresh_candidate_cycle_result_statuses(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                6,
                'REFRESH_STATUS_BEFORE_CALCULATION'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_refresh_candidate_cycle_result_statuses raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_refresh_candidate_cycle_result_statuses processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_refresh_candidate_cycle_result_statuses processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_refresh_candidate_cycle_result_statuses processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        6,
        'REFRESH_STATUS_BEFORE_CALCULATION'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.calculation_outcome = 'CALCULATED'
            )::integer,
            count(*) filter (
                where result.calculation_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.calculation_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_calculate_candidate_cycle_final_performance(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                7,
                'CALCULATE_FINAL_PERFORMANCE'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_calculate_candidate_cycle_final_performance raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_calculate_candidate_cycle_final_performance processed %s rows: %s successful, %s skipped, %s failed. Processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_calculate_candidate_cycle_final_performance processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; processing will continue.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_calculate_candidate_cycle_final_performance processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        7,
        'CALCULATE_FINAL_PERFORMANCE'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;

    if v_step_outcome = 'FAILED' then
        return;
    end if;

    begin
        select
            count(*)::integer,
            count(*) filter (
                where result.refresh_outcome = 'REFRESHED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'SKIPPED'
            )::integer,
            count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
        into
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        from public.bulk_refresh_candidate_cycle_result_statuses(
            p_cycle_id
        ) as result;
    exception
        when others then
            return query
            select
                8,
                'REFRESH_STATUS_AFTER_CALCULATION'::text,
                0,
                0,
                0,
                0,
                'FAILED'::text,
                format(
                    'bulk_refresh_candidate_cycle_result_statuses raised an exception: %s. Processing stopped.',
                    sqlerrm
                )::text;
            return;
    end;

    v_step_outcome := case
        when v_failed_rows = 0 then 'SUCCESS'
        when v_failed_rows = v_processed_rows and v_processed_rows > 0 then 'FAILED'
        else 'PARTIAL'
    end;

    v_step_details := case v_step_outcome
        when 'SUCCESS' then format(
            'bulk_refresh_candidate_cycle_result_statuses processed %s rows: %s successful, %s skipped, %s failed. Cycle processing completed.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        when 'PARTIAL' then format(
            'bulk_refresh_candidate_cycle_result_statuses processed %s rows: %s successful, %s skipped, %s failed. Assignment-specific failures occurred; cycle processing completed with partial results.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
        else format(
            'bulk_refresh_candidate_cycle_result_statuses processed %s rows: %s successful, %s skipped, %s failed. All returned rows failed. Processing stopped.',
            v_processed_rows,
            v_successful_rows,
            v_skipped_rows,
            v_failed_rows
        )
    end;

    return query
    select
        8,
        'REFRESH_STATUS_AFTER_CALCULATION'::text,
        v_processed_rows,
        v_successful_rows,
        v_skipped_rows,
        v_failed_rows,
        v_step_outcome,
        v_step_details;
end;
$function$;

comment on function public.run_performance_cycle_processing(uuid) is
    'Orchestrates one complete performance-cycle processing pass by calling the existing bulk functions in the approved order, including status refreshes before and after final calculation. It returns one aggregate summary row per reached step, continues after assignment-specific partial failures, stops after a complete step failure, does not finalize or lock results, is safe to run repeatedly, and is intended for secure server-side or scheduled execution using service_role.';

revoke execute on function public.run_performance_cycle_processing(uuid) from public;
revoke execute on function public.run_performance_cycle_processing(uuid) from anon;
revoke execute on function public.run_performance_cycle_processing(uuid) from authenticated;
grant execute on function public.run_performance_cycle_processing(uuid) to service_role;
