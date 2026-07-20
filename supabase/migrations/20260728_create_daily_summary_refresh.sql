create or replace function public.refresh_candidate_cycle_daily_summary(
    p_candidate_cycle_id uuid
)
returns table (
    scored_days integer,
    daily_average numeric,
    daily_component_score numeric
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_evaluation_start_date date;
    v_evaluation_end_date date;
    v_eligible_days integer;
    v_scored_days integer;
    v_daily_average numeric;
    v_daily_component_score numeric;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.candidate_id,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.eligible_days
        into strict
            v_candidate_id,
            v_evaluation_start_date,
            v_evaluation_end_date,
            v_eligible_days
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    if v_evaluation_start_date is null then
        raise exception
            'Candidate performance cycle % has no evaluation_start_date.',
            p_candidate_cycle_id;
    end if;

    if v_evaluation_end_date is null then
        raise exception
            'Candidate performance cycle % has no evaluation_end_date.',
            p_candidate_cycle_id;
    end if;

    if v_evaluation_end_date < v_evaluation_start_date then
        raise exception
            'Candidate performance cycle % has evaluation_end_date % before evaluation_start_date %.',
            p_candidate_cycle_id,
            v_evaluation_end_date,
            v_evaluation_start_date;
    end if;

    select
        count(*)::integer,
        round(avg(dpe.daily_total)::numeric, 2)
    into
        v_scored_days,
        v_daily_average
    from public.daily_performance_entries dpe
    where dpe.candidate_cycle_id = p_candidate_cycle_id
      and dpe.performance_date between
          v_evaluation_start_date and v_evaluation_end_date
      and extract(isodow from dpe.performance_date) <> 7
      and not exists (
          select 1
          from public.leave_requests lr
          where lr.candidate_id = v_candidate_id
            and lr.leave_status = 'APPROVED'
            and dpe.performance_date between lr.start_date and lr.end_date
            and lower(btrim(lr.leave_type)) <> 'work from home'
      );

    if v_scored_days > v_eligible_days then
        raise exception
            'Calculated scored_days % exceeds eligible_days % for candidate performance cycle %.',
            v_scored_days,
            v_eligible_days,
            p_candidate_cycle_id;
    end if;

    if v_scored_days = 0 then
        v_daily_average := null;
        v_daily_component_score := null;
    else
        v_daily_component_score := round(
            ((v_daily_average + 10) / 20) * 50,
            2
        );
    end if;

    update public.candidate_performance_cycles
    set
        scored_days = v_scored_days,
        daily_average = v_daily_average,
        daily_component_score = v_daily_component_score
    where id = p_candidate_cycle_id;

    return query
    select
        v_scored_days,
        v_daily_average,
        v_daily_component_score;
end;
$function$;

comment on function public.refresh_candidate_cycle_daily_summary(uuid) is
    'Refreshes one candidate cycle valid daily-score summary using dates inside the effective evaluation period. It excludes Sundays and approved actual leave while keeping legacy Work From Home dates scorable, calculates the daily average and converts it to the 50-point component, and updates only the daily summary fields. It does not update result status or final scores and is safe to run repeatedly.';

revoke execute on function public.refresh_candidate_cycle_daily_summary(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_daily_summary(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_daily_summary(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_daily_summary(uuid) to service_role;
