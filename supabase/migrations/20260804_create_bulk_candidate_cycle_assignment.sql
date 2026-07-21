create or replace function public.bulk_assign_candidates_to_performance_cycle(
    p_cycle_id uuid
)
returns table (
    candidate_id uuid,
    assignment_id uuid,
    assignment_outcome text,
    details text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_cycle_start_date date;
    v_cycle_end_date date;
    v_candidate record;
    v_internship_end_date date;
    v_existing_assignment_id uuid;
    v_assignment_id uuid;
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

    for v_candidate in
        select
            hl.candidate_id,
            count(*)::integer as eligible_lifecycle_count,
            min(hl.probation_start_date) as probation_start_date,
            min(hl.current_end_date) as current_end_date,
            min(hl.original_end_date) as original_end_date
        from public.hr_lifecycle hl
        where hl.lifecycle_status in (
            'IN_PROBATION',
            'PROBATION_REVIEW',
            'PROBATION_PASSED',
            'PROBATION_EXTENDED',
            'MID_GENERATED',
            'OFFER_LETTER_GENERATED',
            'OFFER_LETTER_SENT',
            'ACTIVE',
            'SIGNED_OFFER_SUBMITTED',
            'SIGNED_OFFER_VERIFIED',
            'MISMATCH_REVIEW'
        )
        group by hl.candidate_id
        order by hl.candidate_id
    loop
        if v_candidate.eligible_lifecycle_count > 1 then
            return query
            select
                v_candidate.candidate_id::uuid,
                null::uuid,
                'FAILED'::text,
                format(
                    'Multiple eligible lifecycle records exist for candidate %s.',
                    v_candidate.candidate_id
                )::text;
            continue;
        end if;

        v_existing_assignment_id := null;

        select cpc.id
        into v_existing_assignment_id
        from public.candidate_performance_cycles cpc
        where cpc.cycle_id = p_cycle_id
          and cpc.candidate_id = v_candidate.candidate_id;

        if found then
            return query
            select
                v_candidate.candidate_id::uuid,
                v_existing_assignment_id,
                'SKIPPED'::text,
                'Candidate is already assigned to this performance cycle.'::text;
            continue;
        end if;

        if v_candidate.probation_start_date is null then
            return query
            select
                v_candidate.candidate_id::uuid,
                null::uuid,
                'FAILED'::text,
                'Candidate probation_start_date is missing.'::text;
            continue;
        end if;

        if v_candidate.current_end_date is null
           and v_candidate.original_end_date is null then
            return query
            select
                v_candidate.candidate_id::uuid,
                null::uuid,
                'FAILED'::text,
                'Candidate current_end_date and original_end_date are both missing.'::text;
            continue;
        end if;

        v_internship_end_date := coalesce(
            v_candidate.current_end_date,
            v_candidate.original_end_date
        );

        if v_internship_end_date < v_candidate.probation_start_date then
            return query
            select
                v_candidate.candidate_id::uuid,
                null::uuid,
                'FAILED'::text,
                format(
                    'Candidate internship end date %s is earlier than probation_start_date %s.',
                    v_internship_end_date,
                    v_candidate.probation_start_date
                )::text;
            continue;
        end if;

        if greatest(v_cycle_start_date, v_candidate.probation_start_date)
           > least(v_cycle_end_date, v_internship_end_date) then
            return query
            select
                v_candidate.candidate_id::uuid,
                null::uuid,
                'SKIPPED'::text,
                'Candidate has no date overlap with this performance cycle.'::text;
            continue;
        end if;

        begin
            v_assignment_id := public.assign_candidate_to_performance_cycle(
                v_candidate.candidate_id,
                p_cycle_id
            );

            if v_assignment_id is null then
                raise exception
                    'Candidate assignment returned no assignment ID for candidate %.',
                    v_candidate.candidate_id;
            end if;

            return query
            select
                v_candidate.candidate_id::uuid,
                v_assignment_id,
                'ASSIGNED'::text,
                'Candidate assigned successfully.'::text;
        exception
            when others then
                return query
                select
                    v_candidate.candidate_id::uuid,
                    null::uuid,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_assign_candidates_to_performance_cycle(uuid) is
    'Assigns all eligible lifecycle candidates to one performance cycle by reusing the existing single-candidate assignment function. It applies the approved lifecycle-status and date-overlap rules, returns assigned, skipped, and failed outcomes per candidate, isolates candidate-specific failures, does not calculate scores or refresh summaries, and is safe to run repeatedly.';

revoke execute on function public.bulk_assign_candidates_to_performance_cycle(uuid) from public;
revoke execute on function public.bulk_assign_candidates_to_performance_cycle(uuid) from anon;
revoke execute on function public.bulk_assign_candidates_to_performance_cycle(uuid) from authenticated;
grant execute on function public.bulk_assign_candidates_to_performance_cycle(uuid) to service_role;
