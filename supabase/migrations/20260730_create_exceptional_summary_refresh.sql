create or replace function public.refresh_candidate_cycle_exceptional_summary(
    p_candidate_cycle_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_locked_candidate_cycle_id uuid;
    v_raw_approved_total numeric;
    v_exceptional_score numeric;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select cpc.id
        into strict v_locked_candidate_cycle_id
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    select coalesce(sum(ec.points), 0)::numeric
    into v_raw_approved_total
    from public.exceptional_contributions ec
    where ec.candidate_cycle_id = p_candidate_cycle_id
      and ec.approval_status = 'APPROVED'
      and ec.reviewed_by_user_id is not null
      and ec.reviewed_at is not null;

    if v_raw_approved_total < 0 then
        raise exception
            'Raw approved exceptional-contribution total % is negative for candidate performance cycle %.',
            v_raw_approved_total,
            p_candidate_cycle_id;
    end if;

    v_exceptional_score := least(v_raw_approved_total, 10);

    update public.candidate_performance_cycles
    set exceptional_score = v_exceptional_score
    where id = p_candidate_cycle_id;

    return v_exceptional_score;
end;
$function$;

comment on function public.refresh_candidate_cycle_exceptional_summary(uuid) is
    'Refreshes approved exceptional-contribution points for one candidate cycle, ignores pending and rejected contributions, includes all approved contribution types, and caps the stored score at ten points while preserving individual contribution records. It stores zero when no approved contributions exist, updates only exceptional_score, does not calculate the final score or update result status, and is safe to run repeatedly.';

revoke execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) to service_role;
