begin;

-- Create the private storage bucket for candidate leave documents
insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
) values (
    'candidate-leave-documents',
    'candidate-leave-documents',
    false,
    10485760, -- 10 MB limit
    array['application/pdf']::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = 10485760,
    allowed_mime_types = array['application/pdf']::text[];

-- Create storage policies for candidate-leave-documents
drop policy if exists candidate_leave_objects_candidate_insert on storage.objects;
drop policy if exists candidate_leave_objects_candidate_select on storage.objects;
drop policy if exists candidate_leave_objects_candidate_delete_orphan on storage.objects;
drop policy if exists candidate_leave_objects_staff_select on storage.objects;

-- Insert policy: Candidates can upload only PDFs to their own folder path
create policy candidate_leave_objects_candidate_insert
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'candidate-leave-documents'
    and public.current_user_is_active() is true
    and public.current_user_has_role('CANDIDATE') is true
    and public.current_candidate_id() is not null
    and exists (
        select 1
        from public.hr_lifecycle l
        where l.candidate_id = public.current_candidate_id()
          and l.lifecycle_status in (
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
          )
    )
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and (storage.foldername(name))[3] = 'leave-documents'
    and storage.filename(name) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.pdf$'
);

-- Select policy: Candidates can read only their own leave documents
create policy candidate_leave_objects_candidate_select
on storage.objects
for select
to authenticated
using (
    bucket_id = 'candidate-leave-documents'
    and public.current_user_is_active() is true
    and public.current_user_has_role('CANDIDATE') is true
    and public.current_candidate_id() is not null
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and (storage.foldername(name))[3] = 'leave-documents'
);

-- Delete policy: Candidates can delete their own uploaded documents only if they are orphaned (i.e. not linked to any submitted leave request yet)
create policy candidate_leave_objects_candidate_delete_orphan
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'candidate-leave-documents'
    and public.current_user_is_active() is true
    and public.current_user_has_role('CANDIDATE') is true
    and public.current_candidate_id() is not null
    and array_length(storage.foldername(name), 1) = 3
    and (storage.foldername(name))[1] = 'candidate'
    and (storage.foldername(name))[2] = public.current_candidate_id()::text
    and (storage.foldername(name))[3] = 'leave-documents'
    and owner_id = auth.uid()::text
    and not exists (
        select 1
        from public.leave_requests lr
        where lr.supporting_document = storage.objects.name
    )
);

-- Staff select policy: Staff roles can view all files in candidate-leave-documents
create policy candidate_leave_objects_staff_select
on storage.objects
for select
to authenticated
using (
    bucket_id = 'candidate-leave-documents'
    and public.current_user_is_active()
    and public.current_user_has_any_role(
        array[
            'HR_SITE_CONNECT',
            'HR_SITE_CONNECT_LEAD',
            'HR_EXECUTIVE',
            'HR_EXECUTIVE_LEAD',
            'HR_LEAD',
            'FOUNDERS_OFFICE',
            'ADMIN'
        ]::text[]
    )
);

-- Re-create public.submit_current_candidate_leave_request with support for storage path
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

    if v_supporting_document is not null then
        -- Allow either standard HTTP/HTTPS URLs (for backward compatibility / HR entries) OR candidate folder storage path matching current candidate ID
        if v_supporting_document !~* '^https?://[^[:space:]]+$' then
            if v_supporting_document !~* '^candidate/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/leave-documents/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.pdf$'
               or split_part(v_supporting_document, '/', 2)::uuid <> v_candidate_id then
                raise exception 'Supporting document must be a valid URL or candidate storage path.'
                    using errcode = '23514';
            end if;
        end if;
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

commit;
