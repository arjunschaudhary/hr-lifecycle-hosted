create or replace function public.bulk_refresh_candidate_cycle_result_statuses(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_status text,
    refreshed_status text,
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
    v_returned_old_status text;
    v_returned_new_status text;
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
                v_assignment.result_status::text,
                v_assignment.result_status::text,
                'SKIPPED'::text,
                format(
                    'Result status cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            begin
                select
                    status_refresh.old_status,
                    status_refresh.new_status
                into strict
                    v_returned_old_status,
                    v_returned_new_status
                from public.refresh_candidate_cycle_result_status(
                    v_assignment.candidate_cycle_id
                ) as status_refresh;
            exception
                when no_data_found then
                    raise exception
                        'Result-status refresh returned no row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                when too_many_rows then
                    raise exception
                        'Result-status refresh returned more than one row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
            end;

            if v_returned_old_status is null then
                raise exception
                    'Result-status refresh returned null old_status for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_returned_new_status is null then
                raise exception
                    'Result-status refresh returned null new_status for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_returned_old_status is distinct from v_assignment.result_status then
                raise exception
                    'Result-status refresh returned old_status % inconsistent with locked status % for candidate performance cycle %.',
                    v_returned_old_status,
                    v_assignment.result_status,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_returned_new_status not in (
                'PENDING',
                'DAILY_SCORING',
                'AWAITING_REVIEWS',
                'READY_TO_CALCULATE',
                'CANDIDATE_REVIEW',
                'FINALIZED',
                'LOCKED'
            ) then
                raise exception
                    'Result-status refresh returned invalid new_status % for candidate performance cycle %.',
                    v_returned_new_status,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_returned_new_status in ('FINALIZED', 'LOCKED') then
                raise exception
                    'Result-status refresh unexpectedly returned protected new_status % for candidate performance cycle %.',
                    v_returned_new_status,
                    v_assignment.candidate_cycle_id;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.result_status::text,
                v_returned_new_status,
                'REFRESHED'::text,
                case
                    when v_returned_new_status = v_assignment.result_status then
                        'Result status refreshed and remained unchanged.'::text
                    else
                        format(
                            'Result status refreshed from %s to %s.',
                            v_assignment.result_status,
                            v_returned_new_status
                        )::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.result_status::text,
                    null::text,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) is
    'Refreshes result statuses for every assignment in one performance cycle by reusing the existing single-assignment status-refresh function. It applies the approved status-priority rules, skips finalized and locked results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not refresh scores, calculate results, finalize, or lock assignments, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) to service_role;
