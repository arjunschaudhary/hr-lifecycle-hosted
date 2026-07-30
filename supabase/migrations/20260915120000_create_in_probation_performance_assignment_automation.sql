begin;

create or replace function public.mark_candidate_in_probation_and_enqueue_performance_assignment(
    p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_job public.automation_jobs%rowtype;
    v_job_created boolean := false;
    v_transition_completed boolean := false;
    v_idempotency_key text;
    v_timestamp timestamptz := pg_catalog.now();
begin
    if p_candidate_id is null then
        raise exception using
            errcode = '22004',
            message = 'Candidate ID is required.';
    end if;

    if public.current_user_is_active() is not true
       or public.current_user_has_any_role(
           array[
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_LEAD',
               'ADMIN'
           ]::text[]
       ) is not true then
        raise exception using
            errcode = '42501',
            message = 'You do not have permission to mark this candidate in probation.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null then
        raise exception using
            errcode = '42501',
            message = 'An active application user is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'in-probation:' || p_candidate_id::text,
            0::bigint
        )
    );

    begin
        select hl.*
        into strict v_lifecycle
        from public.hr_lifecycle hl
        where hl.candidate_id = p_candidate_id
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

    if v_lifecycle.probation_start_date is null then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate probation start date is required.';
    end if;

    if v_lifecycle.probation_start_date > current_date then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate probation start date cannot be in the future.';
    end if;

    v_idempotency_key :=
        'PERFORMANCE_CYCLE_ASSIGNMENT:'
        || p_candidate_id::text
        || ':'
        || v_lifecycle.probation_start_date::text;

    if v_lifecycle.lifecycle_status = 'WELCOME_MAIL_SENT' then
        update public.hr_lifecycle
        set
            lifecycle_status = 'IN_PROBATION',
            updated_at = v_timestamp
        where lifecycle_id = v_lifecycle.lifecycle_id
          and lifecycle_status = 'WELCOME_MAIL_SENT';

        if not found then
            raise exception using
                errcode = '40001',
                message = 'Candidate lifecycle changed during processing.';
        end if;

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
        )
        values (
            p_candidate_id,
            'IN_PROBATION',
            'WELCOME_MAIL_SENT',
            'IN_PROBATION',
            'Candidate marked as in probation by HR',
            'SUCCESS',
            v_actor_user_id::text,
            v_timestamp,
            v_timestamp,
            v_timestamp
        );

        v_transition_completed := true;
    elsif v_lifecycle.lifecycle_status = 'IN_PROBATION' then
        begin
            select aj.*
            into strict v_job
            from public.automation_jobs aj
            where aj.idempotency_key = v_idempotency_key
            for update;
        exception
            when no_data_found then
                raise exception using
                    errcode = 'P0001',
                    message = 'Candidate lifecycle status must be WELCOME_MAIL_SENT.';
        end;

        if v_job.candidate_id is distinct from p_candidate_id
           or v_job.job_type is distinct from 'PERFORMANCE_CYCLE_ASSIGNMENT' then
            raise exception using
                errcode = 'P0001',
                message = 'Performance-assignment job state is inconsistent.';
        end if;
    else
        raise exception using
            errcode = 'P0001',
            message = 'Candidate lifecycle status must be WELCOME_MAIL_SENT.';
    end if;

    if v_job.job_id is null then
        insert into public.automation_jobs (
            candidate_id,
            job_type,
            job_status,
            payload,
            scheduled_at,
            attempt_count,
            idempotency_key,
            requested_by,
            created_at,
            updated_at
        )
        values (
            p_candidate_id,
            'PERFORMANCE_CYCLE_ASSIGNMENT',
            'PENDING',
            pg_catalog.jsonb_build_object(
                'probation_start_date',
                v_lifecycle.probation_start_date
            ),
            v_timestamp,
            0,
            v_idempotency_key,
            v_actor_user_id,
            v_timestamp,
            v_timestamp
        )
        on conflict (idempotency_key) do nothing
        returning * into v_job;

        if found then
            v_job_created := true;
        else
            select aj.*
            into strict v_job
            from public.automation_jobs aj
            where aj.idempotency_key = v_idempotency_key
            for update;

            if v_job.candidate_id is distinct from p_candidate_id
               or v_job.job_type is distinct from 'PERFORMANCE_CYCLE_ASSIGNMENT' then
                raise exception using
                    errcode = 'P0001',
                    message = 'Performance-assignment job state is inconsistent.';
            end if;
        end if;
    end if;

    if v_job_created then
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
            p_candidate_id,
            'PERFORMANCE_ASSIGNMENT_QUEUED',
            'IN_PROBATION',
            'IN_PROBATION',
            'Performance-cycle assignment queued after probation started',
            'SUCCESS',
            pg_catalog.jsonb_build_object(
                'job_id',
                v_job.job_id,
                'job_status',
                v_job.job_status
            ),
            v_actor_user_id::text,
            v_timestamp,
            v_timestamp,
            v_timestamp
        );
    end if;

    return pg_catalog.jsonb_build_object(
        'success', true,
        'candidateId', p_candidate_id,
        'lifecycleStatus', 'IN_PROBATION',
        'transitionCompleted', v_transition_completed,
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status
    );
end;
$function$;

comment on function
    public.mark_candidate_in_probation_and_enqueue_performance_assignment(uuid) is
    'Atomically moves one authorized candidate from WELCOME_MAIL_SENT to IN_PROBATION, records the permanent lifecycle activity, and creates or reuses one idempotent performance-cycle assignment job. An idempotent replay is accepted only when the candidate is already IN_PROBATION and the matching job exists.';

revoke execute on function
    public.mark_candidate_in_probation_and_enqueue_performance_assignment(uuid)
from public;

revoke execute on function
    public.mark_candidate_in_probation_and_enqueue_performance_assignment(uuid)
from anon;

grant execute on function
    public.mark_candidate_in_probation_and_enqueue_performance_assignment(uuid)
to authenticated;

grant execute on function
    public.mark_candidate_in_probation_and_enqueue_performance_assignment(uuid)
to service_role;

create or replace function public.process_performance_cycle_assignment_job(
    p_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_job public.automation_jobs%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_previous_status text;
    v_previous_error_message text;
    v_cycle_ids uuid[];
    v_cycle_id uuid;
    v_cycle public.performance_cycles%rowtype;
    v_internship_end_date date;
    v_effective_start_date date;
    v_pod_id uuid;
    v_assignment_id uuid;
    v_eligible_days integer;
    v_error_message text;
    v_timestamp timestamptz := pg_catalog.now();
begin
    if p_job_id is null then
        raise exception using
            errcode = '22004',
            message = 'Performance-assignment job ID is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'performance-assignment-job:' || p_job_id::text,
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
                message = 'Performance-assignment job was not found.';
    end;

    if v_job.job_type is distinct from 'PERFORMANCE_CYCLE_ASSIGNMENT' then
        raise exception using
            errcode = 'P0001',
            message = 'Performance-assignment job type is invalid.';
    end if;

    if v_job.job_status = 'SUCCESS' then
        return pg_catalog.jsonb_build_object(
            'success', true,
            'candidateId', v_job.candidate_id,
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'performanceOutcome', 'PERFORMANCE_ASSIGNED',
            'cycleId', v_job.payload ->> 'cycle_id',
            'assignmentId', v_job.payload ->> 'assignment_id',
            'eligibleDays', v_job.payload -> 'eligible_days',
            'message', 'Candidate is already assigned to the performance cycle.'
        );
    end if;

    if v_job.job_status = 'CANCELLED' then
        return pg_catalog.jsonb_build_object(
            'success', true,
            'candidateId', v_job.candidate_id,
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'performanceOutcome', 'PERFORMANCE_FAILED',
            'message', 'Performance-cycle assignment job is cancelled.'
        );
    end if;

    if v_job.job_status = 'PROCESSING' then
        return pg_catalog.jsonb_build_object(
            'success', true,
            'candidateId', v_job.candidate_id,
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'performanceOutcome', 'PERFORMANCE_FAILED',
            'message', 'Performance-cycle assignment is already being processed.'
        );
    end if;

    v_previous_status := v_job.job_status;
    v_previous_error_message := v_job.error_message;

    update public.automation_jobs
    set
        job_status = 'PROCESSING',
        attempt_count = attempt_count + 1,
        last_attempt_at = v_timestamp,
        completed_at = null,
        error_message = null,
        updated_at = v_timestamp
    where job_id = v_job.job_id
    returning * into v_job;

    begin
        begin
            select hl.*
            into strict v_lifecycle
            from public.hr_lifecycle hl
            where hl.candidate_id = v_job.candidate_id
            for update;
        exception
            when no_data_found then
                raise exception 'Candidate lifecycle record was not found.';
            when too_many_rows then
                raise exception 'Candidate has multiple lifecycle records.';
        end;

        if v_lifecycle.lifecycle_status is distinct from 'IN_PROBATION' then
            raise exception
                'Candidate lifecycle status is not IN_PROBATION.';
        end if;

        if v_lifecycle.probation_start_date is null then
            raise exception 'Candidate probation start date is required.';
        end if;

        if v_lifecycle.probation_start_date > current_date then
            raise exception
                'Candidate probation start date cannot be in the future.';
        end if;

        v_internship_end_date := coalesce(
            v_lifecycle.current_end_date,
            v_lifecycle.original_end_date
        );

        if v_internship_end_date is null then
            raise exception 'Candidate internship end date is required.';
        end if;

        if v_internship_end_date < v_lifecycle.probation_start_date then
            raise exception
                'Candidate internship end date is earlier than probation start date.';
        end if;

        select pg_catalog.array_agg(
            matching_cycle.id
            order by matching_cycle.start_date, matching_cycle.id
        )
        into v_cycle_ids
        from (
            select pc.id, pc.start_date
            from public.performance_cycles pc
            where pc.cycle_status = 'OPEN'
              and current_date between pc.start_date and pc.end_date
              and greatest(
                  pc.start_date,
                  v_lifecycle.probation_start_date
              ) <= least(
                  pc.end_date,
                  v_internship_end_date
              )
            for update
        ) as matching_cycle;

        if coalesce(pg_catalog.cardinality(v_cycle_ids), 0) = 0 then
            v_error_message :=
                'No applicable OPEN performance cycle is currently available.';

            update public.automation_jobs
            set
                job_status = 'RETRY',
                scheduled_at = v_timestamp + interval '15 minutes',
                completed_at = null,
                error_message = v_error_message,
                payload = payload || pg_catalog.jsonb_build_object(
                    'pending_reason',
                    'OPEN_CYCLE'
                ),
                updated_at = v_timestamp
            where job_id = v_job.job_id
            returning * into v_job;

            if v_previous_status is distinct from 'RETRY'
               or v_previous_error_message is distinct from v_error_message then
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
                    v_job.candidate_id,
                    'PERFORMANCE_ASSIGNMENT_PENDING',
                    'IN_PROBATION',
                    'IN_PROBATION',
                    'Performance-cycle assignment is pending an OPEN cycle',
                    'PENDING',
                    v_error_message,
                    pg_catalog.jsonb_build_object(
                        'job_id',
                        v_job.job_id,
                        'pending_reason',
                        'OPEN_CYCLE'
                    ),
                    v_job.requested_by::text,
                    v_timestamp,
                    v_timestamp,
                    v_timestamp
                );
            end if;

            return pg_catalog.jsonb_build_object(
                'success', true,
                'candidateId', v_job.candidate_id,
                'jobId', v_job.job_id,
                'jobStatus', v_job.job_status,
                'performanceOutcome', 'PERFORMANCE_PENDING_CYCLE',
                'message', v_error_message
            );
        end if;

        if pg_catalog.cardinality(v_cycle_ids) > 1 then
            v_error_message :=
                'Multiple applicable OPEN performance cycles were found.';

            update public.automation_jobs
            set
                job_status = 'FAILED',
                completed_at = null,
                error_message = v_error_message,
                payload = payload || pg_catalog.jsonb_build_object(
                    'failure_reason',
                    'MULTIPLE_OPEN_CYCLES'
                ),
                updated_at = v_timestamp
            where job_id = v_job.job_id
            returning * into v_job;

            if v_previous_status is distinct from 'FAILED'
               or v_previous_error_message is distinct from v_error_message then
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
                    v_job.candidate_id,
                    'PERFORMANCE_ASSIGNMENT_FAILED',
                    'IN_PROBATION',
                    'IN_PROBATION',
                    'Performance-cycle assignment failed because cycle configuration is ambiguous',
                    'FAILED',
                    v_error_message,
                    pg_catalog.jsonb_build_object(
                        'job_id',
                        v_job.job_id,
                        'failure_reason',
                        'MULTIPLE_OPEN_CYCLES'
                    ),
                    v_job.requested_by::text,
                    v_timestamp,
                    v_timestamp,
                    v_timestamp
                );
            end if;

            return pg_catalog.jsonb_build_object(
                'success', true,
                'candidateId', v_job.candidate_id,
                'jobId', v_job.job_id,
                'jobStatus', v_job.job_status,
                'performanceOutcome', 'PERFORMANCE_FAILED',
                'message', v_error_message
            );
        end if;

        v_cycle_id := v_cycle_ids[1];

        select pc.*
        into strict v_cycle
        from public.performance_cycles pc
        where pc.id = v_cycle_id
        for update;

        if v_cycle.cycle_status is distinct from 'OPEN'
           or current_date not between v_cycle.start_date and v_cycle.end_date then
            raise exception
                'Applicable performance cycle changed during processing.';
        end if;

        v_effective_start_date := greatest(
            v_cycle.start_date,
            v_lifecycle.probation_start_date
        );

        select pm.pod_id
        into v_pod_id
        from public.pod_memberships pm
        where pm.candidate_id = v_job.candidate_id
          and pm.membership_type = 'CANDIDATE'
          and pm.effective_from <= v_effective_start_date
          and (
              pm.effective_to is null
              or pm.effective_to >= v_effective_start_date
          )
        order by
            pm.effective_from desc,
            pm.created_at desc,
            pm.id desc
        limit 1;

        if v_pod_id is null then
            v_error_message :=
                'No valid candidate pod membership exists on the evaluation start date.';

            update public.automation_jobs
            set
                job_status = 'RETRY',
                scheduled_at = v_timestamp + interval '15 minutes',
                completed_at = null,
                error_message = v_error_message,
                payload = payload || pg_catalog.jsonb_build_object(
                    'cycle_id',
                    v_cycle_id,
                    'pending_reason',
                    'POD_MEMBERSHIP'
                ),
                updated_at = v_timestamp
            where job_id = v_job.job_id
            returning * into v_job;

            if v_previous_status is distinct from 'RETRY'
               or v_previous_error_message is distinct from v_error_message then
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
                    v_job.candidate_id,
                    'PERFORMANCE_ASSIGNMENT_PENDING',
                    'IN_PROBATION',
                    'IN_PROBATION',
                    'Performance-cycle assignment is pending a valid pod membership',
                    'PENDING',
                    v_error_message,
                    pg_catalog.jsonb_build_object(
                        'job_id',
                        v_job.job_id,
                        'cycle_id',
                        v_cycle_id,
                        'pending_reason',
                        'POD_MEMBERSHIP'
                    ),
                    v_job.requested_by::text,
                    v_timestamp,
                    v_timestamp,
                    v_timestamp
                );
            end if;

            return pg_catalog.jsonb_build_object(
                'success', true,
                'candidateId', v_job.candidate_id,
                'jobId', v_job.job_id,
                'jobStatus', v_job.job_status,
                'performanceOutcome', 'PERFORMANCE_PENDING_POD',
                'cycleId', v_cycle_id,
                'message', v_error_message
            );
        end if;

        v_assignment_id := public.assign_candidate_to_performance_cycle(
            v_job.candidate_id,
            v_cycle_id
        );

        if v_assignment_id is null then
            raise exception
                'Candidate performance-cycle assignment returned no ID.';
        end if;

        v_eligible_days :=
            public.refresh_candidate_cycle_eligible_days(v_assignment_id);

        perform *
        from public.refresh_candidate_cycle_daily_summary(v_assignment_id);

        perform *
        from public.refresh_candidate_cycle_review_summary(v_assignment_id);

        perform public.refresh_candidate_cycle_exceptional_summary(
            v_assignment_id
        );

        perform *
        from public.refresh_candidate_cycle_result_status(v_assignment_id);

        update public.automation_jobs
        set
            job_status = 'SUCCESS',
            completed_at = v_timestamp,
            error_message = null,
            payload = payload || pg_catalog.jsonb_build_object(
                'cycle_id',
                v_cycle_id,
                'assignment_id',
                v_assignment_id,
                'eligible_days',
                v_eligible_days
            ),
            updated_at = v_timestamp
        where job_id = v_job.job_id
        returning * into v_job;

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
            v_job.candidate_id,
            'PERFORMANCE_CYCLE_ASSIGNED',
            'IN_PROBATION',
            'IN_PROBATION',
            'Candidate assigned to the current OPEN performance cycle',
            'SUCCESS',
            pg_catalog.jsonb_build_object(
                'job_id',
                v_job.job_id,
                'cycle_id',
                v_cycle_id,
                'assignment_id',
                v_assignment_id,
                'eligible_days',
                v_eligible_days
            ),
            v_job.requested_by::text,
            v_timestamp,
            v_timestamp,
            v_timestamp
        );

        return pg_catalog.jsonb_build_object(
            'success', true,
            'candidateId', v_job.candidate_id,
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'performanceOutcome', 'PERFORMANCE_ASSIGNED',
            'cycleId', v_cycle_id,
            'assignmentId', v_assignment_id,
            'eligibleDays', v_eligible_days,
            'message', 'Candidate assigned to the current performance cycle.'
        );
    exception
        when others then
            v_error_message := pg_catalog.left(
                coalesce(
                    nullif(pg_catalog.btrim(sqlerrm), ''),
                    'Performance-cycle assignment failed.'
                ),
                1000
            );

            update public.automation_jobs
            set
                job_status = 'FAILED',
                completed_at = null,
                error_message = v_error_message,
                payload = payload || pg_catalog.jsonb_build_object(
                    'failure_reason',
                    'PROCESSING_ERROR'
                ),
                updated_at = v_timestamp
            where job_id = v_job.job_id
            returning * into v_job;

            if v_previous_status is distinct from 'FAILED'
               or v_previous_error_message is distinct from v_error_message then
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
                    v_job.candidate_id,
                    'PERFORMANCE_ASSIGNMENT_FAILED',
                    'IN_PROBATION',
                    'IN_PROBATION',
                    'Performance-cycle assignment processing failed',
                    'FAILED',
                    v_error_message,
                    pg_catalog.jsonb_build_object(
                        'job_id',
                        v_job.job_id,
                        'failure_reason',
                        'PROCESSING_ERROR'
                    ),
                    v_job.requested_by::text,
                    v_timestamp,
                    v_timestamp,
                    v_timestamp
                );
            end if;

            return pg_catalog.jsonb_build_object(
                'success', true,
                'candidateId', v_job.candidate_id,
                'jobId', v_job.job_id,
                'jobStatus', v_job.job_status,
                'performanceOutcome', 'PERFORMANCE_FAILED',
                'message', 'Performance-cycle assignment could not be completed.'
            );
    end;
end;
$function$;

comment on function
    public.process_performance_cycle_assignment_job(uuid) is
    'Claims and processes one performance-cycle assignment job using exactly one current OPEN cycle, the existing candidate assignment logic, and candidate-specific eligible-day and summary refresh functions. Pending cycle or pod conditions are durable and retryable; failures never roll back the already committed IN_PROBATION lifecycle transition.';

revoke execute on function
    public.process_performance_cycle_assignment_job(uuid)
from public;

revoke execute on function
    public.process_performance_cycle_assignment_job(uuid)
from anon;

revoke execute on function
    public.process_performance_cycle_assignment_job(uuid)
from authenticated;

grant execute on function
    public.process_performance_cycle_assignment_job(uuid)
to service_role;

commit;
