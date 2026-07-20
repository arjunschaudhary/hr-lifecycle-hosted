create or replace function public.refresh_candidate_cycle_review_summary(
    p_candidate_cycle_id uuid
)
returns table (
    lead_score numeric,
    hr_score numeric
)
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_locked_candidate_cycle_id uuid;
    v_lead_score numeric;
    v_hr_score numeric;
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

    select
        max(pr.total_score) filter (
            where pr.review_type = 'LEAD'
              and pr.review_status = 'SUBMITTED'
              and pr.submitted_at is not null
        ),
        max(pr.total_score) filter (
            where pr.review_type = 'HR'
              and pr.review_status = 'SUBMITTED'
              and pr.submitted_at is not null
        )
    into
        v_lead_score,
        v_hr_score
    from public.performance_reviews pr
    where pr.candidate_cycle_id = p_candidate_cycle_id;

    if v_lead_score is not null
       and (v_lead_score < 0 or v_lead_score > 25) then
        raise exception
            'Submitted Lead review total % is outside the allowed range 0 to 25 for candidate performance cycle %.',
            v_lead_score,
            p_candidate_cycle_id;
    end if;

    if v_hr_score is not null
       and (v_hr_score < 0 or v_hr_score > 15) then
        raise exception
            'Submitted HR review total % is outside the allowed range 0 to 15 for candidate performance cycle %.',
            v_hr_score,
            p_candidate_cycle_id;
    end if;

    update public.candidate_performance_cycles
    set
        lead_score = v_lead_score,
        hr_score = v_hr_score
    where id = p_candidate_cycle_id;

    return query
    select
        v_lead_score,
        v_hr_score;
end;
$function$;

comment on function public.refresh_candidate_cycle_review_summary(uuid) is
    'Refreshes submitted Lead and HR review totals for one candidate cycle, ignores draft reviews, and stores null for a review type that has not been submitted. It uses the generated review total_score, updates only lead_score and hr_score, does not calculate the final score or update result status, and is safe to run repeatedly.';

revoke execute on function public.refresh_candidate_cycle_review_summary(uuid) from public;
revoke execute on function public.refresh_candidate_cycle_review_summary(uuid) from anon;
revoke execute on function public.refresh_candidate_cycle_review_summary(uuid) from authenticated;
grant execute on function public.refresh_candidate_cycle_review_summary(uuid) to service_role;
