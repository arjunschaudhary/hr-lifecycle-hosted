create or replace function public.bulk_refresh_candidate_cycle_daily_summaries(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_scored_days integer,
    refreshed_scored_days integer,
    previous_daily_average numeric,
    refreshed_daily_average numeric,
    previous_daily_component_score numeric,
    refreshed_daily_component_score numeric,
    refresh_outcome text,
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
    v_refreshed_scored_days integer;
    v_refreshed_daily_average numeric;
    v_refreshed_daily_component_score numeric;
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
            cpc.daily_average,
            cpc.daily_component_score,
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
                v_assignment.scored_days::integer,
                v_assignment.scored_days::integer,
                v_assignment.daily_average::numeric,
                v_assignment.daily_average::numeric,
                v_assignment.daily_component_score::numeric,
                v_assignment.daily_component_score::numeric,
                'SKIPPED'::text,
                format(
                    'Daily summary cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            begin
                select
                    summary.scored_days,
                    summary.daily_average,
                    summary.daily_component_score
                into strict
                    v_refreshed_scored_days,
                    v_refreshed_daily_average,
                    v_refreshed_daily_component_score
                from public.refresh_candidate_cycle_daily_summary(
                    v_assignment.candidate_cycle_id
                ) as summary;
            exception
                when no_data_found then
                    raise exception
                        'Daily-summary refresh returned no row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                when too_many_rows then
                    raise exception
                        'Daily-summary refresh returned more than one row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
            end;

            if v_refreshed_scored_days is null then
                raise exception
                    'Daily-summary refresh returned null scored_days for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_scored_days < 0 then
                raise exception
                    'Daily-summary refresh returned negative scored_days % for candidate performance cycle %.',
                    v_refreshed_scored_days,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_scored_days > v_assignment.eligible_days then
                raise exception
                    'Daily-summary refresh returned scored_days % greater than eligible_days % for candidate performance cycle %.',
                    v_refreshed_scored_days,
                    v_assignment.eligible_days,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_scored_days = 0 then
                if v_refreshed_daily_average is not null
                   or v_refreshed_daily_component_score is not null then
                    raise exception
                        'Daily-summary refresh returned score values for zero scored days on candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                end if;
            else
                if v_refreshed_daily_average is null
                   or v_refreshed_daily_component_score is null then
                    raise exception
                        'Daily-summary refresh returned incomplete score values for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                end if;

                if v_refreshed_daily_average not between -10 and 10 then
                    raise exception
                        'Daily-summary refresh returned daily_average % outside -10 to 10 for candidate performance cycle %.',
                        v_refreshed_daily_average,
                        v_assignment.candidate_cycle_id;
                end if;

                if v_refreshed_daily_component_score not between 0 and 50 then
                    raise exception
                        'Daily-summary refresh returned daily_component_score % outside 0 to 50 for candidate performance cycle %.',
                        v_refreshed_daily_component_score,
                        v_assignment.candidate_cycle_id;
                end if;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.scored_days::integer,
                v_refreshed_scored_days,
                v_assignment.daily_average::numeric,
                v_refreshed_daily_average,
                v_assignment.daily_component_score::numeric,
                v_refreshed_daily_component_score,
                'REFRESHED'::text,
                case
                    when v_refreshed_scored_days = v_assignment.scored_days
                         and v_refreshed_daily_average
                             is not distinct from v_assignment.daily_average
                         and v_refreshed_daily_component_score
                             is not distinct from v_assignment.daily_component_score then
                        'Daily summary refreshed and remained unchanged.'::text
                    else
                        'Daily summary refreshed successfully and changed.'::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.scored_days::integer,
                    null::integer,
                    v_assignment.daily_average::numeric,
                    null::numeric,
                    v_assignment.daily_component_score::numeric,
                    null::numeric,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) is
    'Refreshes daily-performance summaries for every assignment in one performance cycle by reusing the existing single-assignment daily-summary function. It preserves evaluation-date, Sunday, approved-leave, and Work From Home rules, skips finalized and locked results, returns refreshed, skipped, and failed outcomes per assignment, treats zero valid daily entries as a successful null-score summary, isolates assignment-specific failures, does not refresh eligible days, reviews, final scores, or statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) to service_role;
