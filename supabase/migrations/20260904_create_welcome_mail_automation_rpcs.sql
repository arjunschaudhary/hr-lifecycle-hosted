create or replace function public.claim_welcome_mail_job(
    p_candidate_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_candidate public.master_candidates%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_job public.automation_jobs%rowtype;
    v_now timestamptz := pg_catalog.now();
    v_idempotency_key text;
    v_email text;
    v_full_name text;
    v_stale_processing_timeout interval := interval '15 minutes';
    v_should_send boolean := false;
    v_needs_finalization boolean := false;
begin
    if p_candidate_id is null then
        raise exception using
            errcode = '22023',
            message = 'Candidate ID is required.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if public.current_user_is_active() is not true
       or v_actor_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'Active application-user authorization is required.';
    end if;

    if public.current_user_has_any_role(
        array[
            'HR_SITE_CONNECT',
            'HR_SITE_CONNECT_LEAD',
            'HR_EXECUTIVE',
            'HR_EXECUTIVE_LEAD',
            'HR_LEAD',
            'FOUNDERS_OFFICE',
            'ADMIN'
        ]::text[]
    ) is not true then
        raise exception using
            errcode = '42501',
            message = 'An approved staff role is required.';
    end if;

    -- Serialize claims for one candidate before inspecting lifecycle or job state.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'welcome-mail:' || p_candidate_id::text,
            0::bigint
        )
    );

    begin
        select c.*
        into strict v_candidate
        from public.master_candidates c
        where c.candidate_id = p_candidate_id
        for share;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate was not found.';
    end;

    v_full_name := nullif(pg_catalog.btrim(v_candidate.full_name), '');
    v_email := nullif(
        pg_catalog.lower(pg_catalog.btrim(v_candidate.email)),
        ''
    );

    if v_full_name is null then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate full name is not available.';
    end if;

    if v_email is null
       or v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate email is not valid for welcome-email delivery.';
    end if;

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = p_candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    v_idempotency_key := 'WELCOME_MAIL:' || p_candidate_id::text;

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.idempotency_key = v_idempotency_key
    for update;

    if v_job.job_id is not null
       and v_job.job_type is distinct from 'WELCOME_MAIL' then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email idempotency key is assigned to another job type.';
    end if;

    if v_job.job_id is not null
       and v_job.candidate_id is distinct from p_candidate_id then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email job candidate does not match the request.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        if v_lifecycle.lifecycle_status
           is distinct from 'WELCOME_MAIL_SENT' then
            raise exception using
                errcode = 'P0001',
                message = 'Welcome-email automation state is inconsistent.';
        end if;

        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', v_candidate.candidate_id,
            'idempotencyKey', v_job.idempotency_key,
            'jobStatus', v_job.job_status,
            'attemptCount', v_job.attempt_count,
            'shouldSend', false,
            'needsFinalization', false,
            'fullName', v_full_name,
            'email', v_email,
            'appliedRole', v_candidate.applied_role,
            'joiningDate', v_lifecycle.probation_start_date,
            'probationEndDate', v_lifecycle.probation_end_date,
            'internshipDurationMonths',
                v_lifecycle.internship_duration_months,
            'expectedEndDate',
                coalesce(
                    v_lifecycle.current_end_date,
                    v_lifecycle.original_end_date
                )
        );
    end if;

    if v_lifecycle.lifecycle_status
       is distinct from 'HR_APPROVED_FOR_PROBATION' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status must be HR_APPROVED_FOR_PROBATION.';
    end if;

    if v_job.job_status = 'CANCELLED' then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email job is cancelled.';
    end if;

    if (
        v_job.provider_message_id is null
        and v_job.provider_accepted_at is not null
    ) or (
        v_job.provider_message_id is not null
        and v_job.provider_accepted_at is null
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email provider acceptance state is inconsistent.';
    end if;

    if v_job.job_id is null then
        insert into public.automation_jobs (
            candidate_id,
            job_type,
            job_status,
            payload,
            scheduled_at,
            attempt_count,
            completed_at,
            error_message,
            idempotency_key,
            requested_by,
            last_attempt_at,
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            'WELCOME_MAIL',
            'PROCESSING',
            '{}'::jsonb,
            v_now,
            1,
            null,
            null,
            v_idempotency_key,
            v_actor_user_id,
            v_now,
            v_now,
            v_now
        )
        returning * into v_job;

        v_should_send := true;
    elsif v_job.provider_message_id is not null
          and v_job.provider_accepted_at is not null then
        update public.automation_jobs
        set
            job_status = 'PROCESSING',
            attempt_count = attempt_count + 1,
            requested_by = v_actor_user_id,
            last_attempt_at = v_now,
            completed_at = null,
            error_message = null,
            updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;

        v_needs_finalization := true;
    elsif v_job.job_status = 'PROCESSING' then
        if coalesce(
            v_job.last_attempt_at,
            v_job.updated_at,
            v_job.created_at
        ) > v_now - v_stale_processing_timeout then
            raise exception using
                errcode = 'P0001',
                message = 'Welcome-email job is already being processed.';
        end if;

        raise exception using
            errcode = 'P0001',
            message = 'Previous welcome-email attempt has an unknown delivery outcome. Check the sender Sent folder before retrying.';
    elsif v_job.job_status in ('PENDING', 'FAILED', 'RETRY') then
        update public.automation_jobs
        set
            job_status = 'PROCESSING',
            attempt_count = attempt_count + 1,
            requested_by = v_actor_user_id,
            last_attempt_at = v_now,
            completed_at = null,
            error_message = null,
            updated_at = v_now
        where job_id = v_job.job_id
        returning * into v_job;

        v_should_send := true;
    else
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email job is not claimable.';
    end if;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_candidate.candidate_id,
        'idempotencyKey', v_job.idempotency_key,
        'jobStatus', v_job.job_status,
        'attemptCount', v_job.attempt_count,
        'shouldSend', v_should_send,
        'needsFinalization', v_needs_finalization,
        'fullName', v_full_name,
        'email', v_email,
        'appliedRole', v_candidate.applied_role,
        'joiningDate', v_lifecycle.probation_start_date,
        'probationEndDate', v_lifecycle.probation_end_date,
        'internshipDurationMonths',
            v_lifecycle.internship_duration_months,
        'expectedEndDate',
            coalesce(
                v_lifecycle.current_end_date,
                v_lifecycle.original_end_date
            )
    );
end;
$function$;

comment on function public.claim_welcome_mail_job(uuid) is
    'Authorizes approved staff, serializes one candidate welcome-email claim, returns database-owned recipient and internship data, blocks recent duplicate processing, blocks stale ambiguous attempts from automatic resend after 15 minutes, and prevents sending again after provider acceptance or success.';

create or replace function public.record_welcome_mail_provider_acceptance(
    p_job_id uuid,
    p_provider_message_id text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_provider_message_id text;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    v_provider_message_id := nullif(
        pg_catalog.btrim(p_provider_message_id),
        ''
    );

    if v_provider_message_id is null then
        raise exception using
            errcode = '22023',
            message = 'Provider message ID is required.';
    end if;

    if pg_catalog.char_length(v_provider_message_id) > 500 then
        raise exception using
            errcode = '22023',
            message = 'Provider message ID exceeds 500 characters.';
    end if;

    begin
        select aj.*
        into strict v_job
        from public.automation_jobs aj
        where aj.job_id = p_job_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Welcome-email automation job was not found.';
    end;

    if v_job.job_type is distinct from 'WELCOME_MAIL' then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a welcome-email job.';
    end if;

    if v_job.provider_message_id is not null
       and v_job.provider_message_id
           is distinct from v_provider_message_id then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email provider message ID conflicts with the stored value.';
    end if;

    if v_job.provider_message_id = v_provider_message_id
       and v_job.provider_accepted_at is not null then
        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'providerAccepted', true
        );
    end if;

    if v_job.provider_accepted_at is not null
       and v_job.provider_message_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email provider acceptance state is inconsistent.';
    end if;

    if v_job.job_status not in ('PROCESSING', 'RETRY') then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email job is not ready for provider acceptance.';
    end if;

    update public.automation_jobs
    set
        provider_message_id = v_provider_message_id,
        provider_accepted_at = v_now,
        job_status = 'RETRY',
        completed_at = null,
        error_message = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status,
        'providerAccepted', true
    );
end;
$function$;

comment on function public.record_welcome_mail_provider_acceptance(uuid, text) is
    'Records a non-secret provider message ID after the welcome email is accepted, preserves idempotency for repeated matching calls, and marks the job for database finalization without changing lifecycle state.';

create or replace function public.finalize_welcome_mail_success(
    p_job_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    begin
        select aj.candidate_id
        into strict v_candidate_id
        from public.automation_jobs aj
        where aj.job_id = p_job_id;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Welcome-email automation job was not found.';
    end;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'welcome-mail:' || v_candidate_id::text,
            0::bigint
        )
    );

    begin
        select aj.*
        into strict v_job
        from public.automation_jobs aj
        where aj.job_id = p_job_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Welcome-email automation job was not found.';
    end;

    if v_job.job_type is distinct from 'WELCOME_MAIL' then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a welcome-email job.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'candidateId', v_job.candidate_id,
            'jobStatus', v_job.job_status,
            'lifecycleStatus', 'WELCOME_MAIL_SENT',
            'providerAcceptedAt', v_job.provider_accepted_at,
            'completedAt', v_job.completed_at
        );
    end if;

    if v_job.provider_message_id is null
       or v_job.provider_accepted_at is null then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome email has not been accepted by the provider.';
    end if;

    if v_job.job_status not in ('PROCESSING', 'RETRY') then
        raise exception using
            errcode = 'P0001',
            message = 'Welcome-email job is not ready for finalization.';
    end if;

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_job.candidate_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle record was not found.';
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    if v_lifecycle.lifecycle_status
       is distinct from 'HR_APPROVED_FOR_PROBATION' then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status must be HR_APPROVED_FOR_PROBATION.';
    end if;

    update public.hr_lifecycle
    set
        lifecycle_status = 'WELCOME_MAIL_SENT',
        updated_at = v_now
    where lifecycle_id = v_lifecycle.lifecycle_id;

    insert into public.hr_activity_logs (
        candidate_id,
        activity_type,
        from_status,
        to_status,
        remarks,
        activity_status,
        performed_by,
        performed_at,
        created_at,
        updated_at
    ) values (
        v_job.candidate_id,
        'WELCOME_MAIL_SENT',
        'HR_APPROVED_FOR_PROBATION',
        'WELCOME_MAIL_SENT',
        'Welcome email sent successfully through secure automation',
        'SUCCESS',
        v_job.requested_by::text,
        v_now,
        v_now,
        v_now
    );

    update public.automation_jobs
    set
        job_status = 'SUCCESS',
        completed_at = v_now,
        error_message = null,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'candidateId', v_job.candidate_id,
        'jobStatus', v_job.job_status,
        'lifecycleStatus', 'WELCOME_MAIL_SENT',
        'providerAcceptedAt', v_job.provider_accepted_at,
        'completedAt', v_job.completed_at
    );
end;
$function$;

comment on function public.finalize_welcome_mail_success(uuid) is
    'After confirmed provider acceptance, atomically moves one candidate from HR_APPROVED_FOR_PROBATION to WELCOME_MAIL_SENT, inserts one success activity log, and completes the automation job. Repeated calls after SUCCESS do not add another log.';

create or replace function public.record_welcome_mail_failure(
    p_job_id uuid,
    p_error_message text,
    p_retryable boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_raw_error text;
    v_safe_error text;
    v_next_status text;
    v_now timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22023',
            message = 'Automation job ID is required.';
    end if;

    if p_retryable is null then
        raise exception using
            errcode = '22023',
            message = 'Retryable flag is required.';
    end if;

    begin
        select aj.*
        into strict v_job
        from public.automation_jobs aj
        where aj.job_id = p_job_id
        for update;
    exception
        when no_data_found then
            raise exception using
                errcode = 'P0001',
                message = 'Welcome-email automation job was not found.';
    end;

    if v_job.job_type is distinct from 'WELCOME_MAIL' then
        raise exception using
            errcode = 'P0001',
            message = 'Automation job is not a welcome-email job.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        return pg_catalog.jsonb_build_object(
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status
        );
    end if;

    if v_job.job_status = 'CANCELLED' then
        raise exception using
            errcode = 'P0001',
            message = 'Cancelled welcome-email job cannot record a failure.';
    end if;

    v_raw_error := pg_catalog.btrim(
        coalesce(p_error_message, '')
    );

    if v_raw_error = '' then
        v_safe_error := 'Welcome email delivery failed.';
    elsif v_raw_error ~ E'[\r\n]'
          or pg_catalog.lower(v_raw_error) ~
              '(authorization|bearer|api[ _-]?key|access[ _-]?token|refresh[ _-]?token|secret|password|cookie|headers?)'
          or pg_catalog.left(v_raw_error, 1) in ('{', '[') then
        v_safe_error :=
            'Welcome email provider request failed. Sensitive details were omitted.';
    else
        v_safe_error := pg_catalog.left(
            pg_catalog.regexp_replace(
                v_raw_error,
                '[[:space:]]+',
                ' ',
                'g'
            ),
            1000
        );
    end if;

    v_next_status := case
        when p_retryable then 'RETRY'
        else 'FAILED'
    end;

    update public.automation_jobs
    set
        job_status = v_next_status,
        completed_at = case
            when p_retryable then null
            else v_now
        end,
        error_message = v_safe_error,
        updated_at = v_now
    where job_id = v_job.job_id
    returning * into v_job;

    return pg_catalog.jsonb_build_object(
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status
    );
end;
$function$;

comment on function public.record_welcome_mail_failure(uuid, text, boolean) is
    'Stores a sanitized welcome-email failure or retry state without changing lifecycle data, clearing provider acceptance, or inserting a success activity log. Callers must pass only a safe summary, never credentials, tokens, headers, stack traces, or full provider responses.';

revoke execute on function public.claim_welcome_mail_job(uuid)
    from public;
revoke execute on function public.claim_welcome_mail_job(uuid)
    from anon;
revoke execute on function public.claim_welcome_mail_job(uuid)
    from authenticated;
grant execute on function public.claim_welcome_mail_job(uuid)
    to authenticated;
grant execute on function public.claim_welcome_mail_job(uuid)
    to service_role;

revoke execute on function public.record_welcome_mail_provider_acceptance(
    uuid,
    text
) from public;
revoke execute on function public.record_welcome_mail_provider_acceptance(
    uuid,
    text
) from anon;
revoke execute on function public.record_welcome_mail_provider_acceptance(
    uuid,
    text
) from authenticated;
grant execute on function public.record_welcome_mail_provider_acceptance(
    uuid,
    text
) to service_role;

revoke execute on function public.finalize_welcome_mail_success(uuid)
    from public;
revoke execute on function public.finalize_welcome_mail_success(uuid)
    from anon;
revoke execute on function public.finalize_welcome_mail_success(uuid)
    from authenticated;
grant execute on function public.finalize_welcome_mail_success(uuid)
    to service_role;

revoke execute on function public.record_welcome_mail_failure(
    uuid,
    text,
    boolean
) from public;
revoke execute on function public.record_welcome_mail_failure(
    uuid,
    text,
    boolean
) from anon;
revoke execute on function public.record_welcome_mail_failure(
    uuid,
    text,
    boolean
) from authenticated;
grant execute on function public.record_welcome_mail_failure(
    uuid,
    text,
    boolean
) to service_role;
