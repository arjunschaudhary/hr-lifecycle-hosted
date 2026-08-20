begin;

-- Browser-triggered offer processing remains the primary path. This cron job
-- only invokes the proven fallback dispatcher. The dispatcher owns eligibility
-- delays and durable dispatch leases to prevent hammering, and it continues to
-- exclude states that could represent an unknown Gmail delivery outcome.
do $block$
declare
    v_job_id bigint;
begin
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'cron-job:offer-letter-fallback-dispatcher',
            0::bigint
        )
    );

    if pg_catalog.to_regprocedure(
        'public.dispatch_offer_letter_fallback_jobs(integer)'
    ) is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher function is not installed.';
    end if;

    if not pg_catalog.has_function_privilege(
        current_user,
        'public.dispatch_offer_letter_fallback_jobs(integer)',
        'EXECUTE'
    ) then
        raise exception using
            errcode = '42501',
            message = 'The cron installation role cannot execute the offer-letter fallback dispatcher.';
    end if;

    if exists (
        select 1
        from cron.job cj
        where cj.jobname = 'offer-letter-fallback-dispatcher'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Cron job offer-letter-fallback-dispatcher already exists.';
    end if;

    select cron.schedule(
        'offer-letter-fallback-dispatcher',
        '*/2 * * * *',
        'select public.dispatch_offer_letter_fallback_jobs(10);'
    )
    into v_job_id;

    if v_job_id is null
       or not exists (
           select 1
           from cron.job cj
           where cj.jobid = v_job_id
             and cj.jobname = 'offer-letter-fallback-dispatcher'
             and cj.schedule = '*/2 * * * *'
             and cj.command =
                 'select public.dispatch_offer_letter_fallback_jobs(10);'
             and cj.username = current_user
             and cj.active is true
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback cron job could not be verified.';
    end if;
end;
$block$;

commit;
