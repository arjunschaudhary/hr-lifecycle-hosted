create or replace function public.bulk_refresh_candidate_cycle_exceptional_summaries(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_exceptional_score numeric,
    refreshed_exceptional_score numeric,
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
    v_refreshed_exceptional_score numeric;
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
            cpc.exceptional_score,
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
                v_assignment.exceptional_score::numeric,
                v_assignment.exceptional_score::numeric,
                'SKIPPED'::text,
                format(
                    'Exceptional summary cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            v_refreshed_exceptional_score :=
                public.refresh_candidate_cycle_exceptional_summary(
                    v_assignment.candidate_cycle_id
                );

            if v_refreshed_exceptional_score is null then
                raise exception
                    'Exceptional-summary refresh returned null for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_exceptional_score not between 0 and 10 then
                raise exception
                    'Exceptional-summary refresh returned score % outside 0 to 10 for candidate performance cycle %.',
                    v_refreshed_exceptional_score,
                    v_assignment.candidate_cycle_id;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.exceptional_score::numeric,
                v_refreshed_exceptional_score,
                'REFRESHED'::text,
                case
                    when v_refreshed_exceptional_score
                             is not distinct from v_assignment.exceptional_score then
                        'Exceptional score refreshed and remained unchanged.'::text
                    else
                        'Exceptional score refreshed successfully and changed.'::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.exceptional_score::numeric,
                    null::numeric,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) is
    'Refreshes exceptional-contribution summaries for every assignment in one performance cycle by reusing the existing single-assignment exceptional-summary function. It counts only valid approved contributions, ignores pending and rejected contributions, stores zero when no approved contributions exist, preserves the ten-point cap, skips finalized and locked results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not modify contribution records, calculate final scores, or change statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) to service_role;
