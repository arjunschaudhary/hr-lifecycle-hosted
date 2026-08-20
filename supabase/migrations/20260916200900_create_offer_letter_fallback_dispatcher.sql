begin;

-- pg_net provides transaction-aware asynchronous HTTP dispatch. Supabase
-- installs its callable API in the dedicated net schema.
create extension if not exists pg_net
    with schema extensions;

alter table public.automation_jobs
    add column if not exists offer_fallback_dispatched_at timestamptz,
    add column if not exists offer_fallback_request_id bigint;

do $block$
begin
    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.automation_jobs'::pg_catalog.regclass
          and conname = 'automation_jobs_offer_fallback_dispatch_check'
    ) then
        alter table public.automation_jobs
            add constraint automation_jobs_offer_fallback_dispatch_check
            check (
                (
                    offer_fallback_dispatched_at is null
                    and offer_fallback_request_id is null
                )
                or
                (
                    job_type = 'OFFER_LETTER'
                    and offer_fallback_dispatched_at is not null
                    and offer_fallback_request_id is not null
                    and offer_fallback_request_id > 0
                )
            );
    end if;
end;
$block$;

comment on column public.automation_jobs.offer_fallback_dispatched_at is
    'Timestamp of the latest committed pg_net fallback dispatch for an OFFER_LETTER job. It is a transport lease only and does not claim or change job state.';

comment on column public.automation_jobs.offer_fallback_request_id is
    'Non-secret pg_net request ID paired with offer_fallback_dispatched_at for fallback-dispatch observability.';

create or replace function public.dispatch_offer_letter_fallback_jobs(
    p_limit integer default 10
)
returns table (
    job_id uuid,
    candidate_id uuid,
    request_id bigint
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
    v_limit integer;
    v_now timestamptz := pg_catalog.now();
    v_project_url text;
    v_project_ref text;
    v_service_role_key text;
    v_service_role_claims jsonb;
    v_jwt_project_ref text;
    v_dispatch_lease interval := interval '5 minutes';
    v_job record;
    v_request_id bigint;
begin
    if p_limit is null or p_limit <= 0 then
        raise exception using
            errcode = '22023',
            message = 'Dispatch limit must be a positive integer.';
    end if;

    v_limit := least(p_limit, 20);

    select nullif(pg_catalog.btrim(ds.decrypted_secret), '')
    into v_project_url
    from vault.decrypted_secrets ds
    where ds.name = 'offer_worker_project_url';

    select nullif(pg_catalog.btrim(ds.decrypted_secret), '')
    into v_service_role_key
    from vault.decrypted_secrets ds
    where ds.name = 'offer_worker_service_role_key';

    if v_project_url is null or v_service_role_key is null then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher Vault configuration is missing.';
    end if;

    v_project_url := pg_catalog.regexp_replace(v_project_url, '/+$', '');

    if v_project_url !~ '^https://[a-z0-9-]+[.]supabase[.]co$' then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher project URL is invalid.';
    end if;

    v_project_ref := pg_catalog.split_part(
        pg_catalog.split_part(v_project_url, '://', 2),
        '.',
        1
    );

    -- process-offer-letter keeps the default Edge Function JWT check enabled.
    -- A new-format sb_secret key is not a JWT and must never be used as a
    -- Bearer token. Decode only the non-secret claim payload to require the
    -- legacy JWT service_role credential expected by claim_offer_letter_job().
    if v_service_role_key !~
       '^[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]+$' then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher requires a JWT-based service-role key.';
    end if;

    begin
        v_service_role_claims := pg_catalog.convert_from(
            pg_catalog.decode(
                pg_catalog.translate(
                    pg_catalog.split_part(v_service_role_key, '.', 2),
                    '-_',
                    '+/'
                ) || pg_catalog.repeat(
                    '=',
                    (
                        4 - pg_catalog.length(
                            pg_catalog.split_part(v_service_role_key, '.', 2)
                        ) % 4
                    ) % 4
                ),
                'base64'
            ),
            'UTF8'
        )::jsonb;
    exception
        when others then
            raise exception using
                errcode = 'P0001',
                message = 'Offer-letter fallback dispatcher service-role key is invalid.';
    end;

    if v_service_role_claims ->> 'role' is distinct from 'service_role' then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher requires a service-role JWT.';
    end if;

    v_jwt_project_ref := nullif(
        pg_catalog.btrim(v_service_role_claims ->> 'ref'),
        ''
    );

    if v_jwt_project_ref is null
       or v_jwt_project_ref !~ '^[a-z0-9-]+$' then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher service-role JWT project reference is invalid.';
    end if;

    if v_jwt_project_ref is distinct from v_project_ref then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter fallback dispatcher Vault project configuration does not match.';
    end if;

    -- FAILED is a terminal/non-retryable worker classification and is never
    -- selected. RETRY is the worker's explicit safe retry/finalization state.
    -- PENDING must still be pre-email. PROCESSING is recoverable only before
    -- any send intent or provider acceptance, because post-send ambiguity can
    -- represent an unknown Gmail delivery outcome.
    for v_job in
        select
            aj.job_id,
            aj.candidate_id,
            case aj.job_status
                when 'PENDING' then
                    greatest(
                        aj.scheduled_at,
                        aj.updated_at,
                        aj.created_at
                    ) + interval '2 minutes'
                when 'RETRY' then
                    greatest(
                        aj.scheduled_at,
                        coalesce(aj.last_attempt_at, aj.created_at),
                        aj.updated_at,
                        aj.created_at
                    ) + interval '5 minutes'
                when 'PROCESSING' then
                    greatest(
                        coalesce(aj.last_attempt_at, aj.created_at),
                        aj.updated_at,
                        aj.created_at
                    ) + interval '15 minutes'
            end as eligible_at,
            aj.created_at
        from public.automation_jobs aj
        left join public.hr_offer_letters hol
            on hol.candidate_id = aj.candidate_id
        where aj.job_type = 'OFFER_LETTER'
          and (
              aj.offer_fallback_dispatched_at is null
              or aj.offer_fallback_dispatched_at <= v_now - v_dispatch_lease
          )
          and (
              (
                  aj.job_status = 'PENDING'
                  and aj.attempt_count < 5
                  and greatest(
                      aj.scheduled_at,
                      aj.updated_at,
                      aj.created_at
                  ) <= v_now - interval '2 minutes'
                  and aj.provider_message_id is null
                  and aj.provider_accepted_at is null
                  and hol.email_attempted_at is null
                  and hol.gmail_message_id is null
                  and hol.provider_accepted_at is null
              )
              or
              (
                  aj.job_status = 'RETRY'
                  and greatest(
                      aj.scheduled_at,
                      coalesce(aj.last_attempt_at, aj.created_at),
                      aj.updated_at,
                      aj.created_at
                  ) <= v_now - interval '5 minutes'
                  and (
                      (
                          aj.attempt_count < 5
                          and aj.provider_message_id is null
                          and aj.provider_accepted_at is null
                          and hol.gmail_message_id is null
                          and hol.provider_accepted_at is null
                      )
                      or
                      (
                          aj.attempt_count < 10
                          and aj.provider_message_id is not null
                          and aj.provider_accepted_at is not null
                          and hol.gmail_message_id
                              = aj.provider_message_id
                          and hol.provider_accepted_at
                              = aj.provider_accepted_at
                          and hol.email_attempted_at is not null
                          and hol.documents_prepared_at is not null
                          and hol.google_doc_file_id is not null
                          and hol.google_pdf_file_id is not null
                      )
                  )
              )
              or
              (
                  aj.job_status = 'PROCESSING'
                  and aj.attempt_count < 5
                  and greatest(
                      coalesce(aj.last_attempt_at, aj.created_at),
                      aj.updated_at,
                      aj.created_at
                  ) <= v_now - interval '15 minutes'
                  and aj.provider_message_id is null
                  and aj.provider_accepted_at is null
                  and hol.email_attempted_at is null
                  and hol.gmail_message_id is null
                  and hol.provider_accepted_at is null
              )
          )
        order by eligible_at, aj.created_at, aj.job_id
        limit v_limit
        for update of aj skip locked
    loop
        select net.http_post(
            url := v_project_url
                || '/functions/v1/process-offer-letter',
            body := pg_catalog.jsonb_build_object(
                'candidateId',
                v_job.candidate_id::text
            ),
            headers := pg_catalog.jsonb_build_object(
                'Content-Type',
                'application/json',
                'Authorization',
                'Bearer ' || v_service_role_key,
                'apikey',
                v_service_role_key
            ),
            timeout_milliseconds := 10000
        )
        into v_request_id;

        if v_request_id is null then
            raise exception using
                errcode = 'P0001',
                message = 'Offer-letter fallback HTTP dispatch could not be queued.';
        end if;

        -- pg_net enqueues transactionally. Persisting the lease and request ID
        -- in this transaction means a rollback removes both markers and the
        -- queued HTTP request. Job state remains owned by the worker.
        update public.automation_jobs aj
        set
            offer_fallback_dispatched_at = v_now,
            offer_fallback_request_id = v_request_id
        where aj.job_id = v_job.job_id;

        job_id := v_job.job_id;
        candidate_id := v_job.candidate_id;
        request_id := v_request_id;
        return next;
    end loop;

    return;
end;
$function$;

comment on function public.dispatch_offer_letter_fallback_jobs(integer) is
    'Queues bounded pg_net calls using a durable five-minute dispatch lease. External work is limited to fewer than five claims; RETRY rows with matched durable provider acceptance may receive fewer than ten finalization attempts. FAILED is excluded because it is terminal/non-retryable. Stale PROCESSING rows with email-attempt or provider-acceptance evidence are excluded because delivery may be unknown. HTTP dispatch does not change job state; process-offer-letter remains responsible for claiming and state transitions.';

revoke all privileges
    on function public.dispatch_offer_letter_fallback_jobs(integer)
    from public;
revoke all privileges
    on function public.dispatch_offer_letter_fallback_jobs(integer)
    from anon;
revoke all privileges
    on function public.dispatch_offer_letter_fallback_jobs(integer)
    from authenticated;

grant execute
    on function public.dispatch_offer_letter_fallback_jobs(integer)
    to service_role;

commit;
