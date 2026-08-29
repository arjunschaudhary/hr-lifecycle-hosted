begin;

/*
 * Candidate/HR-triggered dispatch remains primary. This conservative cron
 * invokes only the safe database dispatcher, whose eligibility filters,
 * transport lease, provider-evidence exclusions, and explicit legacy-job
 * denylist prevent blind retries or Gmail resends.
 */
do $block$
declare
    v_job_id bigint;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'cron-job:exit-document-fallback-dispatcher',
            0::bigint
        )
    );

    if pg_catalog.to_regprocedure(
        'public.dispatch_exit_document_fallback_jobs(integer)'
    ) is null then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document fallback dispatcher function is not installed.';
    end if;

    if not pg_catalog.has_function_privilege(
        current_user,
        'public.dispatch_exit_document_fallback_jobs(integer)',
        'EXECUTE'
    ) then
        raise exception using
            errcode = '42501',
            message = 'The cron installation role cannot execute the Exit-document fallback dispatcher.';
    end if;

    if exists (
        select 1
        from cron.job cj
        where cj.jobname = 'exit-document-fallback-dispatcher'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Cron job exit-document-fallback-dispatcher already exists.';
    end if;

    select cron.schedule(
        'exit-document-fallback-dispatcher',
        '*/5 * * * *',
        'select public.dispatch_exit_document_fallback_jobs(6);'
    )
    into v_job_id;

    if v_job_id is null
       or not exists (
           select 1
           from cron.job cj
           where cj.jobid = v_job_id
             and cj.jobname = 'exit-document-fallback-dispatcher'
             and cj.schedule = '*/5 * * * *'
             and cj.command =
                 'select public.dispatch_exit_document_fallback_jobs(6);'
             and cj.username = current_user
             and cj.active is true
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document fallback cron job could not be verified.';
    end if;
end;
$block$;

commit;
