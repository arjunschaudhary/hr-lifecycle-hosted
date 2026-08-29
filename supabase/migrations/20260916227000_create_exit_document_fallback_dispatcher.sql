begin;

create extension if not exists pg_net
    with schema extensions;

alter table public.automation_jobs
    add column if not exists exit_document_dispatch_lease_expires_at timestamptz,
    add column if not exists exit_document_dispatch_request_id bigint;

do $block$
begin
    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.automation_jobs'::pg_catalog.regclass
          and conname = 'automation_jobs_exit_document_dispatch_check'
    ) then
        alter table public.automation_jobs
            add constraint automation_jobs_exit_document_dispatch_check
            check (
                (
                    exit_document_dispatch_lease_expires_at is null
                    and exit_document_dispatch_request_id is null
                )
                or
                (
                    job_type = 'EXIT_DOCUMENT'
                    and exit_document_dispatch_lease_expires_at is not null
                    and (
                        exit_document_dispatch_request_id is null
                        or exit_document_dispatch_request_id > 0
                    )
                )
            );
    end if;
end;
$block$;

comment on column public.automation_jobs.exit_document_dispatch_lease_expires_at is
    'Transport-only lease preventing duplicate Exit-document worker dispatch. Worker claim/status remains authoritative.';

comment on column public.automation_jobs.exit_document_dispatch_request_id is
    'Optional non-secret pg_net request ID for the current Exit-document fallback dispatch lease.';

create index if not exists idx_automation_jobs_exit_document_safe_dispatch
    on public.automation_jobs (
        job_status,
        scheduled_at,
        exit_document_dispatch_lease_expires_at,
        created_at
    )
    where job_type = 'EXIT_DOCUMENT'
      and job_status in ('PENDING', 'RETRY');


/*
 * Reserves a short transport lease for explicitly requested, currently safe
 * jobs. The HR-facing dispatcher performs HTTP only for rows returned here.
 */
create or replace function public.prepare_exit_document_dispatch_jobs(
    p_request_ids uuid[]
)
returns table (job_id uuid)
language plpgsql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $function$
#variable_conflict use_column
declare
    v_now timestamptz := pg_catalog.now();
    v_requested_count integer;
    v_resolved_count integer;
begin
    if auth.role() is distinct from 'service_role' then
        raise exception using
            errcode = '42501',
            message = 'Service-role dispatcher access is required.';
    end if;

    v_requested_count := pg_catalog.cardinality(p_request_ids);

    if p_request_ids is null
       or v_requested_count is null
       or v_requested_count < 1
       or v_requested_count > 6
       or exists (
            select 1
            from pg_catalog.unnest(p_request_ids) requested(request_id)
            where requested.request_id is null
       )
       or (
            select pg_catalog.count(*)
            from pg_catalog.unnest(p_request_ids) requested(request_id)
       ) is distinct from (
            select pg_catalog.count(distinct requested.request_id)
            from pg_catalog.unnest(p_request_ids) requested(request_id)
       ) then
        raise exception using
            errcode = '22023',
            message = 'One to six unique Exit-document request IDs are required.';
    end if;

    select pg_catalog.count(distinct ecr.request_id)::integer
    into v_resolved_count
    from public.exit_document_requests ecr
    where ecr.request_id = any(p_request_ids)
      and ecr.job_id is not null;

    if v_resolved_count is distinct from v_requested_count then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document requests could not be resolved for dispatch.';
    end if;

    return query
    with eligible as (
        select aj.job_id
        from public.automation_jobs aj
        join public.exit_document_requests ecr
          on ecr.job_id = aj.job_id
        left join public.exit_documents ed
          on ed.exit_case_id = ecr.exit_case_id
         and ed.document_variant = ecr.document_variant
        where ecr.request_id = any(p_request_ids)
          and aj.job_type = 'EXIT_DOCUMENT'
          and aj.job_status in ('PENDING', 'RETRY')
          and aj.scheduled_at <= v_now
          and aj.attempt_count < 5
          and aj.provider_message_id is null
          and aj.provider_accepted_at is null
          and ecr.status in ('REQUESTED', 'FAILED')
          and ecr.email_attempted_at is null
          and ed.gmail_message_id is null
          and ed.emailed_at is null
          and (
                aj.exit_document_dispatch_lease_expires_at is null
                or aj.exit_document_dispatch_lease_expires_at <= v_now
          )
          and aj.job_id <> all(array[
              'bddfd007-d2c9-4354-a1ff-d694a2d45606'::uuid,
              '2b5efc7c-166e-458e-9b04-49a1f0792d77'::uuid,
              'eac8b569-c775-4cbe-a201-04b127424603'::uuid
          ])
        order by aj.scheduled_at, aj.created_at, aj.job_id
        for update of aj skip locked
    ), leased as (
        update public.automation_jobs aj
        set
            exit_document_dispatch_lease_expires_at =
                v_now + interval '2 minutes',
            exit_document_dispatch_request_id = null,
            updated_at = v_now
        from eligible e
        where aj.job_id = e.job_id
        returning aj.job_id
    )
    select leased.job_id
    from leased;
end;
$function$;


/*
 * Browser dispatch remains primary. This fallback selects only pre-email
 * PENDING/RETRY jobs whose explicit schedule is due. It never selects
 * PROCESSING, terminal, provider-accepted, or unresolved email-attempt rows.
 */
create or replace function public.dispatch_exit_document_fallback_jobs(
    p_limit integer default 6
)
returns table (
    job_id uuid,
    request_id bigint
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, pg_temp
as $function$
#variable_conflict use_column
declare
    v_limit integer;
    v_now timestamptz := pg_catalog.now();
    v_project_url text;
    v_project_ref text;
    v_service_role_key text;
    v_service_role_claims jsonb;
    v_jwt_project_ref text;
    v_job record;
    v_request_id bigint;
begin
    if p_limit is null or p_limit <= 0 then
        raise exception using
            errcode = '22023',
            message = 'Dispatch limit must be a positive integer.';
    end if;

    v_limit := least(p_limit, 10);

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
            message = 'Exit-document fallback dispatcher Vault configuration is missing.';
    end if;

    v_project_url := pg_catalog.regexp_replace(v_project_url, '/+$', '');

    if v_project_url !~ '^https://[a-z0-9-]+[.]supabase[.]co$' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document fallback dispatcher project URL is invalid.';
    end if;

    v_project_ref := pg_catalog.split_part(
        pg_catalog.split_part(v_project_url, '://', 2),
        '.',
        1
    );

    if v_service_role_key !~
       '^[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]+$' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document fallback dispatcher requires a JWT-based service-role key.';
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
                message = 'Exit-document fallback dispatcher service-role key is invalid.';
    end;

    if v_service_role_claims ->> 'role' is distinct from 'service_role' then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document fallback dispatcher requires a service-role JWT.';
    end if;

    v_jwt_project_ref := nullif(
        pg_catalog.btrim(v_service_role_claims ->> 'ref'),
        ''
    );

    if v_jwt_project_ref is null
       or v_jwt_project_ref !~ '^[a-z0-9-]+$'
       or v_jwt_project_ref is distinct from v_project_ref then
        raise exception using
            errcode = 'P0001',
            message = 'Exit-document fallback dispatcher Vault project configuration does not match.';
    end if;

    for v_job in
        select
            aj.job_id,
            aj.scheduled_at,
            aj.created_at
        from public.automation_jobs aj
        join public.exit_document_requests ecr
          on ecr.job_id = aj.job_id
        left join public.exit_documents ed
          on ed.exit_case_id = ecr.exit_case_id
         and ed.document_variant = ecr.document_variant
        where aj.job_type = 'EXIT_DOCUMENT'
          and aj.job_status in ('PENDING', 'RETRY')
          and aj.scheduled_at <= v_now
          and aj.attempt_count < 5
          and aj.provider_message_id is null
          and aj.provider_accepted_at is null
          and ecr.status in ('REQUESTED', 'FAILED')
          and ecr.email_attempted_at is null
          and ed.gmail_message_id is null
          and ed.emailed_at is null
          and (
                aj.exit_document_dispatch_lease_expires_at is null
                or aj.exit_document_dispatch_lease_expires_at <= v_now
          )
          and aj.job_id <> all(array[
              'bddfd007-d2c9-4354-a1ff-d694a2d45606'::uuid,
              '2b5efc7c-166e-458e-9b04-49a1f0792d77'::uuid,
              'eac8b569-c775-4cbe-a201-04b127424603'::uuid
          ])
          and (
                aj.job_status = 'RETRY'
                or aj.created_at <= v_now - interval '2 minutes'
          )
        order by aj.scheduled_at, aj.created_at, aj.job_id
        limit v_limit
        for update of aj skip locked
    loop
        select net.http_post(
            url := v_project_url || '/functions/v1/process-exit-document',
            body := pg_catalog.jsonb_build_object(
                'jobId',
                v_job.job_id::text
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
                message = 'Exit-document fallback HTTP dispatch could not be queued.';
        end if;

        update public.automation_jobs aj
        set
            exit_document_dispatch_lease_expires_at =
                v_now + interval '5 minutes',
            exit_document_dispatch_request_id = v_request_id,
            updated_at = v_now
        where aj.job_id = v_job.job_id;

        job_id := v_job.job_id;
        request_id := v_request_id;
        return next;
    end loop;

    return;
end;
$function$;


revoke all privileges
    on function public.prepare_exit_document_dispatch_jobs(uuid[])
    from public, anon, authenticated;

grant execute
    on function public.prepare_exit_document_dispatch_jobs(uuid[])
    to service_role;

revoke all privileges
    on function public.dispatch_exit_document_fallback_jobs(integer)
    from public, anon, authenticated;

grant execute
    on function public.dispatch_exit_document_fallback_jobs(integer)
    to service_role;

comment on function public.prepare_exit_document_dispatch_jobs(uuid[]) is
    'Reserves short transport leases for explicitly requested safe Exit-document PENDING/RETRY jobs. Provider/email evidence and three legacy reconciliation jobs are excluded.';

comment on function public.dispatch_exit_document_fallback_jobs(integer) is
    'Queues bounded pg_net calls only for due safe Exit-document PENDING/RETRY jobs. PROCESSING, terminal, provider/email-uncertain, and three legacy reconciliation jobs are excluded.';

commit;
