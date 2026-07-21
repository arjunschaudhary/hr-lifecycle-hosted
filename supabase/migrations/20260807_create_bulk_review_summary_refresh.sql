create or replace function public.bulk_refresh_candidate_cycle_review_summaries(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_lead_score numeric,
    refreshed_lead_score numeric,
    previous_hr_score numeric,
    refreshed_hr_score numeric,
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
    v_refreshed_lead_score numeric;
    v_refreshed_hr_score numeric;
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
            cpc.lead_score,
            cpc.hr_score,
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
                v_assignment.lead_score::numeric,
                v_assignment.lead_score::numeric,
                v_assignment.hr_score::numeric,
                v_assignment.hr_score::numeric,
                'SKIPPED'::text,
                format(
                    'Review summary cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            begin
                select
                    summary.lead_score,
                    summary.hr_score
                into strict
                    v_refreshed_lead_score,
                    v_refreshed_hr_score
                from public.refresh_candidate_cycle_review_summary(
                    v_assignment.candidate_cycle_id
                ) as summary;
            exception
                when no_data_found then
                    raise exception
                        'Review-summary refresh returned no row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                when too_many_rows then
                    raise exception
                        'Review-summary refresh returned more than one row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
            end;

            if v_refreshed_lead_score is not null
               and v_refreshed_lead_score not between 0 and 25 then
                raise exception
                    'Review-summary refresh returned Lead score % outside 0 to 25 for candidate performance cycle %.',
                    v_refreshed_lead_score,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_hr_score is not null
               and v_refreshed_hr_score not between 0 and 15 then
                raise exception
                    'Review-summary refresh returned HR score % outside 0 to 15 for candidate performance cycle %.',
                    v_refreshed_hr_score,
                    v_assignment.candidate_cycle_id;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.lead_score::numeric,
                v_refreshed_lead_score,
                v_assignment.hr_score::numeric,
                v_refreshed_hr_score,
                'REFRESHED'::text,
                case
                    when v_refreshed_lead_score
                             is not distinct from v_assignment.lead_score
                         and v_refreshed_hr_score
                             is not distinct from v_assignment.hr_score then
                        'Review summary refreshed and remained unchanged.'::text
                    else
                        'Review summary refreshed successfully and changed.'::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.lead_score::numeric,
                    null::numeric,
                    v_assignment.hr_score::numeric,
                    null::numeric,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) is
    'Refreshes Lead and HR review summaries for every assignment in one performance cycle by reusing the existing single-assignment review-summary function. It counts only submitted reviews, ignores drafts, keeps missing reviews as null, skips finalized and locked results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not modify review records, calculate final scores, or change statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) to service_role;
