begin;

create or replace function public.get_lead_review_tasks()
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    applied_role text,
    role_code text,
    cycle_id uuid,
    cycle_code text,
    cycle_number integer,
    cycle_start_date date,
    cycle_end_date date,
    review_open_date date,
    lock_date date,
    cycle_status text,
    pod_id uuid,
    pod_code text,
    pod_name text,
    evaluation_start_date date,
    evaluation_end_date date,
    is_partial_cycle boolean,
    eligible_days integer,
    scored_days integer,
    daily_component_score numeric,
    daily_scoring_complete boolean,
    review_is_open boolean,
    review_id uuid,
    review_status text,
    review_display_status text,
    reviewer_user_id uuid,
    reviewer_name text,
    work_quality_score smallint,
    role_capability_score smallint,
    deadline_delivery_score smallint,
    ownership_teamwork_score smallint,
    total_score smallint,
    reviewer_comment text,
    submitted_at timestamptz,
    review_created_at timestamptz,
    review_updated_at timestamptz,
    can_edit boolean
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_current_user_id uuid;
begin
    if not coalesce(public.current_user_is_active(), false) then
        raise exception using
            errcode = '42501',
            message = 'Lead review workspace access is not available.';
    end if;

    v_current_user_id := public.current_app_user_id();

    if v_current_user_id is null
       or not coalesce(
           public.current_user_has_any_role(
               array[
                   'POD_LEAD',
                   'TECH_LEAD'
               ]::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Lead review workspace access is not available.';
    end if;

    return query
    select
        cpc.id::uuid as candidate_cycle_id,
        cpc.candidate_id::uuid,
        mc.full_name::text,
        mc.applied_role::text,
        mc.role_code::text,
        cpc.cycle_id::uuid,
        pc.cycle_code::text,
        pc.cycle_number::integer,
        pc.start_date::date as cycle_start_date,
        pc.end_date::date as cycle_end_date,
        pc.review_open_date::date,
        pc.lock_date::date,
        pc.cycle_status::text,
        cpc.pod_id::uuid,
        p.pod_code::text,
        p.pod_name::text,
        cpc.evaluation_start_date::date,
        cpc.evaluation_end_date::date,
        cpc.is_partial_cycle::boolean,
        cpc.eligible_days::integer,
        cpc.scored_days::integer,
        cpc.daily_component_score::numeric,
        (
            cpc.eligible_days > 0
            and cpc.scored_days = cpc.eligible_days
            and cpc.daily_component_score is not null
        ) as daily_scoring_complete,
        (
            current_date >= pc.review_open_date
            and pc.cycle_status not in (
                'DRAFT',
                'FINALIZED',
                'LOCKED'
            )
            and cpc.result_status not in (
                'CANDIDATE_REVIEW',
                'FINALIZED',
                'LOCKED'
            )
            and cpc.final_score is null
            and cpc.performance_band is null
            and cpc.calculated_at is null
        ) as review_is_open,
        pr.id::uuid as review_id,
        pr.review_status::text,
        case
            when pr.review_status = 'SUBMITTED' then 'SUBMITTED'
            when pr.review_status = 'DRAFT' then 'DRAFT'
            when not (
                cpc.eligible_days > 0
                and cpc.scored_days = cpc.eligible_days
                and cpc.daily_component_score is not null
            ) then 'WAITING_FOR_DAILY_MARKING'
            else 'NOT_STARTED'
        end::text as review_display_status,
        pr.reviewer_user_id::uuid,
        reviewer.name::text as reviewer_name,
        pr.work_quality_score::smallint,
        pr.role_capability_score::smallint,
        pr.deadline_delivery_score::smallint,
        pr.ownership_teamwork_score::smallint,
        pr.total_score::smallint,
        pr.reviewer_comment::text,
        pr.submitted_at::timestamptz,
        pr.created_at::timestamptz as review_created_at,
        pr.updated_at::timestamptz as review_updated_at,
        (
            cpc.eligible_days > 0
            and cpc.scored_days = cpc.eligible_days
            and cpc.daily_component_score is not null
            and current_date >= pc.review_open_date
            and pc.cycle_status not in (
                'DRAFT',
                'FINALIZED',
                'LOCKED'
            )
            and cpc.result_status not in (
                'CANDIDATE_REVIEW',
                'FINALIZED',
                'LOCKED'
            )
            and cpc.final_score is null
            and cpc.performance_band is null
            and cpc.calculated_at is null
            and (
                pr.review_status is null
                or pr.review_status = 'DRAFT'
            )
        ) as can_edit
    from public.candidate_performance_cycles cpc
    join public.master_candidates mc
        on mc.candidate_id = cpc.candidate_id
    join public.performance_cycles pc
        on pc.id = cpc.cycle_id
    join public.pods p
        on p.id = cpc.pod_id
    left join public.performance_reviews pr
        on pr.candidate_cycle_id = cpc.id
       and pr.review_type = 'LEAD'
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id
    where (
        current_date >= pc.review_open_date
        or pr.id is not null
    )
      and exists (
          select 1
          from public.pod_memberships pm
          join public.user_roles ur
              on ur.user_id = pm.user_id
          join public.roles r
              on r.id = ur.role_id
             and r.slug = pm.membership_type
          where pm.pod_id = cpc.pod_id
            and pm.user_id = v_current_user_id
            and pm.candidate_id is null
            and pm.membership_type in (
                'POD_LEAD',
                'TECH_LEAD'
            )
            and pm.is_active = true
            and pm.effective_from <= current_date
            and (
                pm.effective_to is null
                or pm.effective_to >= current_date
            )
            and ur.is_active = true
            and ur.ended_at is null
            and r.is_active = true
      )
    order by
        pc.review_open_date desc,
        p.pod_name asc,
        mc.full_name asc,
        cpc.id asc;
end;
$function$;

comment on function public.get_lead_review_tasks() is
    'Returns the logged-in Pod Lead or Tech Lead user''s pod-scoped Lead Review task list, exposes no unnecessary candidate contact or HR-only result data, and performs no write action.';

revoke execute on function public.get_lead_review_tasks() from public;
revoke execute on function public.get_lead_review_tasks() from anon;
grant execute on function public.get_lead_review_tasks() to authenticated;
grant execute on function public.get_lead_review_tasks() to service_role;

commit;
