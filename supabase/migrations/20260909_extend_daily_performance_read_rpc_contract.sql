begin;

drop function if exists
    public.get_candidate_daily_performance_entries(uuid);

create or replace function public.get_candidate_daily_performance_entries(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    cycle_id uuid,
    cycle_code text,
    cycle_status text,
    pod_id uuid,
    pod_code text,
    pod_name text,
    evaluation_start_date date,
    evaluation_end_date date,
    result_status text,
    eligible_days integer,
    performance_date date,
    is_scorable boolean,
    exclusion_reason text,
    entry_id uuid,
    work_delivery_score smallint,
    communication_responsibility_score smallint,
    daily_total smallint,
    reason_code text,
    reviewer_comment text,
    reviewer_user_id uuid,
    reviewer_name text,
    submitted_at timestamptz,
    created_at timestamptz,
    updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'HR_SITE_CONNECT',
                   'HR_SITE_CONNECT_LEAD',
                   'HR_EXECUTIVE',
                   'HR_EXECUTIVE_LEAD',
                   'HR_LEAD'
               ]::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Daily performance access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    begin
        select
            cpc.id as candidate_cycle_id,
            cpc.candidate_id,
            mc.full_name,
            cpc.cycle_id,
            pc.cycle_code,
            pc.cycle_status,
            cpc.pod_id,
            p.pod_code,
            p.pod_name,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.result_status,
            cpc.eligible_days
        into strict v_assignment
        from public.candidate_performance_cycles cpc
        join public.master_candidates mc
            on mc.candidate_id = cpc.candidate_id
        join public.performance_cycles pc
            on pc.id = cpc.cycle_id
        join public.pods p
            on p.id = cpc.pod_id
        where cpc.id = p_candidate_cycle_id;
    exception
        when no_data_found then
            raise exception 'Candidate performance cycle was not found.'
                using errcode = 'P0002';
    end;

    return query
    with generated_dates as (
        select
            (
                v_assignment.evaluation_start_date
                + generated.day_offset
            )::date as generated_date
        from pg_catalog.generate_series(
            0,
            v_assignment.evaluation_end_date
                - v_assignment.evaluation_start_date
        ) as generated(day_offset)
    ),
    date_eligibility as (
        select
            generated_dates.generated_date,
            extract(isodow from generated_dates.generated_date) = 7
                as is_sunday,
            exists (
                select 1
                from public.leave_requests lr
                where lr.candidate_id = v_assignment.candidate_id
                  and lr.leave_status = 'APPROVED'
                  and generated_dates.generated_date
                      between lr.start_date and lr.end_date
                  and lower(btrim(lr.leave_type)) <> 'work from home'
            ) as has_approved_leave
        from generated_dates
    )
    select
        v_assignment.candidate_cycle_id::uuid,
        v_assignment.candidate_id::uuid,
        v_assignment.full_name::text,
        v_assignment.cycle_id::uuid,
        v_assignment.cycle_code::text,
        v_assignment.cycle_status::text,
        v_assignment.pod_id::uuid,
        v_assignment.pod_code::text,
        v_assignment.pod_name::text,
        v_assignment.evaluation_start_date::date,
        v_assignment.evaluation_end_date::date,
        v_assignment.result_status::text,
        v_assignment.eligible_days::integer,
        eligibility.generated_date,
        not (
            eligibility.is_sunday
            or eligibility.has_approved_leave
            or eligibility.generated_date > current_date
        ) as is_scorable,
        case
            when eligibility.is_sunday then 'SUNDAY'::text
            when eligibility.has_approved_leave then 'APPROVED_LEAVE'::text
            when eligibility.generated_date > current_date then 'FUTURE_DATE'::text
            else null::text
        end as exclusion_reason,
        dpe.id,
        dpe.work_delivery_score,
        dpe.communication_responsibility_score,
        dpe.daily_total,
        dpe.reason_code,
        dpe.reviewer_comment,
        dpe.reviewer_user_id,
        reviewer.name::text,
        dpe.submitted_at,
        dpe.created_at,
        dpe.updated_at
    from date_eligibility eligibility
    left join public.daily_performance_entries dpe
        on dpe.candidate_cycle_id = v_assignment.candidate_cycle_id
       and dpe.performance_date = eligibility.generated_date
    left join public.users reviewer
        on reviewer.id = dpe.reviewer_user_id
    order by eligibility.generated_date;
end;
$function$;

comment on function
    public.get_candidate_daily_performance_entries(uuid) is
    'Returns the complete inclusive evaluation-date marking grid and stored cycle summary fields for one candidate performance cycle, including scorable-day eligibility and existing daily marks. Access is read-only and limited to active authorized HR users; reviewer email addresses are not exposed.';

revoke execute on function
    public.get_candidate_daily_performance_entries(uuid)
from public;

revoke execute on function
    public.get_candidate_daily_performance_entries(uuid)
from anon;

grant execute on function
    public.get_candidate_daily_performance_entries(uuid)
to authenticated;

grant execute on function
    public.get_candidate_daily_performance_entries(uuid)
to service_role;

commit;
