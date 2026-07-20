create or replace function public.lock_candidate_cycle_performance(
    p_candidate_cycle_id uuid,
    p_performed_by text
)
returns table (
    old_status text,
    new_status text,
    locked_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_final_score numeric;
    v_performance_band text;
    v_result_status text;
    v_calculated_at timestamptz;
    v_finalized_at timestamptz;
    v_lock_timestamp timestamptz;
    v_performed_by text;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    if p_performed_by is null or btrim(p_performed_by) = '' then
        raise exception 'p_performed_by must not be null or blank.'
            using errcode = '22004';
    end if;

    v_performed_by := btrim(p_performed_by);

    begin
        select
            cpc.candidate_id,
            cpc.final_score,
            cpc.performance_band,
            cpc.result_status,
            cpc.calculated_at,
            cpc.finalized_at
        into strict
            v_candidate_id,
            v_final_score,
            v_performance_band,
            v_result_status,
            v_calculated_at,
            v_finalized_at
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    if v_result_status = 'LOCKED' then
        select hal.performed_at
        into v_lock_timestamp
        from public.hr_activity_logs hal
        where hal.candidate_id = v_candidate_id
          and hal.activity_type = 'PERFORMANCE_LOCKED'
          and hal.activity_status = 'SUCCESS'
          and hal.metadata ->> 'candidate_cycle_id' = p_candidate_cycle_id::text
        order by hal.performed_at desc
        limit 1;

        if not found or v_lock_timestamp is null then
            raise exception
                'Candidate performance cycle % is LOCKED but has no successful lock audit log.',
                p_candidate_cycle_id;
        end if;

        return query
        select
            'LOCKED'::text,
            'LOCKED'::text,
            v_lock_timestamp;
        return;
    end if;

    if v_result_status <> 'FINALIZED' then
        raise exception
            'Candidate performance cycle % cannot be locked because only a FINALIZED cycle is eligible; current status is %.',
            p_candidate_cycle_id,
            v_result_status;
    end if;

    if v_final_score is null then
        raise exception
            'Candidate performance cycle % cannot be locked because final_score is null.',
            p_candidate_cycle_id;
    end if;

    if v_performance_band is null then
        raise exception
            'Candidate performance cycle % cannot be locked because performance_band is null.',
            p_candidate_cycle_id;
    end if;

    if v_calculated_at is null then
        raise exception
            'Candidate performance cycle % cannot be locked because calculated_at is null.',
            p_candidate_cycle_id;
    end if;

    if v_finalized_at is null then
        raise exception
            'Candidate performance cycle % cannot be locked because finalized_at is null.',
            p_candidate_cycle_id;
    end if;

    v_lock_timestamp := now();

    update public.candidate_performance_cycles
    set result_status = 'LOCKED'
    where id = p_candidate_cycle_id;

    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        from_status,
        to_status,
        remarks,
        activity_status,
        error_message,
        metadata,
        performed_by,
        performed_at
    )
    values (
        v_candidate_id,
        'PERFORMANCE_LOCKED',
        'FINALIZED',
        'LOCKED',
        'Finalized performance result permanently locked for normal editing.',
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'final_score', v_final_score,
            'performance_band', v_performance_band,
            'finalized_at', v_finalized_at
        ),
        v_performed_by,
        v_lock_timestamp
    );

    return query
    select
        'FINALIZED'::text,
        'LOCKED'::text,
        v_lock_timestamp;
end;
$function$;

comment on function public.lock_candidate_cycle_performance(uuid, text) is
    'Locks a previously finalized performance result through an internal action, preserves the finalization timestamp and calculated result, and creates one permanent successful audit log. It rejects earlier statuses, prevents duplicate lock logs, does not calculate or finalize the result, and is safe to run repeatedly.';

revoke execute on function public.lock_candidate_cycle_performance(uuid, text) from public;
revoke execute on function public.lock_candidate_cycle_performance(uuid, text) from anon;
revoke execute on function public.lock_candidate_cycle_performance(uuid, text) from authenticated;
grant execute on function public.lock_candidate_cycle_performance(uuid, text) to service_role;

create or replace function public.prevent_locked_candidate_cycle_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
    if old.result_status = 'LOCKED' then
        raise exception
            'Cannot % candidate performance cycle % because the cycle is LOCKED.',
            lower(tg_op),
            old.id;
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$function$;

comment on function public.prevent_locked_candidate_cycle_changes() is
    'Prevents every update and deletion after a candidate cycle reaches LOCKED, allows the initial FINALIZED-to-LOCKED transition, and prevents reopening or editing a locked result.';

revoke execute on function public.prevent_locked_candidate_cycle_changes() from public;
revoke execute on function public.prevent_locked_candidate_cycle_changes() from anon;
revoke execute on function public.prevent_locked_candidate_cycle_changes() from authenticated;

create or replace function public.prevent_locked_performance_record_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_old_candidate_cycle_id uuid;
    v_new_candidate_cycle_id uuid;
    v_cycle record;
begin
    if tg_op = 'INSERT' then
        v_new_candidate_cycle_id := new.candidate_cycle_id;
    elsif tg_op = 'DELETE' then
        v_old_candidate_cycle_id := old.candidate_cycle_id;
    else
        v_old_candidate_cycle_id := old.candidate_cycle_id;
        v_new_candidate_cycle_id := new.candidate_cycle_id;
    end if;

    for v_cycle in
        select
            cpc.id,
            cpc.result_status
        from public.candidate_performance_cycles cpc
        where cpc.id = v_old_candidate_cycle_id
           or cpc.id = v_new_candidate_cycle_id
        order by cpc.id
        for share
    loop
        if v_cycle.result_status = 'LOCKED' then
            raise exception
                'Cannot % row in %.% for candidate cycle % because the cycle is LOCKED.',
                lower(tg_op),
                tg_table_schema,
                tg_table_name,
                v_cycle.id;
        end if;
    end loop;

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$function$;

comment on function public.prevent_locked_performance_record_changes() is
    'Prevents insertion, update, movement, or deletion of score-source records connected to a locked candidate cycle. It applies to daily entries, performance reviews, and exceptional contributions.';

revoke execute on function public.prevent_locked_performance_record_changes() from public;
revoke execute on function public.prevent_locked_performance_record_changes() from anon;
revoke execute on function public.prevent_locked_performance_record_changes() from authenticated;

drop trigger if exists protect_locked_candidate_performance_cycle
    on public.candidate_performance_cycles;

create trigger protect_locked_candidate_performance_cycle
before update or delete on public.candidate_performance_cycles
for each row
execute function public.prevent_locked_candidate_cycle_changes();

drop trigger if exists protect_locked_daily_performance_entries
    on public.daily_performance_entries;

create trigger protect_locked_daily_performance_entries
before insert or update or delete on public.daily_performance_entries
for each row
execute function public.prevent_locked_performance_record_changes();

drop trigger if exists protect_locked_performance_reviews
    on public.performance_reviews;

create trigger protect_locked_performance_reviews
before insert or update or delete on public.performance_reviews
for each row
execute function public.prevent_locked_performance_record_changes();

drop trigger if exists protect_locked_exceptional_contributions
    on public.exceptional_contributions;

create trigger protect_locked_exceptional_contributions
before insert or update or delete on public.exceptional_contributions
for each row
execute function public.prevent_locked_performance_record_changes();
