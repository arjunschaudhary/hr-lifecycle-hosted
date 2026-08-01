begin;

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
    'Runs daily performance-cycle maintenance using the Asia/Kolkata business date. It generates idempotent current- and next-month cycles, advances eligible cycles to OPEN or REVIEW_OPEN without moving statuses backwards, retries existing PERFORMANCE_CYCLE_ASSIGNMENT jobs waiting for an OPEN cycle, and reconciles eligible candidates into exactly one current OPEN cycle before refreshing its non-final performance summaries. The existing pg_cron schedule remains 12:05 AM Asia/Kolkata, which is 18:35 UTC on the previous calendar day.';

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

commit;
