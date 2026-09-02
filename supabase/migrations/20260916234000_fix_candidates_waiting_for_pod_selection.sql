begin;

create or replace function public.get_candidates_waiting_for_pod()
returns table (
    candidate_id uuid,
    full_name text,
    email text,
    lifecycle_status text,
    probation_start_date date,
    required_evaluation_start_date date,
    performance_job_id uuid,
    performance_job_status text,
    performance_job_error text,
    has_active_portal_account boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
    v_business_date date :=
        (current_timestamp at time zone 'Asia/Kolkata')::date;
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(
           public.current_user_has_any_role(
               array['ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT_LEAD']::text[]
           ),
           false
       ) then
        raise exception using
            errcode = '42501',
            message = 'Pod Management access is not permitted.';
    end if;

    return query
    select
        c.candidate_id,
        c.full_name::text,
        c.email::text,
        hl.lifecycle_status::text,
        hl.probation_start_date,
        case
            when pc.start_date is null then hl.probation_start_date
            when hl.probation_start_date is null then pc.start_date
            else greatest(pc.start_date, hl.probation_start_date)
        end,
        aj.job_id,
        aj.job_status::text,
        aj.error_message::text,
        (
            cua.id is not null
            and u.status = 'active'
        )
    from public.master_candidates c
    join public.hr_lifecycle hl
        on hl.candidate_id = c.candidate_id
    join lateral (
        select
            job.job_id,
            job.job_status,
            job.error_message,
            job.payload
        from public.automation_jobs job
        where job.candidate_id = c.candidate_id
          and job.job_type = 'PERFORMANCE_CYCLE_ASSIGNMENT'
          and job.job_status in ('PENDING', 'RETRY')
          and job.payload ->> 'pending_reason' = 'POD_MEMBERSHIP'
        order by job.created_at desc, job.job_id desc
        limit 1
    ) aj on true
    left join public.performance_cycles pc
        on pc.id::text = aj.payload ->> 'cycle_id'
    left join public.candidate_user_accounts cua
        on cua.candidate_id = c.candidate_id
       and cua.account_status = 'ACTIVE'
       and cua.deactivated_at is null
       and cua.activated_at <= pg_catalog.now()
    left join public.users u
        on u.id = cua.user_id
    where public.candidate_new_assignment_block_reason(c.candidate_id) is null
      and not exists (
          select 1
          from public.pod_memberships pm
          where pm.candidate_id = c.candidate_id
            and pm.membership_type = 'CANDIDATE'
            and pm.is_active = true
            and pm.effective_from <= v_business_date
            and (
                pm.effective_to is null
                or pm.effective_to >= v_business_date
            )
      )
    order by hl.probation_start_date asc nulls last, c.full_name asc;
end;
$function$;

commit;
