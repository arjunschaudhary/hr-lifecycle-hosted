create or replace function public.assign_candidate_to_performance_cycle(
    p_candidate_id uuid,
    p_cycle_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_cycle_start_date date;
    v_cycle_end_date date;
    v_joining_date date;
    v_current_end_date date;
    v_original_end_date date;
    v_internship_end_date date;
    v_effective_start_date date;
    v_effective_end_date date;
    v_is_partial_cycle boolean;
    v_pod_id uuid;
    v_assignment_id uuid;
begin
    if p_candidate_id is null then
        raise exception 'p_candidate_id must not be null.'
            using errcode = '22004';
    end if;

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

    select cpc.id
    into v_assignment_id
    from public.candidate_performance_cycles cpc
    where cpc.cycle_id = p_cycle_id
      and cpc.candidate_id = p_candidate_id;

    if found then
        return v_assignment_id;
    end if;

    begin
        select
            hl.probation_start_date,
            hl.current_end_date,
            hl.original_end_date
        into strict
            v_joining_date,
            v_current_end_date,
            v_original_end_date
        from public.hr_lifecycle hl
        where hl.candidate_id = p_candidate_id;
    exception
        when no_data_found then
            raise exception 'Lifecycle record does not exist for candidate %.', p_candidate_id;
        when too_many_rows then
            raise exception 'Multiple lifecycle records exist for candidate %.', p_candidate_id;
    end;

    if v_joining_date is null then
        raise exception 'Candidate % has no probation_start_date.', p_candidate_id;
    end if;

    if v_current_end_date is null and v_original_end_date is null then
        raise exception
            'Candidate % has neither current_end_date nor original_end_date.',
            p_candidate_id;
    end if;

    v_internship_end_date := coalesce(v_current_end_date, v_original_end_date);

    if v_internship_end_date < v_joining_date then
        raise exception
            'Candidate % internship end date % is earlier than joining date %.',
            p_candidate_id,
            v_internship_end_date,
            v_joining_date;
    end if;

    v_effective_start_date := greatest(v_cycle_start_date, v_joining_date);
    v_effective_end_date := least(v_cycle_end_date, v_internship_end_date);

    if v_effective_start_date > v_effective_end_date then
        raise exception
            'Candidate % has no date overlap with performance cycle %.',
            p_candidate_id,
            p_cycle_id;
    end if;

    v_is_partial_cycle :=
        v_effective_start_date <> v_cycle_start_date
        or v_effective_end_date <> v_cycle_end_date;

    select pm.pod_id
    into v_pod_id
    from public.pod_memberships pm
    where pm.candidate_id = p_candidate_id
      and pm.membership_type = 'CANDIDATE'
      and pm.effective_from <= v_effective_start_date
      and (
          pm.effective_to is null
          or pm.effective_to >= v_effective_start_date
      )
    order by
        pm.effective_from desc,
        pm.created_at desc,
        pm.id desc
    limit 1;

    if not found then
        raise exception
            'No valid candidate pod membership exists for candidate % on %.',
            p_candidate_id,
            v_effective_start_date;
    end if;

    insert into public.candidate_performance_cycles (
        cycle_id,
        candidate_id,
        pod_id,
        evaluation_start_date,
        evaluation_end_date,
        is_partial_cycle
    )
    values (
        p_cycle_id,
        p_candidate_id,
        v_pod_id,
        v_effective_start_date,
        v_effective_end_date,
        v_is_partial_cycle
    )
    on conflict (cycle_id, candidate_id) do nothing
    returning id into v_assignment_id;

    if v_assignment_id is null then
        select cpc.id
        into v_assignment_id
        from public.candidate_performance_cycles cpc
        where cpc.cycle_id = p_cycle_id
          and cpc.candidate_id = p_candidate_id;
    end if;

    return v_assignment_id;
end;
$function$;

comment on function public.assign_candidate_to_performance_cycle(uuid, uuid) is
    'Assigns one candidate to one existing company cycle. It uses probation_start_date as the V1 joining date and the current or original internship end date, creates partial periods for mid-cycle joining or completion, stores a pod snapshot, and is idempotent. It does not calculate Sundays, approved leave, eligible days, daily scores, review scores, exceptional points, or final results.';

revoke execute on function public.assign_candidate_to_performance_cycle(uuid, uuid) from public;
revoke execute on function public.assign_candidate_to_performance_cycle(uuid, uuid) from anon;
revoke execute on function public.assign_candidate_to_performance_cycle(uuid, uuid) from authenticated;
grant execute on function public.assign_candidate_to_performance_cycle(uuid, uuid) to service_role;
