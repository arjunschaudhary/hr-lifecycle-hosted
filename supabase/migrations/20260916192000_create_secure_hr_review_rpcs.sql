begin;

create table public.performance_review_revisions (
    id uuid primary key default gen_random_uuid(),
    performance_review_id uuid not null,
    candidate_cycle_id uuid not null,
    review_type text not null,
    previous_scores jsonb not null,
    new_scores jsonb not null,
    previous_total_score smallint not null,
    new_total_score smallint not null,
    amendment_reason text not null,
    amended_by uuid not null,
    amended_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    constraint performance_review_revisions_review_fk
        foreign key (performance_review_id)
        references public.performance_reviews(id)
        on delete restrict,
    constraint performance_review_revisions_candidate_cycle_fk
        foreign key (candidate_cycle_id)
        references public.candidate_performance_cycles(id)
        on delete restrict,
    constraint performance_review_revisions_amended_by_fk
        foreign key (amended_by)
        references public.users(id)
        on delete restrict,
    constraint performance_review_revisions_review_type_check
        check (review_type in ('HR', 'LEAD')),
    constraint performance_review_revisions_reason_not_blank_check
        check (btrim(amendment_reason) <> ''),
    constraint performance_review_revisions_previous_scores_object_check
        check (jsonb_typeof(previous_scores) = 'object'),
    constraint performance_review_revisions_new_scores_object_check
        check (jsonb_typeof(new_scores) = 'object')
);

comment on table public.performance_review_revisions is
    'Stores append-only before-and-after score snapshots for submitted performance-review amendments. Restrictive foreign keys preserve the review, candidate-cycle, and reviewer identities required for audit history.';

comment on column public.performance_review_revisions.amendment_reason is
    'Records the required nonblank business reason for changing a submitted performance review.';

create index idx_performance_review_revisions_review_amended
    on public.performance_review_revisions (
        performance_review_id,
        amended_at
    );

create index idx_performance_review_revisions_candidate_cycle_amended
    on public.performance_review_revisions (
        candidate_cycle_id,
        amended_at
    );

alter table public.performance_review_revisions enable row level security;

revoke all privileges on table public.performance_review_revisions from public;
revoke all privileges on table public.performance_review_revisions from anon;
revoke all privileges on table public.performance_review_revisions from authenticated;
grant select, insert on table public.performance_review_revisions to service_role;

create or replace function public.reject_performance_review_revision_mutation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
begin
    raise exception using
        errcode = '55000',
        message = 'Performance review revision history is immutable.';
end;
$function$;

comment on function public.reject_performance_review_revision_mutation() is
    'Rejects updates and deletes so performance-review revision history remains immutable after insertion.';

revoke execute on function
    public.reject_performance_review_revision_mutation()
from public;

revoke execute on function
    public.reject_performance_review_revision_mutation()
from anon;

revoke execute on function
    public.reject_performance_review_revision_mutation()
from authenticated;

create trigger performance_review_revisions_immutable
before update or delete on public.performance_review_revisions
for each row
execute function public.reject_performance_review_revision_mutation();

create or replace function public.get_hr_review_tasks()
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    email text,
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
    result_status text,
    eligible_days integer,
    scored_days integer,
    daily_component_score numeric,
    daily_scoring_complete boolean,
    review_is_open boolean,
    review_id uuid,
    review_status text,
    task_status text,
    reviewer_user_id uuid,
    reviewer_name text,
    communication_professionalism_score smallint,
    attendance_update_discipline_score smallint,
    reporting_policy_compliance_score smallint,
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
            message = 'HR review workspace access is not available.';
    end if;

    v_current_user_id := public.current_app_user_id();

    if v_current_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'HR review workspace access is not available.';
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

    return query
    select
        cpc.id::uuid as candidate_cycle_id,
        cpc.candidate_id::uuid,
        mc.full_name::text,
        mc.email::text,
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
        cpc.result_status::text,
        cpc.eligible_days::integer,
        cpc.scored_days::integer,
        cpc.daily_component_score::numeric,
        review_state.daily_scoring_complete,
        review_state.review_is_open,
        pr.id::uuid as review_id,
        pr.review_status::text,
        case
            when review_state.is_protected then 'PROTECTED'
            when pr.review_status = 'SUBMITTED' then 'SUBMITTED'
            when pr.review_status = 'DRAFT' then 'DRAFT'
            when not review_state.daily_scoring_complete then
                'WAITING_FOR_DAILY_SCORING'
            when not review_state.review_is_open then 'NOT_OPEN'
            else 'READY'
        end::text as task_status,
        pr.reviewer_user_id::uuid,
        reviewer.name::text as reviewer_name,
        pr.communication_professionalism_score::smallint,
        pr.attendance_update_discipline_score::smallint,
        pr.reporting_policy_compliance_score::smallint,
        pr.total_score::smallint,
        pr.reviewer_comment::text,
        pr.submitted_at::timestamptz,
        pr.created_at::timestamptz as review_created_at,
        pr.updated_at::timestamptz as review_updated_at,
        (
            review_state.daily_scoring_complete
            and review_state.review_is_open
            and not review_state.is_protected
        ) as can_edit
    from public.candidate_performance_cycles cpc
    join public.master_candidates mc
        on mc.candidate_id = cpc.candidate_id
    join public.performance_cycles pc
        on pc.id = cpc.cycle_id
    join public.pods p
        on p.id = cpc.pod_id
    cross join lateral (
        select
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
                    'FINALIZED',
                    'LOCKED'
                )
            ) as review_is_open,
            (
                pc.cycle_status in ('FINALIZED', 'LOCKED')
                or cpc.result_status in ('FINALIZED', 'LOCKED')
            ) as is_protected
    ) review_state
    left join public.performance_reviews pr
        on pr.candidate_cycle_id = cpc.id
       and pr.review_type = 'HR'
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id
    where v_has_elevated_access
       or exists (
           select 1
           from public.pod_memberships pm
           where pm.user_id = v_current_user_id
             and pm.pod_id = cpc.pod_id
             and pm.candidate_id is null
             and pm.membership_type = 'HR_SITE_CONNECT'
             and pm.is_active = true
             and pm.effective_from <= current_date
             and (
                 pm.effective_to is null
                 or pm.effective_to >= current_date
             )
       )
    order by
        pc.review_open_date desc,
        p.pod_name asc,
        mc.full_name asc,
        cpc.id asc;
end;
$function$;

comment on function public.get_hr_review_tasks() is
    'Returns pod-scoped HR Review tasks to plain active HR_SITE_CONNECT users and organization-wide tasks to active elevated HR reviewers. It exposes only HR Review fields and performs no write action.';

revoke execute on function public.get_hr_review_tasks() from public;
revoke execute on function public.get_hr_review_tasks() from anon;
grant execute on function public.get_hr_review_tasks() to authenticated;
grant execute on function public.get_hr_review_tasks() to service_role;

create or replace function public.get_candidate_hr_review(
    p_candidate_cycle_id uuid
)
returns table (
    candidate_cycle_id uuid,
    candidate_id uuid,
    full_name text,
    email text,
    applied_role text,
    role_code text,
    cycle_id uuid,
    cycle_code text,
    cycle_number integer,
    cycle_start_date date,
    cycle_end_date date,
    cycle_status text,
    review_open_date date,
    lock_date date,
    pod_id uuid,
    pod_code text,
    pod_name text,
    evaluation_start_date date,
    evaluation_end_date date,
    result_status text,
    eligible_days integer,
    scored_days integer,
    daily_component_score numeric,
    daily_scoring_complete boolean,
    review_is_open boolean,
    review_id uuid,
    communication_professionalism_score smallint,
    attendance_update_discipline_score smallint,
    reporting_policy_compliance_score smallint,
    total_score smallint,
    reviewer_comment text,
    review_status text,
    reviewer_user_id uuid,
    reviewer_name text,
    submitted_at timestamptz,
    review_created_at timestamptz,
    review_updated_at timestamptz,
    task_status text,
    can_edit boolean,
    edit_reason text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_assignment record;
    v_current_user_id uuid;
    v_has_elevated_access boolean;
    v_daily_scoring_complete boolean;
    v_review_is_open boolean;
    v_is_protected boolean;
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
            message = 'HR review access is not available.';
    end if;

    if p_candidate_cycle_id is null then
        raise exception 'p_candidate_cycle_id must not be null.'
            using errcode = '22004';
    end if;

    v_current_user_id := public.current_app_user_id();

    if v_current_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'HR review access is not available.';
    end if;

    begin
        select
            cpc.id as candidate_cycle_id,
            cpc.candidate_id,
            mc.full_name,
            mc.email,
            mc.applied_role,
            mc.role_code,
            cpc.cycle_id,
            pc.cycle_code,
            pc.cycle_number,
            pc.start_date as cycle_start_date,
            pc.end_date as cycle_end_date,
            pc.cycle_status,
            pc.review_open_date,
            pc.lock_date,
            cpc.pod_id,
            p.pod_code,
            p.pod_name,
            cpc.evaluation_start_date,
            cpc.evaluation_end_date,
            cpc.result_status,
            cpc.eligible_days,
            cpc.scored_days,
            cpc.daily_component_score
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
           where pm.user_id = v_current_user_id
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
            message = 'HR review access is not available.';
    end if;

    v_daily_scoring_complete :=
        v_assignment.eligible_days > 0
        and v_assignment.scored_days = v_assignment.eligible_days
        and v_assignment.daily_component_score is not null;

    v_is_protected :=
        v_assignment.cycle_status in ('FINALIZED', 'LOCKED')
        or v_assignment.result_status in ('FINALIZED', 'LOCKED');

    v_review_is_open :=
        current_date >= v_assignment.review_open_date
        and v_assignment.cycle_status not in (
            'DRAFT',
            'FINALIZED',
            'LOCKED'
        )
        and v_assignment.result_status not in ('FINALIZED', 'LOCKED');

    return query
    select
        v_assignment.candidate_cycle_id::uuid,
        v_assignment.candidate_id::uuid,
        v_assignment.full_name::text,
        v_assignment.email::text,
        v_assignment.applied_role::text,
        v_assignment.role_code::text,
        v_assignment.cycle_id::uuid,
        v_assignment.cycle_code::text,
        v_assignment.cycle_number::integer,
        v_assignment.cycle_start_date::date,
        v_assignment.cycle_end_date::date,
        v_assignment.cycle_status::text,
        v_assignment.review_open_date::date,
        v_assignment.lock_date::date,
        v_assignment.pod_id::uuid,
        v_assignment.pod_code::text,
        v_assignment.pod_name::text,
        v_assignment.evaluation_start_date::date,
        v_assignment.evaluation_end_date::date,
        v_assignment.result_status::text,
        v_assignment.eligible_days::integer,
        v_assignment.scored_days::integer,
        v_assignment.daily_component_score::numeric,
        v_daily_scoring_complete,
        v_review_is_open,
        pr.id::uuid,
        pr.communication_professionalism_score::smallint,
        pr.attendance_update_discipline_score::smallint,
        pr.reporting_policy_compliance_score::smallint,
        pr.total_score::smallint,
        pr.reviewer_comment::text,
        pr.review_status::text,
        pr.reviewer_user_id::uuid,
        reviewer.name::text,
        pr.submitted_at::timestamptz,
        pr.created_at::timestamptz,
        pr.updated_at::timestamptz,
        case
            when v_is_protected then 'PROTECTED'
            when pr.review_status = 'SUBMITTED' then 'SUBMITTED'
            when pr.review_status = 'DRAFT' then 'DRAFT'
            when not v_daily_scoring_complete then
                'WAITING_FOR_DAILY_SCORING'
            when not v_review_is_open then 'NOT_OPEN'
            else 'READY'
        end::text,
        (
            v_daily_scoring_complete
            and v_review_is_open
            and not v_is_protected
        ),
        case
            when v_is_protected then
                'HR review is protected for this candidate cycle.'
            when not v_daily_scoring_complete then
                'Daily performance scoring must be complete before HR review.'
            when not v_review_is_open then
                'HR review is not open yet.'
            when pr.review_status = 'SUBMITTED' then
                'A nonblank amendment reason is required to change this submitted HR review.'
            else null::text
        end
    from (values (1)) as single_row(anchor)
    left join public.performance_reviews pr
        on pr.candidate_cycle_id = v_assignment.candidate_cycle_id
       and pr.review_type = 'HR'
    left join public.users reviewer
        on reviewer.id = pr.reviewer_user_id;
end;
$function$;

comment on function public.get_candidate_hr_review(uuid) is
    'Returns one authorized candidate-cycle HR Review with candidate, cycle, pod, scoring readiness, reviewer identity, amendment availability, and HR-only review fields. Lead Review component scores are not exposed.';

revoke execute on function public.get_candidate_hr_review(uuid) from public;
revoke execute on function public.get_candidate_hr_review(uuid) from anon;
grant execute on function public.get_candidate_hr_review(uuid) to authenticated;
grant execute on function public.get_candidate_hr_review(uuid) to service_role;

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

    v_new_total_score :=
        coalesce(p_communication_professionalism_score, 0)
        + coalesce(p_attendance_update_discipline_score, 0)
        + coalesce(p_reporting_policy_compliance_score, 0);

    if v_new_total_score not between 0 and 15 then
        raise exception 'HR review total must be between 0 and 15.'
            using errcode = '22003';
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
        v_hr_total_changed :=
            v_existing_review.total_score is distinct from v_new_total_score;

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
            total_score = v_new_total_score,
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
            total_score,
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
            v_new_total_score,
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

    if v_is_amendment then
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
            from public.refresh_candidate_cycle_result_status(
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

commit;
