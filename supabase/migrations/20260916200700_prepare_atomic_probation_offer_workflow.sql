begin;

-- Make generated MIDs unique at the database layer. Existing live-data review
-- found no duplicate non-null MID values before this migration was authored.
create unique index if not exists uq_hr_lifecycle_mid_unique
    on public.hr_lifecycle (mid)
    where mid is not null;

create or replace function public.pass_probation_and_prepare_offer(
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
    v_role_code text;
    v_clean_name text;
    v_name_parts text[];
    v_name_code text;
    v_year_code text;
    v_mid_prefix text;
    v_mid text;
    v_next_serial integer;
    v_idempotency_key text;
    v_from_status text;
    v_already_prepared boolean := false;
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
            message = 'An approved HR staff role is required.';
    end if;

    -- Serialize all pass/MID/offer preparation for this candidate.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'probation-offer:' || p_candidate_id::text,
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

    v_from_status := v_lifecycle.lifecycle_status;
    v_idempotency_key := 'OFFER_LETTER:' || p_candidate_id::text;

    -- Idempotent retry after the database preparation already completed.
    if v_lifecycle.lifecycle_status = 'MID_GENERATED' then
        if v_lifecycle.mid is null
           or pg_catalog.btrim(v_lifecycle.mid) = '' then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate lifecycle is MID_GENERATED but MID is missing.';
        end if;

        select aj.*
        into v_job
        from public.automation_jobs aj
        where aj.idempotency_key = v_idempotency_key
        for update;

        if v_job.job_id is not null
           and (
               v_job.job_type is distinct from 'OFFER_LETTER'
               or v_job.candidate_id is distinct from p_candidate_id
           ) then
            raise exception using
                errcode = 'P0001',
                message = 'Offer-letter automation state is inconsistent.';
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
                created_at,
                updated_at
            ) values (
                p_candidate_id,
                'OFFER_LETTER',
                'PENDING',
                pg_catalog.jsonb_build_object(
                    'mid', v_lifecycle.mid,
                    'offerLetterNumber', 'OL-' || v_lifecycle.mid
                ),
                v_now,
                0,
                null,
                null,
                v_idempotency_key,
                v_actor_user_id,
                v_now,
                v_now
            )
            returning * into v_job;
        end if;

        return pg_catalog.jsonb_build_object(
            'candidateId', p_candidate_id,
            'lifecycleStatus', 'MID_GENERATED',
            'mid', v_lifecycle.mid,
            'offerLetterNumber', 'OL-' || v_lifecycle.mid,
            'jobId', v_job.job_id,
            'jobStatus', v_job.job_status,
            'alreadyPrepared', true
        );
    end if;

    if v_lifecycle.lifecycle_status not in (
        'PROBATION_REVIEW',
        'PROBATION_PASSED'
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Candidate must be in PROBATION_REVIEW or PROBATION_PASSED.';
    end if;

    if v_lifecycle.lifecycle_status = 'PROBATION_REVIEW' then
        update public.hr_lifecycle
        set
            lifecycle_status = 'PROBATION_PASSED',
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
            performed_at
        ) values (
            p_candidate_id,
            'PROBATION_PASSED',
            'PROBATION_REVIEW',
            'PROBATION_PASSED',
            'Candidate passed probation; automated offer preparation started',
            'SUCCESS',
            'HR',
            v_now
        );
    end if;

    v_mid := nullif(pg_catalog.btrim(v_lifecycle.mid), '');

    if v_mid is null then
        v_role_code := pg_catalog.upper(
            pg_catalog.btrim(v_candidate.role_code)
        );

        if v_role_code is null
           or v_role_code not in (
               'AUT', 'FSD', 'JAV', 'PMT', 'CPS', 'POS', 'CDT', 'NUT',
               'HPI', 'HRO', 'TAC', 'BDE', 'GDS', 'PDS', 'VED', 'PRL',
               'SMM', 'OPA', 'UIX', 'MKT', 'LGE',
               'AOP', 'BAI', 'CON', 'DAT', 'DES', 'FIN', 'HRI', 'HPS',
               'MOG', 'OPR', 'PRD', 'PYA', 'QAI', 'RES', 'SAM', 'SWI',
               'SUP'
           ) then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate role code is not valid for MID generation.';
        end if;

        v_clean_name := pg_catalog.btrim(
            pg_catalog.regexp_replace(
                coalesce(v_candidate.full_name, ''),
                '[^A-Za-z0-9_[:space:]]',
                '',
                'g'
            )
        );

        if v_clean_name = '' then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate name is required for MID generation.';
        end if;

        v_name_parts := pg_catalog.regexp_split_to_array(
            v_clean_name,
            '[[:space:]]+'
        );

        if pg_catalog.array_length(v_name_parts, 1) = 1 then
            v_name_code := pg_catalog.upper(
                pg_catalog.left(v_name_parts[1], 2)
            );
        else
            v_name_code := pg_catalog.upper(
                pg_catalog.left(v_name_parts[1], 1)
                || pg_catalog.left(
                    v_name_parts[pg_catalog.array_length(v_name_parts, 1)],
                    1
                )
            );
        end if;

        if v_name_code is null or v_name_code = '' then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate name code could not be generated.';
        end if;

        -- Preserve the existing MID format and current-year behavior while
        -- moving serial allocation from the browser into PostgreSQL.
        v_year_code := pg_catalog.to_char(
            pg_catalog.timezone('Asia/Kolkata', v_now),
            'YY'
        );
        v_mid_prefix := 'JCF-'
            || v_role_code
            || '-'
            || v_name_code
            || '-'
            || v_year_code;

        -- Serialize allocation for this exact role/name/year prefix.
        perform pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                'mid-prefix:' || v_mid_prefix,
                0::bigint
            )
        );

        select coalesce(
                   max(
                       pg_catalog.substr(
                           l.mid,
                           pg_catalog.length(v_mid_prefix) + 1,
                           3
                       )::integer
                   ),
                   0
               ) + 1
        into v_next_serial
        from public.hr_lifecycle l
        where l.mid ~ ('^' || v_mid_prefix || '[0-9]{3}$');

        if v_next_serial > 999 then
            raise exception using
                errcode = 'P0001',
                message = 'MID serial limit has been reached for this role/name/year.';
        end if;

        v_mid := v_mid_prefix
            || pg_catalog.lpad(v_next_serial::text, 3, '0');
    end if;

    update public.hr_lifecycle
    set
        lifecycle_status = 'MID_GENERATED',
        mid = v_mid,
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
        performed_at
    ) values (
        p_candidate_id,
        'MID_GENERATED',
        'PROBATION_PASSED',
        'MID_GENERATED',
        'MID generated atomically and offer automation queued',
        'SUCCESS',
        'HR',
        v_now
    );

    select aj.*
    into v_job
    from public.automation_jobs aj
    where aj.idempotency_key = v_idempotency_key
    for update;

    if v_job.job_id is not null
       and (
           v_job.job_type is distinct from 'OFFER_LETTER'
           or v_job.candidate_id is distinct from p_candidate_id
       ) then
        raise exception using
            errcode = 'P0001',
            message = 'Offer-letter automation state is inconsistent.';
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
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            'OFFER_LETTER',
            'PENDING',
            pg_catalog.jsonb_build_object(
                'mid', v_mid,
                'offerLetterNumber', 'OL-' || v_mid
            ),
            v_now,
            0,
            null,
            null,
            v_idempotency_key,
            v_actor_user_id,
            v_now,
            v_now
        )
        returning * into v_job;
    else
        v_already_prepared := true;
    end if;

    return pg_catalog.jsonb_build_object(
        'candidateId', p_candidate_id,
        'previousLifecycleStatus', v_from_status,
        'lifecycleStatus', 'MID_GENERATED',
        'mid', v_mid,
        'offerLetterNumber', 'OL-' || v_mid,
        'jobId', v_job.job_id,
        'jobStatus', v_job.job_status,
        'alreadyPrepared', v_already_prepared
    );
end;
$function$;

comment on function public.pass_probation_and_prepare_offer(uuid) is
    'Atomically records probation pass, allocates a unique MID using the existing JCF format, and queues one idempotent OFFER_LETTER automation job for the candidate.';

revoke all privileges
    on function public.pass_probation_and_prepare_offer(uuid)
    from public;
revoke all privileges
    on function public.pass_probation_and_prepare_offer(uuid)
    from anon;
revoke all privileges
    on function public.pass_probation_and_prepare_offer(uuid)
    from authenticated;

grant execute
    on function public.pass_probation_and_prepare_offer(uuid)
    to authenticated;
grant execute
    on function public.pass_probation_and_prepare_offer(uuid)
    to service_role;

commit;
