begin;

create or replace function public.get_current_candidate_leave_requests()
returns table (
    leave_request_id uuid,
    leave_type text,
    start_date date,
    end_date date,
    requested_leave_days integer,
    reason text,
    supporting_document text,
    leave_status text,
    created_at timestamptz,
    updated_at timestamptz,
    approved_at timestamptz,
    rejected_at timestamptz
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
            using message = 'Candidate leave access is not available.';
    end if;

    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate leave access is not available.';
    end if;

    return query
    select
        lr.leave_request_id,
        lr.leave_type::text,
        lr.start_date,
        lr.end_date,
        lr.requested_leave_days,
        lr.reason,
        lr.supporting_document,
        lr.leave_status::text,
        lr.created_at,
        lr.updated_at,
        lr.approved_at,
        lr.rejected_at
    from public.leave_requests lr
    where lr.candidate_id = v_candidate_id
    order by lr.created_at desc nulls last,
             lr.leave_request_id desc;
end;
$function$;

comment on function public.get_current_candidate_leave_requests() is
    'Returns only the leave-request history belonging to the current active candidate mapping. Candidate identity is resolved server-side and no other candidate records are exposed.';

revoke execute on function public.get_current_candidate_leave_requests() from public;
revoke execute on function public.get_current_candidate_leave_requests() from anon;
grant execute on function public.get_current_candidate_leave_requests() to authenticated;
grant execute on function public.get_current_candidate_leave_requests() to service_role;

create or replace function public.submit_current_candidate_leave_request(
    p_leave_type text,
    p_start_date date,
    p_end_date date,
    p_reason text,
    p_supporting_document text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_candidate_id uuid;
    v_lifecycle_status text;
    v_mid text;
    v_internship_duration_months integer;
    v_extension_months integer;
    v_allocated_leave_days integer;
    v_approved_leave_days integer;
    v_remaining_leave_days integer;
    v_extra_leave_days integer;
    v_requested_leave_days integer;
    v_leave_type text;
    v_reason text;
    v_supporting_document text;
    v_balance public.leave_balances%rowtype;
    v_balance_exists boolean := false;
    v_request public.leave_requests%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(public.current_user_has_role('CANDIDATE'), false) then
        raise insufficient_privilege
            using message = 'Candidate leave access is not available.';
    end if;

    v_actor_user_id := public.current_app_user_id();
    v_candidate_id := public.current_candidate_id();

    if v_actor_user_id is null or v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate leave access is not available.';
    end if;

    if p_start_date is null or p_end_date is null then
        raise exception 'Start date and end date are required.'
            using errcode = '22004';
    end if;

    if p_end_date < p_start_date then
        raise exception 'Start date cannot be after end date.'
            using errcode = '22007';
    end if;

    v_leave_type := nullif(btrim(p_leave_type), '');
    v_reason := nullif(btrim(p_reason), '');
    v_supporting_document := nullif(btrim(p_supporting_document), '');

    if v_leave_type is null
       or v_leave_type not in (
           'Casual Leave',
           'Sick Leave',
           'Emergency Leave'
       ) then
        raise exception 'Leave type is not available.'
            using errcode = '23514';
    end if;

    if v_reason is null then
        raise exception 'Reason is required.'
            using errcode = '23514';
    end if;

    if v_supporting_document is not null
       and v_supporting_document !~* '^https?://[^[:space:]]+$' then
        raise exception 'Supporting document link must use HTTP or HTTPS.'
            using errcode = '23514';
    end if;

    select count(*)::integer
    into v_requested_leave_days
    from pg_catalog.generate_series(
        p_start_date::timestamp,
        p_end_date::timestamp,
        interval '1 day'
    ) as generated_dates(generated_date)
    where extract(isodow from generated_dates.generated_date) <> 7;

    if v_requested_leave_days <= 0 then
        raise exception 'Selected dates do not include an eligible leave day.'
            using errcode = '23514';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'candidate-leave:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select
            hl.lifecycle_status::text,
            hl.mid::text,
            hl.internship_duration_months
        into strict
            v_lifecycle_status,
            v_mid,
            v_internship_duration_months
        from public.hr_lifecycle hl
        where hl.candidate_id = v_candidate_id
        for share;
    exception
        when no_data_found then
            raise exception 'Candidate lifecycle record is not available.'
                using errcode = 'P0001';
        when too_many_rows then
            raise exception 'Candidate has multiple lifecycle records.'
                using errcode = 'P0001';
    end;

    if v_lifecycle_status not in (
        'HR_APPROVED_FOR_PROBATION',
        'WELCOME_MAIL_SENT',
        'IN_PROBATION',
        'PROBATION_REVIEW',
        'PROBATION_EXTENDED',
        'PROBATION_PASSED',
        'MID_GENERATED',
        'OFFER_LETTER_GENERATED',
        'OFFER_LETTER_SENT',
        'ACTIVE',
        'SIGNED_OFFER_SUBMITTED',
        'SIGNED_OFFER_VERIFIED',
        'MISMATCH_REVIEW'
    ) then
        raise exception 'Candidate is not eligible to apply for leave.'
            using errcode = '23514';
    end if;

    select coalesce(sum(ie.extension_value), 0)::integer
    into v_extension_months
    from public.internship_extensions ie
    where ie.candidate_id = v_candidate_id
      and ie.extension_type = 'MONTHS'
      and ie.is_processed is true;

    v_allocated_leave_days := case v_internship_duration_months
        when 3 then 9 + (v_extension_months * 3)
        when 4 then 15 + (v_extension_months * 3)
        else null
    end;

    if v_allocated_leave_days is null then
        raise exception 'Leave entitlement is defined only for 3 or 4 month internships.'
            using errcode = '23514';
    end if;

    select lb.*
    into v_balance
    from public.leave_balances lb
    where lb.candidate_id = v_candidate_id
    for update;

    v_balance_exists := found;

    if exists (
        select 1
        from public.leave_requests pending_request
        where pending_request.candidate_id = v_candidate_id
          and pending_request.leave_status = 'PENDING'
    ) then
        raise exception 'You already have a pending leave request. Wait for HR to review it before submitting another.'
            using errcode = '23514';
    end if;

    v_approved_leave_days := coalesce(v_balance.approved_leave_days, 0);
    v_extra_leave_days := coalesce(v_balance.extra_leave_days, 0);
    v_remaining_leave_days := greatest(
        v_allocated_leave_days - v_approved_leave_days,
        0
    );

    if v_requested_leave_days > v_remaining_leave_days
       and v_supporting_document is null then
        raise exception 'A supporting document link is required when requested leave exceeds the remaining balance.'
            using errcode = '23514';
    end if;

    if exists (
        select 1
        from public.leave_requests existing_request
        where existing_request.candidate_id = v_candidate_id
          and existing_request.leave_status in ('PENDING', 'APPROVED')
          and existing_request.start_date <= p_end_date
          and existing_request.end_date >= p_start_date
    ) then
        raise exception 'This leave request overlaps with an existing leave request.'
            using errcode = '23514';
    end if;

    if v_balance_exists then
        update public.leave_balances
        set
            allocated_leave_days = v_allocated_leave_days,
            approved_leave_days = v_approved_leave_days,
            remaining_leave_days = v_remaining_leave_days,
            extra_leave_days = v_extra_leave_days,
            updated_at = v_now
        where candidate_id = v_candidate_id;
    else
        insert into public.leave_balances (
            candidate_id,
            mid,
            allocated_leave_days,
            approved_leave_days,
            remaining_leave_days,
            extra_leave_days,
            created_at,
            updated_at
        )
        values (
            v_candidate_id,
            v_mid,
            v_allocated_leave_days,
            0,
            v_allocated_leave_days,
            0,
            v_now,
            v_now
        );

        v_approved_leave_days := 0;
        v_remaining_leave_days := v_allocated_leave_days;
        v_extra_leave_days := 0;
    end if;

    insert into public.leave_requests (
        candidate_id,
        mid,
        leave_type,
        start_date,
        end_date,
        requested_leave_days,
        reason,
        supporting_document,
        leave_status,
        created_at,
        updated_at
    )
    values (
        v_candidate_id,
        v_mid,
        v_leave_type,
        p_start_date,
        p_end_date,
        v_requested_leave_days,
        v_reason,
        v_supporting_document,
        'PENDING',
        v_now,
        v_now
    )
    returning * into v_request;

    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        from_status,
        to_status,
        remarks,
        activity_status,
        metadata,
        performed_by,
        performed_at,
        created_at,
        updated_at
    )
    values (
        v_candidate_id,
        'LEAVE_APPLIED',
        null,
        'PENDING',
        'Leave application submitted.',
        'SUCCESS',
        jsonb_build_object(
            'leave_request_id', v_request.leave_request_id,
            'leave_type', v_request.leave_type,
            'start_date', v_request.start_date,
            'end_date', v_request.end_date,
            'requested_leave_days', v_request.requested_leave_days,
            'remaining_leave_days', v_remaining_leave_days,
            'supporting_document_provided', v_supporting_document is not null
        ),
        v_actor_user_id::text,
        v_now,
        v_now,
        v_now
    );

    return jsonb_build_object(
        'leaveRequestId', v_request.leave_request_id,
        'leaveType', v_request.leave_type,
        'startDate', v_request.start_date,
        'endDate', v_request.end_date,
        'requestedLeaveDays', v_request.requested_leave_days,
        'reason', v_request.reason,
        'supportingDocument', v_request.supporting_document,
        'leaveStatus', v_request.leave_status,
        'createdAt', v_request.created_at
    );
end;
$function$;

comment on function public.submit_current_candidate_leave_request(text, date, date, text, text) is
    'Creates one pending leave request for the current active candidate mapping. It preserves the existing Sunday exclusion, leave entitlement, overlap, and balance-maintenance rules, requires a supporting-document link for leave beyond the remaining balance, and never accepts a candidate identifier from the caller.';

revoke execute on function public.submit_current_candidate_leave_request(text, date, date, text, text) from public;
revoke execute on function public.submit_current_candidate_leave_request(text, date, date, text, text) from anon;
grant execute on function public.submit_current_candidate_leave_request(text, date, date, text, text) to authenticated;
grant execute on function public.submit_current_candidate_leave_request(text, date, date, text, text) to service_role;

commit;
