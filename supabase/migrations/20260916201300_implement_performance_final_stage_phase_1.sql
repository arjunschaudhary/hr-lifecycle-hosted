begin;

alter table public.candidate_performance_cycles
    drop constraint if exists candidate_performance_cycles_result_status_check;

alter table public.candidate_performance_cycles
    add constraint candidate_performance_cycles_result_status_check
    check (
        result_status in (
            'PENDING',
            'DAILY_SCORING',
            'AWAITING_REVIEWS',
            'READY_TO_CALCULATE',
            'CANDIDATE_REVIEW',
            'FINALIZED',
            'LOCKED',
            'NOT_EVALUATED'
        )
    );

create or replace function public.prevent_locked_candidate_cycle_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
    if old.result_status in ('LOCKED', 'NOT_EVALUATED') then
        raise exception
            'Cannot % candidate performance cycle % because the result is terminal (%).',
            lower(tg_op),
            old.id,
            old.result_status;
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$function$;

comment on function public.prevent_locked_candidate_cycle_changes() is
    'Prevents every update and deletion after a candidate cycle reaches LOCKED or NOT_EVALUATED, allows the initial transition into either terminal state, and prevents reopening or editing a terminal result.';

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
        if v_cycle.result_status in ('LOCKED', 'NOT_EVALUATED') then
            raise exception
                'Cannot % row in %.% for candidate cycle % because the result is terminal (%).',
                lower(tg_op),
                tg_table_schema,
                tg_table_name,
                v_cycle.id,
                v_cycle.result_status;
        end if;
    end loop;

    if tg_op = 'DELETE' then
        return old;
    end if;

    return new;
end;
$function$;

comment on function public.prevent_locked_performance_record_changes() is
    'Prevents insertion, update, movement, or deletion of score-source records connected to a LOCKED or NOT_EVALUATED candidate cycle. It applies to daily entries, performance reviews, and exceptional contributions.';

revoke execute on function public.prevent_locked_performance_record_changes() from public;
revoke execute on function public.prevent_locked_performance_record_changes() from anon;
revoke execute on function public.prevent_locked_performance_record_changes() from authenticated;

create or replace function public.refresh_candidate_cycle_result_status(
    p_candidate_cycle_id uuid
)
returns table (
    old_status text,
    new_status text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_review_open_date date;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_eligible_days integer;
    v_scored_days integer;
    v_daily_average numeric;
    v_daily_component_score numeric;
    v_lead_score numeric;
    v_hr_score numeric;
    v_exceptional_score numeric;
    v_final_score numeric;
    v_performance_band text;
    v_calculated_at timestamptz;
    v_finalized_at timestamptz;
    v_old_status text;
    v_new_status text;
    v_transition_timestamp timestamptz;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.candidate_id,
            pc.review_open_date,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_average,
            cpc.daily_component_score,
            cpc.lead_score,
            cpc.hr_score,
            cpc.exceptional_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at,
            cpc.finalized_at,
            cpc.result_status
        into strict
            v_candidate_id,
            v_review_open_date,
            v_eligible_days,
            v_scored_days,
            v_daily_average,
            v_daily_component_score,
            v_lead_score,
            v_hr_score,
            v_exceptional_score,
            v_final_score,
            v_performance_band,
            v_calculated_at,
            v_finalized_at,
            v_old_status
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
          on pc.id = cpc.cycle_id
        where cpc.id = p_candidate_cycle_id
        for update of cpc;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    if v_eligible_days < 0 then
        raise exception
            'eligible_days % is negative for candidate performance cycle %.',
            v_eligible_days,
            p_candidate_cycle_id;
    end if;

    if v_scored_days < 0 then
        raise exception
            'scored_days % is negative for candidate performance cycle %.',
            v_scored_days,
            p_candidate_cycle_id;
    end if;

    if v_scored_days > v_eligible_days then
        raise exception
            'scored_days % exceeds eligible_days % for candidate performance cycle %.',
            v_scored_days,
            v_eligible_days,
            p_candidate_cycle_id;
    end if;

    if v_old_status = 'NOT_EVALUATED' then
        if v_eligible_days <> 0
           or v_scored_days <> 0
           or v_daily_average is not null
           or v_daily_component_score is not null
           or v_lead_score is not null
           or v_hr_score is not null
           or v_exceptional_score is not null
           or v_final_score is not null
           or v_performance_band is not null
           or v_calculated_at is not null
           or v_finalized_at is not null then
            raise exception
                'Candidate performance cycle % has an invalid NOT_EVALUATED result payload.',
                p_candidate_cycle_id;
        end if;

        return query select v_old_status, v_old_status;
        return;
    end if;

    if v_final_score is null and v_performance_band is not null then
        raise exception
            'Candidate performance cycle % has performance_band without final_score.',
            p_candidate_cycle_id;
    end if;

    if v_final_score is not null and v_performance_band is null then
        raise exception
            'Candidate performance cycle % has final_score without performance_band.',
            p_candidate_cycle_id;
    end if;

    if (
        v_final_score is not null
        or v_performance_band is not null
    ) and (
        v_eligible_days <= 0
        or v_scored_days <> v_eligible_days
        or v_daily_component_score is null
    ) then
        raise exception
            'Candidate performance cycle % has stored final performance with incomplete daily scoring (% of % eligible days scored).',
            p_candidate_cycle_id,
            v_scored_days,
            v_eligible_days;
    end if;

    if v_old_status in ('FINALIZED', 'LOCKED') then
        return query select v_old_status, v_old_status;
        return;
    end if;

    if v_eligible_days = 0
       and v_business_date >= v_review_open_date then
        v_transition_timestamp := current_timestamp;

        update public.candidate_performance_cycles
        set
            scored_days = 0,
            daily_average = null,
            daily_component_score = null,
            lead_score = null,
            hr_score = null,
            exceptional_score = null,
            final_score = null,
            performance_band = null,
            calculated_at = null,
            finalized_at = null,
            result_status = 'NOT_EVALUATED',
            updated_at = v_transition_timestamp
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
            'PERFORMANCE_NOT_EVALUATED',
            v_old_status,
            'NOT_EVALUATED',
            'Candidate performance cycle was not evaluated because it had no eligible working days.',
            'SUCCESS',
            null,
            jsonb_build_object(
                'candidate_cycle_id', p_candidate_cycle_id,
                'eligible_days', 0,
                'reason', 'NO_ELIGIBLE_WORKING_DAYS',
                'business_date', v_business_date
            ),
            'SYSTEM',
            v_transition_timestamp
        );

        return query select v_old_status, 'NOT_EVALUATED'::text;
        return;
    end if;

    v_new_status := case
        when v_final_score is not null
             and v_performance_band is not null
            then 'CANDIDATE_REVIEW'
        when v_eligible_days > 0
             and v_scored_days = v_eligible_days
             and v_daily_component_score is not null
             and v_lead_score is not null
             and v_hr_score is not null
             and v_exceptional_score is not null
             and v_final_score is null
             and v_performance_band is null
            then 'READY_TO_CALCULATE'
        when v_eligible_days > 0
             and v_scored_days = v_eligible_days
             and v_daily_component_score is not null
             and (
                 v_lead_score is null
                 or v_hr_score is null
                 or v_exceptional_score is null
             )
            then 'AWAITING_REVIEWS'
        when v_scored_days > 0
             and v_scored_days < v_eligible_days
            then 'DAILY_SCORING'
        else 'PENDING'
    end;

    if v_new_status is distinct from v_old_status then
        update public.candidate_performance_cycles
        set result_status = v_new_status
        where id = p_candidate_cycle_id;
    end if;

    return query select v_old_status, v_new_status;
end;
$function$;

comment on function public.refresh_candidate_cycle_result_status(uuid) is
    'Refreshes one candidate-cycle status without calculating scores. It marks a zero-eligible-day cycle NOT_EVALUATED only after the Asia/Kolkata review-open date, clears all score/result fields for that terminal outcome, audits the transition once, preserves FINALIZED, LOCKED, and valid NOT_EVALUATED results, and otherwise derives the existing pre-final status.';

revoke execute on function public.refresh_candidate_cycle_result_status(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_result_status(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_result_status(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_result_status(uuid) to service_role;

create or replace function public.refresh_candidate_cycle_exceptional_summary(
    p_candidate_cycle_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_exceptional_score numeric;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select cpc.exceptional_score
        into strict v_exceptional_score
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    return v_exceptional_score;
end;
$function$;

comment on function public.refresh_candidate_cycle_exceptional_summary(uuid) is
    'Returns the explicit HR-entered candidate-cycle exceptional score without deriving or overwriting it from exceptional_contributions. NULL means not entered and zero is a valid explicit score. Historical exceptional_contributions remain untouched as evidence records.';

revoke execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_exceptional_summary(uuid) to service_role;

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
        if v_assignment.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED') then
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
    'Refreshes eligible working days for every assignment in one performance cycle by reusing the existing single-assignment eligible-day function. It preserves the Sunday, approved-leave, and Work From Home rules, skips finalized, locked, and not-evaluated results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not refresh scores or statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_eligible_days(uuid) to service_role;

create or replace function public.bulk_refresh_candidate_cycle_daily_summaries(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_scored_days integer,
    refreshed_scored_days integer,
    previous_daily_average numeric,
    refreshed_daily_average numeric,
    previous_daily_component_score numeric,
    refreshed_daily_component_score numeric,
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
    v_refreshed_scored_days integer;
    v_refreshed_daily_average numeric;
    v_refreshed_daily_component_score numeric;
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
            cpc.scored_days,
            cpc.daily_average,
            cpc.daily_component_score,
            cpc.result_status
        from public.candidate_performance_cycles cpc
        where cpc.cycle_id = p_cycle_id
        order by
            cpc.candidate_id,
            cpc.id
        for update of cpc
    loop
        if v_assignment.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED') then
            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.scored_days::integer,
                v_assignment.scored_days::integer,
                v_assignment.daily_average::numeric,
                v_assignment.daily_average::numeric,
                v_assignment.daily_component_score::numeric,
                v_assignment.daily_component_score::numeric,
                'SKIPPED'::text,
                format(
                    'Daily summary cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            begin
                select
                    summary.scored_days,
                    summary.daily_average,
                    summary.daily_component_score
                into strict
                    v_refreshed_scored_days,
                    v_refreshed_daily_average,
                    v_refreshed_daily_component_score
                from public.refresh_candidate_cycle_daily_summary(
                    v_assignment.candidate_cycle_id
                ) as summary;
            exception
                when no_data_found then
                    raise exception
                        'Daily-summary refresh returned no row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                when too_many_rows then
                    raise exception
                        'Daily-summary refresh returned more than one row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
            end;

            if v_refreshed_scored_days is null then
                raise exception
                    'Daily-summary refresh returned null scored_days for candidate performance cycle %.',
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_scored_days < 0 then
                raise exception
                    'Daily-summary refresh returned negative scored_days % for candidate performance cycle %.',
                    v_refreshed_scored_days,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_scored_days > v_assignment.eligible_days then
                raise exception
                    'Daily-summary refresh returned scored_days % greater than eligible_days % for candidate performance cycle %.',
                    v_refreshed_scored_days,
                    v_assignment.eligible_days,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_scored_days = 0 then
                if v_refreshed_daily_average is not null
                   or v_refreshed_daily_component_score is not null then
                    raise exception
                        'Daily-summary refresh returned score values for zero scored days on candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                end if;
            else
                if v_refreshed_daily_average is null
                   or v_refreshed_daily_component_score is null then
                    raise exception
                        'Daily-summary refresh returned incomplete score values for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                end if;

                if v_refreshed_daily_average not between -10 and 10 then
                    raise exception
                        'Daily-summary refresh returned daily_average % outside -10 to 10 for candidate performance cycle %.',
                        v_refreshed_daily_average,
                        v_assignment.candidate_cycle_id;
                end if;

                if v_refreshed_daily_component_score not between 0 and 50 then
                    raise exception
                        'Daily-summary refresh returned daily_component_score % outside 0 to 50 for candidate performance cycle %.',
                        v_refreshed_daily_component_score,
                        v_assignment.candidate_cycle_id;
                end if;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.scored_days::integer,
                v_refreshed_scored_days,
                v_assignment.daily_average::numeric,
                v_refreshed_daily_average,
                v_assignment.daily_component_score::numeric,
                v_refreshed_daily_component_score,
                'REFRESHED'::text,
                case
                    when v_refreshed_scored_days = v_assignment.scored_days
                         and v_refreshed_daily_average
                             is not distinct from v_assignment.daily_average
                         and v_refreshed_daily_component_score
                             is not distinct from v_assignment.daily_component_score then
                        'Daily summary refreshed and remained unchanged.'::text
                    else
                        'Daily summary refreshed successfully and changed.'::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.scored_days::integer,
                    null::integer,
                    v_assignment.daily_average::numeric,
                    null::numeric,
                    v_assignment.daily_component_score::numeric,
                    null::numeric,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) is
    'Refreshes daily-performance summaries for every assignment in one performance cycle by reusing the existing single-assignment daily-summary function. It preserves evaluation-date, Sunday, approved-leave, and Work From Home rules, skips finalized, locked, and not-evaluated results, returns refreshed, skipped, and failed outcomes per assignment, treats zero valid daily entries as a successful null-score summary, isolates assignment-specific failures, does not refresh eligible days, reviews, final scores, or statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_daily_summaries(uuid) to service_role;

create or replace function public.bulk_refresh_candidate_cycle_review_summaries(
    p_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    previous_lead_score numeric,
    refreshed_lead_score numeric,
    previous_hr_score numeric,
    refreshed_hr_score numeric,
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
    v_refreshed_lead_score numeric;
    v_refreshed_hr_score numeric;
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
            cpc.lead_score,
            cpc.hr_score,
            cpc.result_status
        from public.candidate_performance_cycles cpc
        where cpc.cycle_id = p_cycle_id
        order by
            cpc.candidate_id,
            cpc.id
        for update of cpc
    loop
        if v_assignment.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED') then
            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.lead_score::numeric,
                v_assignment.lead_score::numeric,
                v_assignment.hr_score::numeric,
                v_assignment.hr_score::numeric,
                'SKIPPED'::text,
                format(
                    'Review summary cannot be refreshed because the result is %s.',
                    v_assignment.result_status
                )::text;
            continue;
        end if;

        begin
            begin
                select
                    summary.lead_score,
                    summary.hr_score
                into strict
                    v_refreshed_lead_score,
                    v_refreshed_hr_score
                from public.refresh_candidate_cycle_review_summary(
                    v_assignment.candidate_cycle_id
                ) as summary;
            exception
                when no_data_found then
                    raise exception
                        'Review-summary refresh returned no row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
                when too_many_rows then
                    raise exception
                        'Review-summary refresh returned more than one row for candidate performance cycle %.',
                        v_assignment.candidate_cycle_id;
            end;

            if v_refreshed_lead_score is not null
               and v_refreshed_lead_score not between 0 and 25 then
                raise exception
                    'Review-summary refresh returned Lead score % outside 0 to 25 for candidate performance cycle %.',
                    v_refreshed_lead_score,
                    v_assignment.candidate_cycle_id;
            end if;

            if v_refreshed_hr_score is not null
               and v_refreshed_hr_score not between 0 and 15 then
                raise exception
                    'Review-summary refresh returned HR score % outside 0 to 15 for candidate performance cycle %.',
                    v_refreshed_hr_score,
                    v_assignment.candidate_cycle_id;
            end if;

            return query
            select
                v_assignment.candidate_cycle_id::uuid,
                v_assignment.candidate_id::uuid,
                v_assignment.lead_score::numeric,
                v_refreshed_lead_score,
                v_assignment.hr_score::numeric,
                v_refreshed_hr_score,
                'REFRESHED'::text,
                case
                    when v_refreshed_lead_score
                             is not distinct from v_assignment.lead_score
                         and v_refreshed_hr_score
                             is not distinct from v_assignment.hr_score then
                        'Review summary refreshed and remained unchanged.'::text
                    else
                        'Review summary refreshed successfully and changed.'::text
                end;
        exception
            when others then
                return query
                select
                    v_assignment.candidate_cycle_id::uuid,
                    v_assignment.candidate_id::uuid,
                    v_assignment.lead_score::numeric,
                    null::numeric,
                    v_assignment.hr_score::numeric,
                    null::numeric,
                    'FAILED'::text,
                    sqlerrm::text;
        end;
    end loop;
end;
$function$;

comment on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) is
    'Refreshes Lead and HR review summaries for every assignment in one performance cycle by reusing the existing single-assignment review-summary function. It counts only submitted reviews, ignores drafts, keeps missing reviews as null, skips finalized, locked, and not-evaluated results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not modify review records, calculate final scores, or change statuses, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_review_summaries(uuid) to service_role;

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
        if v_assignment.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED') then
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

            if v_refreshed_exceptional_score is not null
               and v_refreshed_exceptional_score not between 0 and 10 then
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
    'Returns the explicit candidate-cycle Exceptional score for every assignment without deriving it from exceptional_contributions. NULL is a valid not-yet-entered result, zero is a valid explicit score, finalized, locked, and not-evaluated results are skipped, and assignment-specific failures remain isolated.';

revoke execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_exceptional_summaries(uuid) to service_role;

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
        if v_assignment.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED') then
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
                'LOCKED',
                'NOT_EVALUATED'
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
    'Refreshes result statuses for every assignment in one performance cycle by reusing the existing single-assignment status-refresh function. It applies the approved status-priority rules including zero-day transitions to NOT_EVALUATED, skips finalized, locked, and existing not-evaluated results, returns refreshed, skipped, and failed outcomes per assignment, isolates assignment-specific failures, does not refresh scores, calculate results, finalize, or lock assignments, and is safe to run repeatedly.';

revoke execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) from public;
revoke execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) from anon;
revoke execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) from authenticated;
grant execute on function public.bulk_refresh_candidate_cycle_result_statuses(uuid) to service_role;

create or replace function public.run_daily_performance_cycle_maintenance()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_current_month date;
    v_next_month date;
    v_review_opened_cycle_count integer := 0;
    v_opened_cycle_count integer := 0;
    v_retried_job_count integer := 0;
    v_retry_error_count integer := 0;
    v_current_open_cycle_count integer := 0;
    v_current_open_cycle_ids uuid[];
    v_reconciled_cycle_id uuid;
    v_assignment_processed_count integer := 0;
    v_assigned_candidate_count integer := 0;
    v_skipped_candidate_count integer := 0;
    v_failed_candidate_count integer := 0;
    v_refresh_error_count integer := 0;
    v_step_refresh_error_count integer := 0;
    v_reconciliation_error_count integer := 0;
    v_job record;
    v_zero_day_assignment record;
begin
    v_current_month :=
        pg_catalog.date_trunc('month', v_business_date::timestamp)::date;
    v_next_month := (v_current_month + interval '1 month')::date;

    perform public.generate_performance_cycles_for_month(v_current_month);
    perform public.generate_performance_cycles_for_month(v_next_month);

    update public.performance_cycles
    set
        cycle_status = 'REVIEW_OPEN',
        updated_at = current_timestamp
    where cycle_status in ('DRAFT', 'OPEN')
      and review_open_date <= v_business_date;

    get diagnostics v_review_opened_cycle_count = row_count;

    for v_zero_day_assignment in
        select cpc.id as candidate_cycle_id
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
          on pc.id = cpc.cycle_id
        where pc.cycle_status = 'REVIEW_OPEN'
          and pc.review_open_date <= v_business_date
          and cpc.eligible_days = 0
          and cpc.result_status not in (
              'FINALIZED',
              'LOCKED',
              'NOT_EVALUATED'
          )
        order by cpc.id
        for update of cpc
    loop
        begin
            perform *
            from public.refresh_candidate_cycle_result_status(
                v_zero_day_assignment.candidate_cycle_id
            );
        exception
            when others then
                v_refresh_error_count := v_refresh_error_count + 1;
        end;
    end loop;

    update public.performance_cycles
    set
        cycle_status = 'OPEN',
        updated_at = current_timestamp
    where cycle_status = 'DRAFT'
      and v_business_date between start_date and end_date
      and v_business_date < review_open_date;

    get diagnostics v_opened_cycle_count = row_count;

    for v_job in
        select aj.job_id
        from public.automation_jobs aj
        where aj.job_type = 'PERFORMANCE_CYCLE_ASSIGNMENT'
          and aj.job_status in ('PENDING', 'RETRY')
          and aj.payload ->> 'pending_reason' = 'OPEN_CYCLE'
        order by aj.created_at, aj.job_id
    loop
        v_retried_job_count := v_retried_job_count + 1;

        begin
            perform public.process_performance_cycle_assignment_job(
                v_job.job_id
            );
        exception
            when others then
                v_retry_error_count := v_retry_error_count + 1;
        end;
    end loop;

    select
        pg_catalog.count(*)::integer,
        pg_catalog.array_agg(
            current_cycle.id
            order by current_cycle.start_date, current_cycle.id
        )
    into
        v_current_open_cycle_count,
        v_current_open_cycle_ids
    from (
        select pc.id, pc.start_date
        from public.performance_cycles pc
        where pc.cycle_status = 'OPEN'
          and v_business_date between pc.start_date and pc.end_date
        for update
    ) as current_cycle;

    if v_current_open_cycle_count > 1 then
        v_reconciliation_error_count :=
            v_reconciliation_error_count + 1;
    elsif v_current_open_cycle_count = 1 then
        v_reconciled_cycle_id := v_current_open_cycle_ids[1];

        begin
            select
                pg_catalog.count(*)::integer,
                pg_catalog.count(*) filter (
                    where result.assignment_outcome = 'ASSIGNED'
                )::integer,
                pg_catalog.count(*) filter (
                    where result.assignment_outcome = 'SKIPPED'
                )::integer,
                pg_catalog.count(*) filter (
                    where result.assignment_outcome = 'FAILED'
                )::integer
            into
                v_assignment_processed_count,
                v_assigned_candidate_count,
                v_skipped_candidate_count,
                v_failed_candidate_count
            from public.bulk_assign_candidates_to_performance_cycle(
                v_reconciled_cycle_id
            ) as result;
        exception
            when others then
                v_reconciliation_error_count :=
                    v_reconciliation_error_count + 1;
        end;

        begin
            select pg_catalog.count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
            into v_step_refresh_error_count
            from public.bulk_refresh_candidate_cycle_eligible_days(
                v_reconciled_cycle_id
            ) as result;

            v_refresh_error_count := v_refresh_error_count +
                coalesce(v_step_refresh_error_count, 0);
        exception
            when others then
                v_refresh_error_count := v_refresh_error_count + 1;
        end;

        begin
            select pg_catalog.count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
            into v_step_refresh_error_count
            from public.bulk_refresh_candidate_cycle_daily_summaries(
                v_reconciled_cycle_id
            ) as result;

            v_refresh_error_count := v_refresh_error_count +
                coalesce(v_step_refresh_error_count, 0);
        exception
            when others then
                v_refresh_error_count := v_refresh_error_count + 1;
        end;

        begin
            select pg_catalog.count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
            into v_step_refresh_error_count
            from public.bulk_refresh_candidate_cycle_review_summaries(
                v_reconciled_cycle_id
            ) as result;

            v_refresh_error_count := v_refresh_error_count +
                coalesce(v_step_refresh_error_count, 0);
        exception
            when others then
                v_refresh_error_count := v_refresh_error_count + 1;
        end;

        begin
            select pg_catalog.count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
            into v_step_refresh_error_count
            from public.bulk_refresh_candidate_cycle_exceptional_summaries(
                v_reconciled_cycle_id
            ) as result;

            v_refresh_error_count := v_refresh_error_count +
                coalesce(v_step_refresh_error_count, 0);
        exception
            when others then
                v_refresh_error_count := v_refresh_error_count + 1;
        end;

        begin
            select pg_catalog.count(*) filter (
                where result.refresh_outcome = 'FAILED'
            )::integer
            into v_step_refresh_error_count
            from public.bulk_refresh_candidate_cycle_result_statuses(
                v_reconciled_cycle_id
            ) as result;

            v_refresh_error_count := v_refresh_error_count +
                coalesce(v_step_refresh_error_count, 0);
        exception
            when others then
                v_refresh_error_count := v_refresh_error_count + 1;
        end;
    end if;

    return pg_catalog.jsonb_build_object(
        'businessDate', v_business_date,
        'reviewOpenedCycleCount', v_review_opened_cycle_count,
        'openedCycleCount', v_opened_cycle_count,
        'retriedJobCount', v_retried_job_count,
        'retryErrorCount', v_retry_error_count,
        'reconciledCycleId', v_reconciled_cycle_id,
        'assignmentProcessedCount', v_assignment_processed_count,
        'assignedCandidateCount', v_assigned_candidate_count,
        'skippedCandidateCount', v_skipped_candidate_count,
        'failedCandidateCount', v_failed_candidate_count,
        'refreshErrorCount', v_refresh_error_count,
        'reconciliationErrorCount', v_reconciliation_error_count
    );
end;
$function$;

comment on function
    public.run_daily_performance_cycle_maintenance() is
    'Runs daily performance-cycle maintenance using the Asia/Kolkata business date. It generates idempotent current- and next-month cycles, advances eligible cycles to OPEN or REVIEW_OPEN without moving statuses backwards, retries existing PERFORMANCE_CYCLE_ASSIGNMENT jobs waiting for an OPEN cycle, transitions review-open zero-eligible-day candidate cycles to NOT_EVALUATED using the India business date, and reconciles eligible candidates into exactly one current OPEN cycle before refreshing its non-final performance summaries. The existing pg_cron schedule remains 12:05 AM Asia/Kolkata, which is 18:35 UTC on the previous calendar day.';

revoke execute on function
    public.run_daily_performance_cycle_maintenance()
from public;

revoke execute on function
    public.run_daily_performance_cycle_maintenance()
from anon;

revoke execute on function
    public.run_daily_performance_cycle_maintenance()
from authenticated;

grant execute on function
    public.run_daily_performance_cycle_maintenance()
to service_role;

create or replace function public.advance_candidate_cycle_performance(
    p_candidate_cycle_id uuid
)
returns table (
    old_status text,
    new_status text,
    final_score numeric,
    performance_band text,
    calculated_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_initial_status text;
    v_refreshed_status text;
    v_final_status text;
    v_final_score numeric;
    v_performance_band text;
    v_calculated_at timestamptz;
begin
    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select cpc.result_status
        into strict v_initial_status
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle % does not exist.',
                p_candidate_cycle_id;
    end;

    select status_refresh.new_status
    into strict v_refreshed_status
    from public.refresh_candidate_cycle_result_status(
        p_candidate_cycle_id
    ) as status_refresh;

    if v_refreshed_status in (
        'READY_TO_CALCULATE',
        'CANDIDATE_REVIEW'
    ) then
        perform *
        from public.calculate_candidate_cycle_final_performance(
            p_candidate_cycle_id
        );

        select status_refresh.new_status
        into strict v_final_status
        from public.refresh_candidate_cycle_result_status(
            p_candidate_cycle_id
        ) as status_refresh;

        if v_final_status <> 'CANDIDATE_REVIEW' then
            raise exception
                'Candidate performance cycle % did not reach CANDIDATE_REVIEW after calculation.',
                p_candidate_cycle_id;
        end if;
    else
        v_final_status := v_refreshed_status;
    end if;

    select
        cpc.final_score,
        cpc.performance_band,
        cpc.calculated_at
    into
        v_final_score,
        v_performance_band,
        v_calculated_at
    from public.candidate_performance_cycles cpc
    where cpc.id = p_candidate_cycle_id;

    return query
    select
        v_initial_status,
        v_final_status,
        v_final_score,
        v_performance_band,
        v_calculated_at;
end;
$function$;

comment on function public.advance_candidate_cycle_performance(uuid) is
    'Internal repeat-safe candidate-cycle advancement. It refreshes status, calculates an exact READY_TO_CALCULATE result, safely recalculates a provisional CANDIDATE_REVIEW result after an allowed component amendment, refreshes again to CANDIDATE_REVIEW, and otherwise preserves the appropriate current or terminal state. It uses the existing /100 formula.';

revoke execute on function public.advance_candidate_cycle_performance(uuid) from public;
revoke execute on function public.advance_candidate_cycle_performance(uuid) from anon;
revoke execute on function public.advance_candidate_cycle_performance(uuid) from authenticated;
grant execute on function public.advance_candidate_cycle_performance(uuid) to service_role;

create or replace function public.save_candidate_exceptional_score(
    p_candidate_cycle_id uuid,
    p_exceptional_score numeric
)
returns table (
    candidate_cycle_id uuid,
    previous_exceptional_score numeric,
    exceptional_score numeric,
    result_status text,
    final_score numeric,
    performance_band text,
    calculated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
    v_assignment record;
    v_has_elevated_access boolean;
    v_normalized_score numeric;
    v_new_result_status text;
    v_final_score numeric;
    v_performance_band text;
    v_calculated_at timestamptz;
    v_save_timestamp timestamptz := current_timestamp;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
            public.current_user_has_any_role(
                array[
                    'ADMIN',
                    'HR_SITE_CONNECT',
                    'HR_SITE_CONNECT_LEAD',
                    'HR_EXECUTIVE_LEAD',
                    'HR_LEAD'
                ]::text[]
            ),
            false
       ) then
        raise insufficient_privilege
            using message = 'Exceptional performance scoring access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null then
        raise insufficient_privilege
            using message = 'Exceptional performance scoring access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    if p_exceptional_score is null then
        raise exception 'Exceptional score is required.'
            using errcode = '22004';
    end if;

    if p_exceptional_score < 0 or p_exceptional_score > 10 then
        raise exception 'Exceptional score must be between 0 and 10.'
            using errcode = '22003';
    end if;

    v_normalized_score := round(p_exceptional_score, 2);

    select
        cpc.candidate_id,
        cpc.pod_id,
        cpc.eligible_days,
        cpc.scored_days,
        cpc.daily_component_score,
        cpc.exceptional_score,
        cpc.result_status,
        pc.review_open_date,
        pc.cycle_status
    into strict v_assignment
    from public.candidate_performance_cycles cpc
    join public.performance_cycles pc
      on pc.id = cpc.cycle_id
    where cpc.id = p_candidate_cycle_id
    for update of cpc;

    if v_assignment.result_status in (
        'FINALIZED',
        'LOCKED',
        'NOT_EVALUATED'
    ) then
        raise exception
            'Exceptional score cannot be changed for this terminal performance result.'
            using errcode = 'P0001';
    end if;

    if v_assignment.eligible_days <= 0 then
        raise exception
            'Exceptional scoring requires eligible performance days.'
            using errcode = 'P0001';
    end if;

    if v_assignment.scored_days <> v_assignment.eligible_days
       or v_assignment.daily_component_score is null then
        raise exception
            'Daily performance scoring must be complete before Exceptional scoring.'
            using errcode = 'P0001';
    end if;

    if v_business_date < v_assignment.review_open_date then
        raise exception
            'Exceptional scoring is not open yet.'
            using errcode = 'P0001';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Exceptional scoring is not available for this cycle status.'
            using errcode = 'P0001';
    end if;

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'ADMIN',
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    if not v_has_elevated_access
       and not exists (
            select 1
            from public.user_roles ur
            join public.roles r
              on r.id = ur.role_id
             and r.slug = 'HR_SITE_CONNECT'
             and r.is_active = true
            join public.pod_memberships pm
              on pm.user_id = ur.user_id
             and pm.membership_type = 'HR_SITE_CONNECT'
             and pm.pod_id = v_assignment.pod_id
             and pm.candidate_id is null
             and pm.is_active = true
             and pm.effective_from <= v_business_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= v_business_date
             )
            where ur.user_id = v_actor_user_id
              and ur.is_active = true
              and ur.ended_at is null
       ) then
        raise insufficient_privilege
            using message = 'Exceptional performance scoring access is not available.';
    end if;

    if v_assignment.exceptional_score
       is not distinct from v_normalized_score then
        select
            advancement.new_status,
            advancement.final_score,
            advancement.performance_band,
            advancement.calculated_at
        into strict
            v_new_result_status,
            v_final_score,
            v_performance_band,
            v_calculated_at
        from public.advance_candidate_cycle_performance(
            p_candidate_cycle_id
        ) as advancement;

        return query
        select
            p_candidate_cycle_id,
            v_assignment.exceptional_score,
            v_normalized_score,
            v_new_result_status,
            v_final_score,
            v_performance_band,
            v_calculated_at;
        return;
    end if;

    update public.candidate_performance_cycles
    set
        exceptional_score = v_normalized_score,
        final_score = null,
        performance_band = null,
        calculated_at = null,
        finalized_at = null,
        updated_at = v_save_timestamp
    where id = p_candidate_cycle_id;

    select
        advancement.new_status,
        advancement.final_score,
        advancement.performance_band,
        advancement.calculated_at
    into strict
        v_new_result_status,
        v_final_score,
        v_performance_band,
        v_calculated_at
    from public.advance_candidate_cycle_performance(
        p_candidate_cycle_id
    ) as advancement;

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
        v_assignment.candidate_id,
        'PERFORMANCE_EXCEPTIONAL_SCORE_UPDATED',
        v_assignment.result_status,
        v_new_result_status,
        'Exceptional performance score saved by HR.',
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'old_exceptional_score', v_assignment.exceptional_score,
            'new_exceptional_score', v_normalized_score,
            'actor_user_id', v_actor_user_id
        ),
        v_actor_user_id::text,
        v_save_timestamp
    );

    return query
    select
        p_candidate_cycle_id,
        v_assignment.exceptional_score,
        v_normalized_score,
        v_new_result_status,
        v_final_score,
        v_performance_band,
        v_calculated_at;
exception
    when no_data_found then
        raise exception
            'Candidate performance cycle does not exist.'
            using errcode = 'P0001';
end;
$function$;

comment on function public.save_candidate_exceptional_score(uuid, numeric) is
    'Allows authorized HR performance reviewers to enter or amend an explicit 0-to-10 candidate-cycle Exceptional score after Daily scoring is complete and review is open. It uses the existing HR review role/pod model, keeps exceptional_contributions separate, invalidates any provisional final result before recalculation, audits changes, and advances the result automatically.';

revoke execute on function public.save_candidate_exceptional_score(uuid, numeric) from public;
revoke execute on function public.save_candidate_exceptional_score(uuid, numeric) from anon;
grant execute on function public.save_candidate_exceptional_score(uuid, numeric) to authenticated;
grant execute on function public.save_candidate_exceptional_score(uuid, numeric) to service_role;

create or replace function public.finalize_and_lock_candidate_performance(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    result_status text,
    final_score numeric,
    performance_band text,
    finalized_at timestamptz,
    locked_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_current_status text;
    v_final_score numeric;
    v_performance_band text;
    v_finalized_at timestamptz;
    v_locked_at timestamptz;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(public.current_user_has_role('HR_LEAD'), false) then
        raise insufficient_privilege
            using message = 'Performance finalization access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null then
        raise insufficient_privilege
            using message = 'Performance finalization access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.result_status,
            cpc.final_score,
            cpc.performance_band,
            cpc.finalized_at
        into strict
            v_current_status,
            v_final_score,
            v_performance_band,
            v_finalized_at
        from public.candidate_performance_cycles cpc
        where cpc.id = p_candidate_cycle_id
        for update;
    exception
        when no_data_found then
            raise exception
                'Candidate performance cycle does not exist.'
                using errcode = 'P0001';
    end;

    if v_current_status not in (
        'CANDIDATE_REVIEW',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Performance result is not ready for HR Lead finalization.'
            using errcode = 'P0001';
    end if;

    if v_current_status = 'CANDIDATE_REVIEW' then
        perform *
        from public.finalize_candidate_cycle_performance(
            p_candidate_cycle_id,
            v_actor_user_id::text
        );
    end if;

    select locking.locked_at
    into strict v_locked_at
    from public.lock_candidate_cycle_performance(
        p_candidate_cycle_id,
        v_actor_user_id::text
    ) as locking;

    select
        cpc.result_status,
        cpc.final_score,
        cpc.performance_band,
        cpc.finalized_at
    into strict
        v_current_status,
        v_final_score,
        v_performance_band,
        v_finalized_at
    from public.candidate_performance_cycles cpc
    where cpc.id = p_candidate_cycle_id;

    if v_current_status <> 'LOCKED' then
        raise exception
            'Performance result did not reach LOCKED after finalization.'
            using errcode = 'P0001';
    end if;

    return query
    select
        p_candidate_cycle_id,
        v_current_status,
        v_final_score,
        v_performance_band,
        v_finalized_at,
        v_locked_at;
end;
$function$;

comment on function public.finalize_and_lock_candidate_performance(uuid) is
    'Authenticated exact-HR_LEAD operation that atomically finalizes a CANDIDATE_REVIEW result and immediately locks it, safely completes locking for an interrupted FINALIZED result, and is repeat-safe for an already LOCKED result. Legacy service-role finalize and lock functions remain unexposed to authenticated users.';

revoke execute on function public.finalize_and_lock_candidate_performance(uuid) from public;
revoke execute on function public.finalize_and_lock_candidate_performance(uuid) from anon;
grant execute on function public.finalize_and_lock_candidate_performance(uuid) to authenticated;
grant execute on function public.finalize_and_lock_candidate_performance(uuid) to service_role;


create or replace function public.save_candidate_daily_performance_entry(
    p_candidate_cycle_id uuid,
    p_performance_date date,
    p_work_delivery_score smallint,
    p_communication_responsibility_score smallint,
    p_reason_code text,
    p_reviewer_comment text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_existing_entry public.daily_performance_entries%rowtype;
    v_reviewer_user_id uuid;
    v_entry_id uuid;
    v_reason_code text;
    v_reviewer_comment text;
    v_requested_daily_total smallint;
    v_new_daily_total smallint;
    v_old_work_delivery_score smallint;
    v_old_communication_responsibility_score smallint;
    v_old_daily_total smallint;
    v_old_reason_code text;
    v_old_reviewer_comment text;
    v_eligible_days integer;
    v_scored_days integer;
    v_daily_average numeric;
    v_daily_component_score numeric;
    v_old_status text;
    v_new_status text;
    v_operation text;
    v_activity_type text;
    v_save_timestamp timestamptz := now();
    v_entry_exists boolean;
    v_has_elevated_access boolean;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'HR_SITE_CONNECT',
                   'HR_SITE_CONNECT_LEAD',
                   'HR_EXECUTIVE_LEAD',
                   'HR_LEAD'
               ]::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance marking access is not available.';
    end if;

    v_reviewer_user_id := public.current_app_user_id();

    if v_reviewer_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'Daily performance marking access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    if p_performance_date is null then
        raise exception 'p_performance_date must not be null.'
            using errcode = '22004';
    end if;

    if p_work_delivery_score is null
       or p_communication_responsibility_score is null then
        raise exception 'Both daily performance scores are required.'
            using errcode = '22004';
    end if;

    if p_work_delivery_score not between -5 and 5 then
        raise exception 'Work delivery score must be between -5 and 5.'
            using errcode = '22003';
    end if;

    if p_communication_responsibility_score not between -5 and 5 then
        raise exception
            'Communication and responsibility score must be between -5 and 5.'
            using errcode = '22003';
    end if;

    if p_performance_date > current_date then
        raise exception 'Daily performance cannot be marked for a future date.'
            using errcode = '22007';
    end if;

    v_reason_code := nullif(upper(btrim(p_reason_code)), '');
    v_reviewer_comment := nullif(btrim(p_reviewer_comment), '');
    v_requested_daily_total :=
        p_work_delivery_score + p_communication_responsibility_score;

    if v_reason_code is not null
       and v_reason_code not in (
           'WORK_COMPLETED',
           'PARTIAL_COMPLETION',
           'QUALITY_ISSUE',
           'DEADLINE_DELAY',
           'BLOCKER_COMMUNICATED',
           'MISSED_UPDATE',
           'STRONG_OWNERSHIP',
           'MEETING_ABSENCE',
           'FALSE_UPDATE',
           'OTHER'
       ) then
        raise exception 'Reason code is not valid.'
            using errcode = '22023';
    end if;

    if char_length(v_reviewer_comment) > 2000 then
        raise exception 'Reviewer comment must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    if (
        v_requested_daily_total <= -5
        or v_requested_daily_total = 10
    ) and v_reason_code is null then
        raise exception 'A reason code is required for this daily score.'
            using errcode = '23514';
    end if;

    if v_requested_daily_total = -10
       and v_reviewer_comment is null then
        raise exception 'A reviewer comment is required for the minimum daily score.'
            using errcode = '23514';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'daily-performance:'
                || p_candidate_cycle_id::text
                || ':'
                || p_performance_date::text,
            0::bigint
        )
    );

    begin
        select
            cpc.candidate_id,
            cpc.pod_id,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.result_status,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at,
            pc.cycle_status
        into strict v_assignment
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        where cpc.id = p_candidate_cycle_id
        for update of cpc;
    exception
        when no_data_found then
            raise exception 'Candidate performance cycle was not found.'
                using errcode = 'P0002';
    end;

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    if not v_has_elevated_access
       and not exists (
           select 1
           from public.pod_memberships pm
           where pm.user_id = v_reviewer_user_id
             and pm.pod_id = v_assignment.pod_id
             and pm.membership_type = 'HR_SITE_CONNECT'
             and public.current_user_has_role('HR_SITE_CONNECT')
             and pm.is_active = true
             and pm.effective_from <= current_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= current_date
             )
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance marking access is not available.';
    end if;

    if p_performance_date < v_assignment.evaluation_start_date
       or p_performance_date > v_assignment.evaluation_end_date then
        raise exception
            'Performance date must be inside the candidate evaluation period.'
            using errcode = '22007';
    end if;

    if extract(isodow from p_performance_date) = 7 then
        raise exception 'Daily performance cannot be marked for Sunday.'
            using errcode = '22007';
    end if;

    if exists (
        select 1
        from public.leave_requests lr
        where lr.candidate_id = v_assignment.candidate_id
          and lr.leave_status = 'APPROVED'
          and p_performance_date between lr.start_date and lr.end_date
          and lower(btrim(lr.leave_type)) <> 'work from home'
    ) then
        raise exception
            'Daily performance cannot be marked during approved leave.'
            using errcode = '22007';
    end if;

    if v_assignment.result_status in (
        'CANDIDATE_REVIEW',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Daily performance cannot be changed for this result status.'
            using errcode = '55000';
    end if;

    if v_assignment.final_score is not null
       or v_assignment.performance_band is not null
       or v_assignment.calculated_at is not null then
        raise exception
            'Daily performance cannot be changed after final calculation.'
            using errcode = '55000';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'Daily performance marking is not available for this cycle status.'
            using errcode = '55000';
    end if;

    select dpe.*
    into v_existing_entry
    from public.daily_performance_entries dpe
    where dpe.candidate_cycle_id = p_candidate_cycle_id
      and dpe.performance_date = p_performance_date
    for update;

    v_entry_exists := found;

    if v_entry_exists then
        v_old_work_delivery_score := v_existing_entry.work_delivery_score;
        v_old_communication_responsibility_score :=
            v_existing_entry.communication_responsibility_score;
        v_old_daily_total := v_existing_entry.daily_total;
        v_old_reason_code := v_existing_entry.reason_code;
        v_old_reviewer_comment := v_existing_entry.reviewer_comment;
        v_operation := 'UPDATED';
        v_activity_type := 'DAILY_PERFORMANCE_MARK_UPDATED';

        update public.daily_performance_entries
        set
            work_delivery_score = p_work_delivery_score,
            communication_responsibility_score =
                p_communication_responsibility_score,
            reviewer_user_id = v_reviewer_user_id,
            reason_code = v_reason_code,
            reviewer_comment = v_reviewer_comment,
            submitted_at = v_save_timestamp,
            updated_at = v_save_timestamp
        where id = v_existing_entry.id
        returning
            id,
            daily_total
        into
            v_entry_id,
            v_new_daily_total;
    else
        v_operation := 'CREATED';
        v_activity_type := 'DAILY_PERFORMANCE_MARK_CREATED';

        insert into public.daily_performance_entries (
            candidate_cycle_id,
            performance_date,
            work_delivery_score,
            communication_responsibility_score,
            reviewer_user_id,
            reason_code,
            reviewer_comment,
            submitted_at,
            created_at,
            updated_at
        )
        values (
            p_candidate_cycle_id,
            p_performance_date,
            p_work_delivery_score,
            p_communication_responsibility_score,
            v_reviewer_user_id,
            v_reason_code,
            v_reviewer_comment,
            v_save_timestamp,
            v_save_timestamp,
            v_save_timestamp
        )
        returning
            id,
            daily_total
        into
            v_entry_id,
            v_new_daily_total;
    end if;

    select public.refresh_candidate_cycle_eligible_days(
        p_candidate_cycle_id
    )
    into v_eligible_days;

    begin
        select
            summary.scored_days,
            summary.daily_average,
            summary.daily_component_score
        into strict
            v_scored_days,
            v_daily_average,
            v_daily_component_score
        from public.refresh_candidate_cycle_daily_summary(
            p_candidate_cycle_id
        ) as summary;
    exception
        when no_data_found then
            raise exception 'Daily performance summary refresh returned no result.';
        when too_many_rows then
            raise exception 'Daily performance summary refresh returned multiple results.';
    end;

    begin
        select
            status_refresh.old_status,
            status_refresh.new_status
        into strict
            v_old_status,
            v_new_status
        from public.advance_candidate_cycle_performance(
            p_candidate_cycle_id
        ) as status_refresh;
    exception
        when no_data_found then
            raise exception 'Performance status refresh returned no result.';
        when too_many_rows then
            raise exception 'Performance status refresh returned multiple results.';
    end;

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
        performed_at,
        created_at,
        updated_at
    )
    values (
        v_assignment.candidate_id,
        v_activity_type,
        v_old_status,
        v_new_status,
        case v_operation
            when 'CREATED' then
                format(
                    'Daily performance mark created for %s.',
                    p_performance_date
                )
            else
                format(
                    'Daily performance mark updated for %s.',
                    p_performance_date
                )
        end,
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'daily_entry_id', v_entry_id,
            'performance_date', p_performance_date,
            'old_work_delivery_score', v_old_work_delivery_score,
            'new_work_delivery_score', p_work_delivery_score,
            'old_communication_responsibility_score',
                v_old_communication_responsibility_score,
            'new_communication_responsibility_score',
                p_communication_responsibility_score,
            'old_daily_total', v_old_daily_total,
            'new_daily_total', v_new_daily_total,
            'old_reason_code', v_old_reason_code,
            'new_reason_code', v_reason_code,
            'old_reviewer_comment', v_old_reviewer_comment,
            'new_reviewer_comment', v_reviewer_comment,
            'eligible_days', v_eligible_days,
            'scored_days', v_scored_days,
            'daily_average', v_daily_average,
            'daily_component_score', v_daily_component_score
        ),
        v_reviewer_user_id::text,
        v_save_timestamp,
        v_save_timestamp,
        v_save_timestamp
    );

    return jsonb_build_object(
        'dailyEntryId', v_entry_id,
        'candidateCycleId', p_candidate_cycle_id,
        'candidateId', v_assignment.candidate_id,
        'performanceDate', p_performance_date,
        'workDeliveryScore', p_work_delivery_score,
        'communicationResponsibilityScore',
            p_communication_responsibility_score,
        'dailyTotal', v_new_daily_total,
        'reasonCode', v_reason_code,
        'reviewerComment', v_reviewer_comment,
        'reviewerUserId', v_reviewer_user_id,
        'submittedAt', v_save_timestamp,
        'scoredDays', v_scored_days,
        'dailyAverage', v_daily_average,
        'dailyComponentScore', v_daily_component_score,
        'oldStatus', v_old_status,
        'newStatus', v_new_status,
        'operation', v_operation
    );
end;
$function$;

comment on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) is
    'Creates or updates one eligible daily performance mark for an authorized active HR reviewer, derives reviewer identity from the authenticated application user, refreshes the candidate-cycle daily summary and result status, and records a permanent activity log in the same transaction.';

revoke execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) from public;

revoke execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) from anon;

grant execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) to authenticated;

grant execute on function public.save_candidate_daily_performance_entry(
    uuid,
    date,
    smallint,
    smallint,
    text,
    text
) to service_role;

create or replace function public.save_candidate_lead_review(
    p_candidate_cycle_id uuid,
    p_work_quality_score smallint,
    p_role_capability_score smallint,
    p_deadline_delivery_score smallint,
    p_ownership_teamwork_score smallint,
    p_reviewer_comment text,
    p_review_status text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_existing_review public.performance_reviews%rowtype;
    v_reviewer_user_id uuid;
    v_reviewer_candidate_id uuid;
    v_reviewer_name text;
    v_review_status text;
    v_reviewer_comment text;
    v_review_id uuid;
    v_new_total_score smallint;
    v_new_submitted_at timestamptz;
    v_old_review_status text;
    v_old_work_quality_score smallint;
    v_old_role_capability_score smallint;
    v_old_deadline_delivery_score smallint;
    v_old_ownership_teamwork_score smallint;
    v_old_total_score smallint;
    v_old_reviewer_comment text;
    v_lead_score numeric;
    v_old_result_status text;
    v_new_result_status text;
    v_operation text;
    v_activity_type text;
    v_remarks text;
    v_save_timestamp timestamptz := current_timestamp;
    v_review_exists boolean;
    v_has_lead_pod_membership boolean;
    v_has_pod_lead_membership boolean;
    v_target_is_project_manager boolean;
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array['POD_LEAD', 'TECH_LEAD']::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Lead review marking access is not available.';
    end if;

    v_reviewer_user_id := public.current_app_user_id();

    if v_reviewer_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'Lead review marking access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_review_status := upper(btrim(p_review_status));
    v_reviewer_comment := nullif(btrim(p_reviewer_comment), '');

    if v_review_status is null
       or v_review_status not in ('DRAFT', 'SUBMITTED') then
        raise exception 'Review status must be DRAFT or SUBMITTED.'
            using errcode = '22023';
    end if;

    if p_work_quality_score is not null
       and p_work_quality_score not between 0 and 10 then
        raise exception 'Work quality score must be between 0 and 10.'
            using errcode = '22003';
    end if;

    if p_role_capability_score is not null
       and p_role_capability_score not between 0 and 5 then
        raise exception 'Role capability score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_deadline_delivery_score is not null
       and p_deadline_delivery_score not between 0 and 5 then
        raise exception 'Deadline delivery score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_ownership_teamwork_score is not null
       and p_ownership_teamwork_score not between 0 and 5 then
        raise exception 'Ownership and teamwork score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if v_review_status = 'SUBMITTED'
       and (
           p_work_quality_score is null
           or p_role_capability_score is null
           or p_deadline_delivery_score is null
           or p_ownership_teamwork_score is null
       ) then
        raise exception 'All Lead review scores are required for submission.'
            using errcode = '23514';
    end if;

    if char_length(v_reviewer_comment) > 2000 then
        raise exception 'Reviewer comment must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    v_new_total_score :=
        coalesce(p_work_quality_score, 0)
        + coalesce(p_role_capability_score, 0)
        + coalesce(p_deadline_delivery_score, 0)
        + coalesce(p_ownership_teamwork_score, 0);

    if v_new_total_score not between 0 and 25 then
        raise exception 'Lead review total must be between 0 and 25.'
            using errcode = '22003';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'performance-review:'
                || p_candidate_cycle_id::text
                || ':LEAD',
            0::bigint
        )
    );

    begin
        select
            cpc.candidate_id,
            cpc.pod_id,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.result_status,
            cpc.lead_score,
            cpc.final_score,
            cpc.performance_band,
            cpc.calculated_at,
            pc.review_open_date,
            pc.cycle_status
        into strict v_assignment
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        where cpc.id = p_candidate_cycle_id
        for update of cpc;
    exception
        when no_data_found then
            raise exception 'Candidate performance cycle was not found.'
                using errcode = 'P0002';
    end;

    select cua.candidate_id
    into v_reviewer_candidate_id
    from public.candidate_user_accounts cua
    where cua.user_id = v_reviewer_user_id
      and cua.account_status = 'ACTIVE'
      and cua.deactivated_at is null
      and cua.activated_at <= current_timestamp;

    if v_reviewer_candidate_id = v_assignment.candidate_id then
        raise exception using
            errcode = '42501',
            message = 'You cannot submit a Lead Review for your own candidate cycle.';
    end if;

    select
        coalesce(bool_or(pm.membership_type in ('POD_LEAD', 'TECH_LEAD')), false),
        coalesce(bool_or(pm.membership_type = 'POD_LEAD'), false)
    into
        v_has_lead_pod_membership,
        v_has_pod_lead_membership
    from public.pod_memberships pm
    join public.user_roles ur
        on ur.user_id = pm.user_id
    join public.roles r
        on r.id = ur.role_id
       and r.slug = pm.membership_type
    where pm.pod_id = v_assignment.pod_id
      and pm.user_id = v_reviewer_user_id
      and pm.candidate_id is null
      and pm.membership_type in ('POD_LEAD', 'TECH_LEAD')
      and pm.is_active = true
      and pm.effective_from <= v_business_date
      and (pm.effective_to is null or pm.effective_to >= v_business_date)
      and ur.is_active = true
      and ur.ended_at is null
      and r.is_active = true;

    select exists (
        select 1
        from public.candidate_user_accounts target_cua
        join public.user_roles target_ur
            on target_ur.user_id = target_cua.user_id
        join public.roles target_r
            on target_r.id = target_ur.role_id
           and target_r.slug = 'TECH_LEAD'
        join public.pod_memberships target_pm
            on target_pm.user_id = target_cua.user_id
           and target_pm.pod_id = v_assignment.pod_id
           and target_pm.membership_type = 'TECH_LEAD'
        where target_cua.candidate_id = v_assignment.candidate_id
          and target_ur.is_active = true
          and target_ur.ended_at is null
          and target_r.is_active = true
          and target_pm.is_active = true
          and target_pm.effective_from <= v_business_date
          and (
              target_pm.effective_to is null
              or target_pm.effective_to >= v_business_date
          )
    ) into v_target_is_project_manager;

    if v_target_is_project_manager
       and not v_has_pod_lead_membership then
        raise exception using
            errcode = '42501',
            message = 'Project Manager Lead Reviews require an eligible Pod Lead.';
    end if;

    if not v_has_lead_pod_membership then
        raise exception using
            errcode = '42501',
            message = 'Lead review marking access is not available.';
    end if;

    if v_assignment.eligible_days <= 0 then
        raise exception 'Lead review requires eligible performance days.'
            using errcode = '55000';
    end if;

    if v_assignment.scored_days
       is distinct from v_assignment.eligible_days
       or v_assignment.daily_component_score is null then
        raise exception
            'Daily performance scoring must be complete before Lead review.'
            using errcode = '55000';
    end if;

    if v_business_date < v_assignment.review_open_date then
        raise exception 'Lead review is not open yet.'
            using errcode = '55000';
    end if;

    if v_assignment.cycle_status in ('DRAFT', 'FINALIZED', 'LOCKED') then
        raise exception
            'Lead review is not available for this cycle status.'
            using errcode = '55000';
    end if;

    if v_assignment.result_status in (
        'CANDIDATE_REVIEW', 'FINALIZED', 'LOCKED'
    ) then
        raise exception
            'Lead review is not available for this result status.'
            using errcode = '55000';
    end if;

    if v_assignment.final_score is not null
       or v_assignment.performance_band is not null
       or v_assignment.calculated_at is not null then
        raise exception
            'Lead review cannot be changed after final calculation.'
            using errcode = '55000';
    end if;

    select pr.*
    into v_existing_review
    from public.performance_reviews pr
    where pr.candidate_cycle_id = p_candidate_cycle_id
      and pr.review_type = 'LEAD'
    for update;

    v_review_exists := found;

    if v_review_exists
       and v_existing_review.review_status = 'SUBMITTED' then
        raise exception 'A submitted Lead review cannot be changed.'
            using errcode = '55000';
    end if;

    if v_review_exists
       and v_existing_review.review_status = 'DRAFT'
       and v_existing_review.reviewer_user_id is not null
       and v_existing_review.reviewer_user_id <> v_reviewer_user_id then
        raise exception
            'This Lead Review draft is already owned by another reviewer.'
            using errcode = '55000';
    end if;

    if v_review_exists then
        v_old_review_status := v_existing_review.review_status;
        v_old_work_quality_score := v_existing_review.work_quality_score;
        v_old_role_capability_score :=
            v_existing_review.role_capability_score;
        v_old_deadline_delivery_score :=
            v_existing_review.deadline_delivery_score;
        v_old_ownership_teamwork_score :=
            v_existing_review.ownership_teamwork_score;
        v_old_total_score := v_existing_review.total_score;
        v_old_reviewer_comment := v_existing_review.reviewer_comment;
    end if;

    if v_review_status = 'SUBMITTED' then
        v_operation := 'SUBMITTED';
        v_activity_type := 'LEAD_REVIEW_SUBMITTED';
        v_remarks := 'Lead performance review submitted.';
    elsif v_review_exists then
        v_operation := 'DRAFT_UPDATED';
        v_activity_type := 'LEAD_REVIEW_DRAFT_UPDATED';
        v_remarks := 'Lead performance review draft updated.';
    else
        v_operation := 'DRAFT_CREATED';
        v_activity_type := 'LEAD_REVIEW_DRAFT_CREATED';
        v_remarks := 'Lead performance review draft created.';
    end if;

    if v_review_exists then
        update public.performance_reviews
        set
            reviewer_user_id = v_reviewer_user_id,
            work_quality_score = p_work_quality_score,
            role_capability_score = p_role_capability_score,
            deadline_delivery_score = p_deadline_delivery_score,
            ownership_teamwork_score = p_ownership_teamwork_score,
            reviewer_comment = v_reviewer_comment,
            review_status = v_review_status,
            submitted_at = case
                when v_review_status = 'SUBMITTED' then v_save_timestamp
                else null
            end,
            updated_at = v_save_timestamp
        where id = v_existing_review.id
        returning id, total_score, submitted_at
        into v_review_id, v_new_total_score, v_new_submitted_at;
    else
        insert into public.performance_reviews (
            candidate_cycle_id,
            review_type,
            reviewer_user_id,
            work_quality_score,
            role_capability_score,
            deadline_delivery_score,
            ownership_teamwork_score,
            reviewer_comment,
            review_status,
            submitted_at,
            created_at,
            updated_at
        ) values (
            p_candidate_cycle_id,
            'LEAD',
            v_reviewer_user_id,
            p_work_quality_score,
            p_role_capability_score,
            p_deadline_delivery_score,
            p_ownership_teamwork_score,
            v_reviewer_comment,
            v_review_status,
            case
                when v_review_status = 'SUBMITTED' then v_save_timestamp
                else null
            end,
            v_save_timestamp,
            v_save_timestamp
        )
        returning id, total_score, submitted_at
        into v_review_id, v_new_total_score, v_new_submitted_at;
    end if;

    v_old_result_status := v_assignment.result_status;

    if v_review_status = 'SUBMITTED' then
        begin
            select review_summary.lead_score
            into strict v_lead_score
            from public.refresh_candidate_cycle_review_summary(
                p_candidate_cycle_id
            ) as review_summary;
        exception
            when no_data_found then
                raise exception 'Review summary refresh returned no result.';
            when too_many_rows then
                raise exception 'Review summary refresh returned multiple results.';
        end;

        begin
            select status_refresh.old_status, status_refresh.new_status
            into strict v_old_result_status, v_new_result_status
            from public.advance_candidate_cycle_performance(
                p_candidate_cycle_id
            ) as status_refresh;
        exception
            when no_data_found then
                raise exception 'Performance status refresh returned no result.';
            when too_many_rows then
                raise exception 'Performance status refresh returned multiple results.';
        end;
    else
        v_lead_score := v_assignment.lead_score;
        v_new_result_status := v_old_result_status;
    end if;

    select u.name::text
    into strict v_reviewer_name
    from public.users u
    where u.id = v_reviewer_user_id;

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
        performed_at,
        created_at,
        updated_at
    ) values (
        v_assignment.candidate_id,
        v_activity_type,
        v_old_result_status,
        v_new_result_status,
        v_remarks,
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'review_id', v_review_id,
            'review_type', 'LEAD',
            'old_review_status', v_old_review_status,
            'new_review_status', v_review_status,
            'old_work_quality_score', v_old_work_quality_score,
            'new_work_quality_score', p_work_quality_score,
            'old_role_capability_score', v_old_role_capability_score,
            'new_role_capability_score', p_role_capability_score,
            'old_deadline_delivery_score', v_old_deadline_delivery_score,
            'new_deadline_delivery_score', p_deadline_delivery_score,
            'old_ownership_teamwork_score',
                v_old_ownership_teamwork_score,
            'new_ownership_teamwork_score',
                p_ownership_teamwork_score,
            'old_total_score', v_old_total_score,
            'new_total_score', v_new_total_score,
            'old_reviewer_comment', v_old_reviewer_comment,
            'new_reviewer_comment', v_reviewer_comment,
            'reviewer_user_id', v_reviewer_user_id,
            'lead_score', v_lead_score
        ),
        v_reviewer_user_id::text,
        v_save_timestamp,
        v_save_timestamp,
        v_save_timestamp
    );

    return jsonb_build_object(
        'reviewId', v_review_id,
        'candidateCycleId', p_candidate_cycle_id,
        'candidateId', v_assignment.candidate_id,
        'podId', v_assignment.pod_id,
        'reviewStatus', v_review_status,
        'workQualityScore', p_work_quality_score,
        'roleCapabilityScore', p_role_capability_score,
        'deadlineDeliveryScore', p_deadline_delivery_score,
        'ownershipTeamworkScore', p_ownership_teamwork_score,
        'totalScore', v_new_total_score,
        'reviewerComment', v_reviewer_comment,
        'reviewerUserId', v_reviewer_user_id,
        'reviewerName', v_reviewer_name,
        'submittedAt', v_new_submitted_at,
        'leadScore', v_lead_score,
        'oldResultStatus', v_old_result_status,
        'newResultStatus', v_new_result_status,
        'operation', v_operation
    );
end;
$function$;

comment on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) is
    'Creates or updates one Lead Review, blocks self-review, requires a Pod Lead for current Project Manager candidates, preserves draft ownership, and uses the India business date for reviewer membership effectiveness.';

revoke execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) from public;

revoke execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) from anon;

grant execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) to authenticated;

grant execute on function public.save_candidate_lead_review(
    uuid,
    smallint,
    smallint,
    smallint,
    smallint,
    text,
    text
) to service_role;

create or replace function public.save_candidate_hr_review(
    p_candidate_cycle_id uuid,
    p_communication_professionalism_score smallint,
    p_attendance_update_discipline_score smallint,
    p_reporting_policy_compliance_score smallint,
    p_reviewer_comment text,
    p_review_status text,
    p_amendment_reason text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_existing_review public.performance_reviews%rowtype;
    v_reviewer_user_id uuid;
    v_reviewer_name text;
    v_review_status text;
    v_reviewer_comment text;
    v_amendment_reason text;
    v_review_id uuid;
    v_revision_id uuid;
    v_new_total_score smallint;
    v_new_submitted_at timestamptz;
    v_old_review_status text;
    v_old_communication_professionalism_score smallint;
    v_old_attendance_update_discipline_score smallint;
    v_old_reporting_policy_compliance_score smallint;
    v_old_total_score smallint;
    v_old_reviewer_comment text;
    v_hr_score numeric;
    v_old_result_status text;
    v_new_result_status text;
    v_operation text;
    v_activity_type text;
    v_remarks text;
    v_save_timestamp timestamptz := now();
    v_review_exists boolean;
    v_is_amendment boolean;
    v_hr_total_changed boolean := false;
    v_has_elevated_access boolean;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'ADMIN',
                   'HR_SITE_CONNECT',
                   'HR_SITE_CONNECT_LEAD',
                   'HR_EXECUTIVE_LEAD',
                   'HR_LEAD'
               ]::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR review marking access is not available.';
    end if;

    v_reviewer_user_id := public.current_app_user_id();

    if v_reviewer_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'HR review marking access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_review_status := upper(btrim(p_review_status));
    v_reviewer_comment := nullif(btrim(p_reviewer_comment), '');

    if v_reviewer_comment is null then
        raise exception 'Reviewer comment is required.'
            using errcode = '23514';
    end if;

    v_amendment_reason := nullif(btrim(p_amendment_reason), '');

    if v_review_status is null
       or v_review_status not in ('DRAFT', 'SUBMITTED') then
        raise exception 'Review status must be DRAFT or SUBMITTED.'
            using errcode = '22023';
    end if;

    if p_communication_professionalism_score is not null
       and p_communication_professionalism_score not between 0 and 5 then
        raise exception
            'Communication and professionalism score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_attendance_update_discipline_score is not null
       and p_attendance_update_discipline_score not between 0 and 5 then
        raise exception
            'Attendance and update discipline score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if p_reporting_policy_compliance_score is not null
       and p_reporting_policy_compliance_score not between 0 and 5 then
        raise exception
            'Reporting and policy compliance score must be between 0 and 5.'
            using errcode = '22003';
    end if;

    if v_review_status = 'SUBMITTED'
       and (
           p_communication_professionalism_score is null
           or p_attendance_update_discipline_score is null
           or p_reporting_policy_compliance_score is null
       ) then
        raise exception 'All HR review scores are required for submission.'
            using errcode = '23514';
    end if;

    if char_length(v_reviewer_comment) > 2000 then
        raise exception 'Reviewer comment must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    if char_length(v_amendment_reason) > 2000 then
        raise exception 'Amendment reason must not exceed 2000 characters.'
            using errcode = '22001';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'performance-review:'
                || p_candidate_cycle_id::text
                || ':HR',
            0::bigint
        )
    );

    begin
        select
            cpc.candidate_id,
            cpc.pod_id,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score,
            cpc.result_status,
            cpc.hr_score,
            pc.review_open_date,
            pc.cycle_status
        into strict v_assignment
        from public.candidate_performance_cycles cpc
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        where cpc.id = p_candidate_cycle_id
        for update of cpc;
    exception
        when no_data_found then
            raise exception 'Candidate performance cycle was not found.'
                using errcode = 'P0002';
    end;

    v_has_elevated_access := coalesce(
        public.current_user_has_any_role(
            array[
                'ADMIN',
                'HR_SITE_CONNECT_LEAD',
                'HR_EXECUTIVE_LEAD',
                'HR_LEAD'
            ]::text[]
        ),
        false
    );

    if not v_has_elevated_access
       and not exists (
           select 1
           from public.pod_memberships pm
           where pm.user_id = v_reviewer_user_id
             and pm.pod_id = v_assignment.pod_id
             and pm.candidate_id is null
             and pm.membership_type = 'HR_SITE_CONNECT'
             and pm.is_active = true
             and pm.effective_from <= current_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= current_date
             )
       ) then
        raise exception using
            errcode = '42501',
            message = 'HR review marking access is not available.';
    end if;

    if v_assignment.eligible_days <= 0 then
        raise exception 'HR review requires eligible performance days.'
            using errcode = '55000';
    end if;

    if v_assignment.scored_days
       is distinct from v_assignment.eligible_days
       or v_assignment.daily_component_score is null then
        raise exception
            'Daily performance scoring must be complete before HR review.'
            using errcode = '55000';
    end if;

    if current_date < v_assignment.review_open_date then
        raise exception 'HR review is not open yet.'
            using errcode = '55000';
    end if;

    if v_assignment.cycle_status in (
        'DRAFT',
        'FINALIZED',
        'LOCKED'
    ) then
        raise exception
            'HR review is not available for this cycle status.'
            using errcode = '55000';
    end if;

    if v_assignment.result_status in ('FINALIZED', 'LOCKED') then
        raise exception
            'HR review is not available for this result status.'
            using errcode = '55000';
    end if;

    select pr.*
    into v_existing_review
    from public.performance_reviews pr
    where pr.candidate_cycle_id = p_candidate_cycle_id
      and pr.review_type = 'HR'
    for update;

    v_review_exists := found;
    v_is_amendment :=
        v_review_exists
        and v_existing_review.review_status = 'SUBMITTED';

    if v_is_amendment then
        if v_amendment_reason is null then
            raise exception
                'An amendment reason is required to change a submitted HR review.'
                using errcode = '23514';
        end if;

        if p_communication_professionalism_score is null
           or p_attendance_update_discipline_score is null
           or p_reporting_policy_compliance_score is null then
            raise exception 'All HR review scores are required for submission.'
                using errcode = '23514';
        end if;

        v_review_status := 'SUBMITTED';
    end if;

    if v_review_exists then
        v_old_review_status := v_existing_review.review_status;
        v_old_communication_professionalism_score :=
            v_existing_review.communication_professionalism_score;
        v_old_attendance_update_discipline_score :=
            v_existing_review.attendance_update_discipline_score;
        v_old_reporting_policy_compliance_score :=
            v_existing_review.reporting_policy_compliance_score;
        v_old_total_score := v_existing_review.total_score;
        v_old_reviewer_comment := v_existing_review.reviewer_comment;
    end if;

    if v_is_amendment then
        v_operation := 'AMENDED';
        v_activity_type := 'HR_REVIEW_AMENDED';
        v_remarks := 'Submitted HR performance review amended.';
    elsif v_review_status = 'SUBMITTED' then
        v_operation := 'SUBMITTED';
        v_activity_type := 'HR_REVIEW_SUBMITTED';
        v_remarks := 'HR performance review submitted.';
    else
        v_operation := 'DRAFT_SAVED';
        v_activity_type := 'HR_REVIEW_DRAFT_SAVED';
        v_remarks := 'HR performance review draft saved.';
    end if;

    if v_review_exists then
        update public.performance_reviews
        set
            reviewer_user_id = v_reviewer_user_id,
            communication_professionalism_score =
                p_communication_professionalism_score,
            attendance_update_discipline_score =
                p_attendance_update_discipline_score,
            reporting_policy_compliance_score =
                p_reporting_policy_compliance_score,
            reviewer_comment = v_reviewer_comment,
            review_status = v_review_status,
            submitted_at = case
                when v_is_amendment then v_existing_review.submitted_at
                when v_review_status = 'SUBMITTED' then v_save_timestamp
                else null
            end,
            updated_at = v_save_timestamp
        where id = v_existing_review.id
        returning
            id,
            total_score,
            submitted_at
        into
            v_review_id,
            v_new_total_score,
            v_new_submitted_at;
    else
        insert into public.performance_reviews (
            candidate_cycle_id,
            review_type,
            reviewer_user_id,
            communication_professionalism_score,
            attendance_update_discipline_score,
            reporting_policy_compliance_score,
            reviewer_comment,
            review_status,
            submitted_at,
            created_at,
            updated_at
        )
        values (
            p_candidate_cycle_id,
            'HR',
            v_reviewer_user_id,
            p_communication_professionalism_score,
            p_attendance_update_discipline_score,
            p_reporting_policy_compliance_score,
            v_reviewer_comment,
            v_review_status,
            case
                when v_review_status = 'SUBMITTED' then v_save_timestamp
                else null
            end,
            v_save_timestamp,
            v_save_timestamp
        )
        returning
            id,
            total_score,
            submitted_at
        into
            v_review_id,
            v_new_total_score,
            v_new_submitted_at;
    end if;

    if v_new_total_score not between 0 and 15 then
        raise exception 'HR review total must be between 0 and 15.'
            using errcode = '22003';
    end if;

    if v_is_amendment then
        v_hr_total_changed :=
            v_old_total_score is distinct from v_new_total_score;

        insert into public.performance_review_revisions (
            performance_review_id,
            candidate_cycle_id,
            review_type,
            previous_scores,
            new_scores,
            previous_total_score,
            new_total_score,
            amendment_reason,
            amended_by,
            amended_at,
            created_at
        )
        values (
            v_review_id,
            p_candidate_cycle_id,
            'HR',
            jsonb_build_object(
                'communication_professionalism_score',
                    v_old_communication_professionalism_score,
                'attendance_update_discipline_score',
                    v_old_attendance_update_discipline_score,
                'reporting_policy_compliance_score',
                    v_old_reporting_policy_compliance_score
            ),
            jsonb_build_object(
                'communication_professionalism_score',
                    p_communication_professionalism_score,
                'attendance_update_discipline_score',
                    p_attendance_update_discipline_score,
                'reporting_policy_compliance_score',
                    p_reporting_policy_compliance_score
            ),
            v_old_total_score,
            v_new_total_score,
            v_amendment_reason,
            v_reviewer_user_id,
            v_save_timestamp,
            v_save_timestamp
        )
        returning id into v_revision_id;
    end if;

    v_old_result_status := v_assignment.result_status;

    if v_review_status = 'SUBMITTED' then
        begin
            select review_summary.hr_score
            into strict v_hr_score
            from public.refresh_candidate_cycle_review_summary(
                p_candidate_cycle_id
            ) as review_summary;
        exception
            when no_data_found then
                raise exception 'Review summary refresh returned no result.';
            when too_many_rows then
                raise exception 'Review summary refresh returned multiple results.';
        end;

        if v_is_amendment and v_hr_total_changed then
            update public.candidate_performance_cycles
            set
                final_score = null,
                performance_band = null,
                calculated_at = null
            where id = p_candidate_cycle_id;
        end if;

        begin
            select
                status_refresh.old_status,
                status_refresh.new_status
            into strict
                v_old_result_status,
                v_new_result_status
            from public.advance_candidate_cycle_performance(
                p_candidate_cycle_id
            ) as status_refresh;
        exception
            when no_data_found then
                raise exception 'Performance status refresh returned no result.';
            when too_many_rows then
                raise exception 'Performance status refresh returned multiple results.';
        end;
    else
        v_hr_score := v_assignment.hr_score;
        v_new_result_status := v_old_result_status;
    end if;

    select u.name::text
    into strict v_reviewer_name
    from public.users u
    where u.id = v_reviewer_user_id;

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
        performed_at,
        created_at,
        updated_at
    )
    values (
        v_assignment.candidate_id,
        v_activity_type,
        v_old_result_status,
        v_new_result_status,
        v_remarks,
        'SUCCESS',
        null,
        jsonb_build_object(
            'candidate_cycle_id', p_candidate_cycle_id,
            'review_id', v_review_id,
            'revision_id', v_revision_id,
            'review_type', 'HR',
            'old_review_status', v_old_review_status,
            'new_review_status', v_review_status,
            'old_communication_professionalism_score',
                v_old_communication_professionalism_score,
            'new_communication_professionalism_score',
                p_communication_professionalism_score,
            'old_attendance_update_discipline_score',
                v_old_attendance_update_discipline_score,
            'new_attendance_update_discipline_score',
                p_attendance_update_discipline_score,
            'old_reporting_policy_compliance_score',
                v_old_reporting_policy_compliance_score,
            'new_reporting_policy_compliance_score',
                p_reporting_policy_compliance_score,
            'old_total_score', v_old_total_score,
            'new_total_score', v_new_total_score,
            'old_reviewer_comment', v_old_reviewer_comment,
            'new_reviewer_comment', v_reviewer_comment,
            'amendment_reason', v_amendment_reason,
            'reviewer_user_id', v_reviewer_user_id,
            'hr_score', v_hr_score
        ),
        v_reviewer_user_id::text,
        v_save_timestamp,
        v_save_timestamp,
        v_save_timestamp
    );

    return jsonb_build_object(
        'reviewId', v_review_id,
        'revisionId', v_revision_id,
        'candidateCycleId', p_candidate_cycle_id,
        'candidateId', v_assignment.candidate_id,
        'podId', v_assignment.pod_id,
        'reviewStatus', v_review_status,
        'communicationProfessionalismScore',
            p_communication_professionalism_score,
        'attendanceUpdateDisciplineScore',
            p_attendance_update_discipline_score,
        'reportingPolicyComplianceScore',
            p_reporting_policy_compliance_score,
        'totalScore', v_new_total_score,
        'reviewerComment', v_reviewer_comment,
        'amendmentReason', v_amendment_reason,
        'reviewerUserId', v_reviewer_user_id,
        'reviewerName', v_reviewer_name,
        'submittedAt', v_new_submitted_at,
        'hrScore', v_hr_score,
        'oldResultStatus', v_old_result_status,
        'newResultStatus', v_new_result_status,
        'operation', v_operation
    );
end;
$function$;

comment on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) is
    'Creates or updates an HR Review draft, submits a complete HR Review, or amends a submitted HR Review with a required audit reason. Submission and amendment refresh the stored HR summary and result status and record permanent audit history atomically.';

revoke execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) from public;

revoke execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) from anon;

grant execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) to authenticated;

grant execute on function public.save_candidate_hr_review(
    uuid,
    smallint,
    smallint,
    smallint,
    text,
    text,
    text
) to service_role;


create or replace view public.candidate_performance_list_view
with (security_invoker = true)
as
select
    cpc.id as candidate_cycle_id,
    cpc.cycle_id,
    pc.cycle_code,
    pc.cycle_number,
    pc.start_date as cycle_start_date,
    pc.end_date as cycle_end_date,
    pc.review_open_date,
    pc.lock_date,
    pc.cycle_status,
    cpc.candidate_id,
    mc.full_name,
    mc.email,
    mc.applied_role,
    mc.role_code,
    mc.department,
    cpc.pod_id,
    p.pod_code,
    p.pod_name,
    cpc.evaluation_start_date,
    cpc.evaluation_end_date,
    cpc.is_partial_cycle,
    cpc.eligible_days,
    cpc.scored_days,
    greatest(cpc.eligible_days - cpc.scored_days, 0)::integer as remaining_scoring_days,
    case
        when cpc.eligible_days > 0 then
            round(cpc.scored_days::numeric / cpc.eligible_days::numeric * 100, 2)
        else 0::numeric
    end as scoring_completion_percent,
    cpc.daily_average,
    cpc.daily_component_score,
    cpc.lead_score,
    cpc.hr_score,
    cpc.exceptional_score,
    cpc.final_score,
    cpc.performance_band,
    cpc.result_status,
    (cpc.daily_component_score is not null) as daily_summary_ready,
    (cpc.lead_score is not null) as lead_review_ready,
    (cpc.hr_score is not null) as hr_review_ready,
    (cpc.exceptional_score is not null) as exceptional_summary_ready,
    (
        cpc.eligible_days > 0
        and cpc.scored_days = cpc.eligible_days
        and cpc.daily_component_score is not null
        and cpc.lead_score is not null
        and cpc.hr_score is not null
        and cpc.exceptional_score is not null
    ) as all_components_ready,
    (
        cpc.final_score is not null
        and cpc.performance_band is not null
    ) as final_result_ready,
    (cpc.result_status = 'CANDIDATE_REVIEW') as ready_for_finalization,
    (
        cpc.result_status in ('FINALIZED', 'LOCKED', 'NOT_EVALUATED')
    ) as is_protected,
    cpc.calculated_at,
    cpc.finalized_at,
    cpc.created_at as assignment_created_at,
    cpc.updated_at as assignment_updated_at
from public.candidate_performance_cycles cpc
join public.performance_cycles pc on pc.id = cpc.cycle_id
join public.master_candidates mc on mc.candidate_id = cpc.candidate_id
join public.pods p on p.id = cpc.pod_id;

comment on view public.candidate_performance_list_view is
    'Returns one operational row per candidate performance-cycle assignment, including explicit Exceptional readiness and protected LOCKED/NOT_EVALUATED terminal states, using security-invoker behavior.';

revoke all privileges on public.candidate_performance_list_view from public;
revoke all privileges on public.candidate_performance_list_view from anon;
revoke all privileges on public.candidate_performance_list_view from authenticated;
grant select on public.candidate_performance_list_view to service_role;

create or replace view public.performance_action_queue_view
with (security_invoker = true)
as
select
    cpdv.candidate_cycle_id::text || ':' || action.action_code as action_key,
    action.action_code,
    action.action_label,
    action.action_owner_scope,
    cpdv.candidate_cycle_id,
    cpdv.candidate_id,
    cpdv.full_name,
    cpdv.email,
    cpdv.applied_role,
    cpdv.role_code,
    cpdv.pod_id,
    cpdv.pod_code,
    cpdv.pod_name,
    cpdv.cycle_id,
    cpdv.cycle_code,
    cpdv.cycle_number,
    cpdv.cycle_start_date,
    cpdv.cycle_end_date,
    cpdv.evaluation_start_date,
    cpdv.evaluation_end_date,
    cpdv.review_open_date,
    cpdv.lock_date,
    cpdv.result_status,
    cpdv.eligible_days,
    cpdv.scored_days,
    cpdv.remaining_scoring_days,
    cpdv.pending_exceptional_count,
    action.due_date,
    (action.due_date - current_date)::integer as days_until_due,
    (current_date > action.due_date) as is_overdue,
    action.action_reason
from public.candidate_performance_detail_view cpdv
cross join lateral (
    select
        'COMPLETE_DAILY_SCORING'::text,
        'Complete Daily Scoring'::text,
        'HR_SITE_CONNECT'::text,
        cpdv.evaluation_end_date,
        format(
            '%s eligible scoring days remain incomplete.',
            cpdv.remaining_scoring_days
        )::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.remaining_scoring_days > 0
      and current_date >= cpdv.evaluation_start_date

    union all

    select
        'SUBMIT_LEAD_REVIEW'::text,
        'Submit Lead Review'::text,
        'LEAD'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the Lead review is missing.'::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.scored_days = cpdv.eligible_days
      and cpdv.daily_summary_ready = true
      and cpdv.lead_review_ready = false
      and current_date >= cpdv.review_open_date

    union all

    select
        'SUBMIT_HR_REVIEW'::text,
        'Submit HR Review'::text,
        'HR'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the HR review is missing.'::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.scored_days = cpdv.eligible_days
      and cpdv.daily_summary_ready = true
      and cpdv.hr_review_ready = false
      and current_date >= cpdv.review_open_date

    union all

    select
        'SUBMIT_EXCEPTIONAL_SCORE'::text,
        'Submit Exceptional Score'::text,
        'HR'::text,
        cpdv.lock_date,
        'Daily scoring is complete but the explicit Exceptional score is missing.'::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.eligible_days > 0
      and cpdv.scored_days = cpdv.eligible_days
      and cpdv.daily_summary_ready = true
      and cpdv.exceptional_summary_ready = false
      and current_date >= cpdv.review_open_date

    union all

    select
        'REVIEW_EXCEPTIONAL_CONTRIBUTIONS'::text,
        'Review Exceptional Contributions'::text,
        'HR'::text,
        cpdv.lock_date,
        format(
            '%s exceptional contributions are awaiting approval or rejection.',
            cpdv.pending_exceptional_count
        )::text
    where cpdv.result_status not in (
        'FINALIZED', 'LOCKED', 'NOT_EVALUATED'
    )
      and cpdv.pending_exceptional_count > 0

    union all

    select
        'FINALIZE_RESULT'::text,
        'Finalize Performance Result'::text,
        'HR_LEAD'::text,
        cpdv.lock_date,
        'The calculated result is ready for HR Lead finalization and automatic locking.'::text
    where cpdv.ready_for_finalization = true
      and cpdv.result_status = 'CANDIDATE_REVIEW'
      and cpdv.final_result_ready = true
) action (
    action_code,
    action_label,
    action_owner_scope,
    due_date,
    action_reason
);

comment on view public.performance_action_queue_view is
    'Returns outstanding Daily, Lead, HR, explicit Exceptional-score, exceptional-contribution-review, and HR Lead finalization actions. Calculation and locking are automatic, and NOT_EVALUATED results are terminal and excluded.';

revoke all privileges on public.performance_action_queue_view from public;
revoke all privileges on public.performance_action_queue_view from anon;
revoke all privileges on public.performance_action_queue_view from authenticated;
grant select on public.performance_action_queue_view to service_role;

create or replace function public.get_current_candidate_performance_history()
returns table (
    candidate_cycle_id uuid,
    cycle_id uuid,
    cycle_code text,
    cycle_number integer,
    cycle_start_date date,
    cycle_end_date date,
    cycle_status text,
    evaluation_start_date date,
    evaluation_end_date date,
    is_partial_cycle boolean,
    eligible_days integer,
    scored_days integer,
    daily_average numeric,
    daily_component_score numeric,
    lead_score numeric,
    hr_score numeric,
    exceptional_score numeric,
    final_score numeric,
    performance_band text,
    result_status text,
    final_result_ready boolean,
    finalized_at timestamptz,
    assignment_created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_candidate_id uuid;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(public.current_user_has_role('CANDIDATE'), false) then
        raise insufficient_privilege
            using message = 'Candidate performance history access is not available.';
    end if;

    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate performance history access is not available.';
    end if;

    return query
    select
        cplv.candidate_cycle_id,
        cplv.cycle_id,
        cplv.cycle_code,
        cplv.cycle_number,
        cplv.cycle_start_date,
        cplv.cycle_end_date,
        cplv.cycle_status,
        cplv.evaluation_start_date,
        cplv.evaluation_end_date,
        cplv.is_partial_cycle,
        cplv.eligible_days,
        cplv.scored_days,
        null::numeric,
        null::numeric,
        null::numeric,
        null::numeric,
        null::numeric,
        case
            when cplv.result_status = 'LOCKED'
                then cplv.final_score
            else null::numeric
        end,
        case
            when cplv.result_status = 'LOCKED'
                then cplv.performance_band
            else null::text
        end,
        cplv.result_status,
        (cplv.result_status = 'LOCKED'),
        case
            when cplv.result_status = 'LOCKED'
                then cplv.finalized_at
            else null::timestamptz
        end,
        cplv.assignment_created_at
    from public.candidate_performance_list_view cplv
    where cplv.candidate_id = v_candidate_id
    order by cplv.cycle_start_date, cplv.candidate_cycle_id;
end;
$function$;

comment on function public.get_current_candidate_performance_history() is
    'Returns the current candidate own performance history with all internal component-score fields masked. Final score, band, readiness, and finalized timestamp are exposed only for LOCKED results. NOT_EVALUATED remains visible with zero eligible days and no numerical result.';

revoke execute on function public.get_current_candidate_performance_history() from public;
revoke execute on function public.get_current_candidate_performance_history() from anon;
grant execute on function public.get_current_candidate_performance_history() to authenticated;
grant execute on function public.get_current_candidate_performance_history() to service_role;



update public.candidate_performance_cycles cpc
set
    exceptional_score = null,
    final_score = null,
    performance_band = null,
    calculated_at = null,
    finalized_at = null,
    updated_at = current_timestamp
where cpc.eligible_days > 0
  and cpc.exceptional_score = 0
  and cpc.result_status not in (
      'FINALIZED',
      'LOCKED',
      'NOT_EVALUATED'
  )
  and not exists (
      select 1
      from public.hr_activity_logs hal
      where hal.activity_type = 'PERFORMANCE_EXCEPTIONAL_SCORE_UPDATED'
        and hal.activity_status = 'SUCCESS'
        and hal.metadata ->> 'candidate_cycle_id' = cpc.id::text
        and (hal.metadata ->> 'new_exceptional_score')::numeric = 0
  );

do $do$
declare
    v_candidate_cycle_id uuid;
begin
    for v_candidate_cycle_id in
        select cpc.id
        from public.candidate_performance_cycles cpc
        where cpc.result_status not in (
            'FINALIZED',
            'LOCKED',
            'NOT_EVALUATED'
        )
          and (
              cpc.eligible_days = 0
              or (
                  cpc.eligible_days > 0
                  and cpc.exceptional_score is null
              )
          )
        order by cpc.id
    loop
        perform *
        from public.refresh_candidate_cycle_result_status(
            v_candidate_cycle_id
        );
    end loop;
end;
$do$;

commit;
