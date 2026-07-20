create or replace function public.finalize_candidate_cycle_performance(
    p_candidate_cycle_id uuid,
    p_performed_by text
)
returns table (
    old_status text,
    new_status text,
    finalized_at timestamptz
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
    v_existing_finalized_at timestamptz;
    v_finalization_timestamp timestamptz;
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
            v_existing_finalized_at
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    if v_result_status = 'FINALIZED' then
        if v_existing_finalized_at is null then
            raise exception
                'Candidate performance cycle % is FINALIZED but finalized_at is null.',
                p_candidate_cycle_id;
        end if;

        return query
        select
            'FINALIZED'::text,
            'FINALIZED'::text,
            v_existing_finalized_at;
        return;
    end if;

    if v_result_status = 'LOCKED' then
        raise exception
            'Candidate performance cycle % is LOCKED and cannot be finalized again.',
            p_candidate_cycle_id;
    end if;

    if v_result_status <> 'CANDIDATE_REVIEW' then
        raise exception
            'Candidate performance cycle % is not ready for finalization; current status is %.',
            p_candidate_cycle_id,
            v_result_status;
    end if;

    if v_final_score is null then
        raise exception
            'Candidate performance cycle % cannot be finalized because final_score is null.',
            p_candidate_cycle_id;
    end if;

    if v_performance_band is null then
        raise exception
            'Candidate performance cycle % cannot be finalized because performance_band is null.',
            p_candidate_cycle_id;
    end if;

    if v_calculated_at is null then
        raise exception
            'Candidate performance cycle % cannot be finalized because calculated_at is null.',
            p_candidate_cycle_id;
    end if;

    if v_existing_finalized_at is not null then
        raise exception
            'Candidate performance cycle % is CANDIDATE_REVIEW but finalized_at is already set.',
            p_candidate_cycle_id;
    end if;

    v_finalization_timestamp := now();

    update public.candidate_performance_cycles
    set
        result_status = 'FINALIZED',
        finalized_at = v_finalization_timestamp
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
        'PERFORMANCE_FINALIZED',
        'CANDIDATE_REVIEW',
        'FINALIZED',
        'Performance result finalized after internal HR review.',
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'final_score', v_final_score,
            'performance_band', v_performance_band
        ),
        v_performed_by,
        v_finalization_timestamp
    );

    return query
    select
        'CANDIDATE_REVIEW'::text,
        'FINALIZED'::text,
        v_finalization_timestamp;
end;
$function$;

comment on function public.finalize_candidate_cycle_performance(uuid, text) is
    'Finalizes a calculated performance result through an internal HR action and treats CANDIDATE_REVIEW as ready for internal finalization without requiring candidate action. It requires a complete calculated result, sets FINALIZED and finalized_at, inserts one permanent successful audit log, prevents duplicate finalization logs, rejects locked or unready cycles, does not calculate scores or lock cycles, and is safe to run repeatedly.';

revoke execute on function public.finalize_candidate_cycle_performance(uuid, text) from public;
revoke execute on function public.finalize_candidate_cycle_performance(uuid, text) from anon;
revoke execute on function public.finalize_candidate_cycle_performance(uuid, text) from authenticated;
grant execute on function public.finalize_candidate_cycle_performance(uuid, text) to service_role;
