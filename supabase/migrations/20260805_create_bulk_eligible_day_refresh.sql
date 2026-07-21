create or replace function public.bulk_refresh_candidate_cycle_eligible_days(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_eligible_days integer,
    refreshed_eligible_days integer,
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
    v_refreshed_eligible_days integer;
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
                v_assignment.eligible_days::integer,
                v_assignment.eligible_days::integer,
                'SKIPPED'::text,
                format(
                    'Eligible days cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            v_refreshed_eligible_days :=
                public.refresh_candidate_cycle_eligible_days(
                    v_assignment.candidate_cycle_id
                );

            if v_refreshed_eligible_days is null then
                raise exception
                    'Eligible-day refresh returned null for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_eligible_days < 0 then
                raise exception
                    'Eligible-day refresh returned negative value % for candidate performance cycle %.',
                    v_refreshed_eligible_days,
                    v_assignment.candidate_cycle_id;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.eligible_days::integer,
                v_refreshed_eligible_days,
                'REFRESHED'::text,
                case
                    when v_refreshed_eligible_days = v_assignment.eligible_days then
                        'Eligible-day count refreshed and remained unchanged.'::text
                    else
                        format(
                            'Eligible-day count refreshed from %s to %s.',
                            v_assignment.eligible_days,
                            v_refreshed_eligible_days
                        )::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.eligible_days::integer,
                    null::integer,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) is
    'Refreshes eligible working days for every assignment in one performance cycle by reusing the existing single-assignment eligible-day function. It preserves the Sunday, approved-leave, and Work From Home rules, skips finalized and locked results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not refresh scores or statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) to service_role;
