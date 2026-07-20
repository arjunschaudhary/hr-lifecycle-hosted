create or replace function public.refresh_candidate_cycle_eligible_days(
    p_candidate_cycle_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_evaluation_start_date date;
    v_evaluation_end_date date;
    v_eligible_days integer;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.candidate_id,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date
        into strict
            v_candidate_id,
            v_evaluation_start_date,
            v_evaluation_end_date
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id;
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

    select count(*)::integer
    into v_eligible_days
    from generate_series(
        v_evaluation_start_date::timestamp,
        v_evaluation_end_date::timestamp,
        interval '1 day'
    ) as generated(generated_date)
    where extract(isodow from generated.generated_date) <> 7
      and not exists (
          select 1
          from public.leave_requests lr
          where lr.candidate_id = v_candidate_id
            and lr.leave_status = 'APPROVED'
            and generated.generated_date::date between lr.start_date and lr.end_date
            and lower(btrim(lr.leave_type)) <> 'work from home'
      );

    update public.candidate_performance_cycles
    set eligible_days = v_eligible_days
    where id = p_candidate_cycle_id;

    return v_eligible_days;
end;
$function$;

comment on function public.refresh_candidate_cycle_eligible_days(uuid) is
    'Refreshes eligible working days for one candidate cycle by counting dates inclusively, excluding Sundays and approved actual leave. Legacy Work From Home records remain eligible because remote work is the normal working arrangement. It updates only eligible_days, does not calculate scored days or performance scores, and is safe to run repeatedly.';

revoke execute on function public.refresh_candidate_cycle_eligible_days(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_eligible_days(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_eligible_days(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_eligible_days(uuid) to service_role;
