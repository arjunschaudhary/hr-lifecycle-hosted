begin;

-- The deployed frontend still uses authenticated direct table access. Phase 1A
-- therefore removes anonymous access and adds secure RPCs without enabling RLS
-- or changing authenticated table privileges.

create unique index if not exists uq_exit_cases_one_open_per_candidate
on public.exit_cases (candidate_id)
where overall_status <> 'COMPLETED';

create or replace function public.get_current_candidate_exit_case()
returns table (
    exit_case_id uuid,
    candidate_id uuid,
    exit_date date,
    exit_type text,
    overall_status text,
    candidate_form_completed boolean,
    hr_form_completed boolean,
    pod_name_snapshot text,
    created_at timestamptz,
    feedback_id uuid,
    feedback_submitted_at timestamptz,
    already_submitted boolean
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_candidate_id uuid;
begin
    if not public.current_user_is_active()
       or not public.current_user_has_any_role(array['CANDIDATE']::text[]) then
        raise exception using
            errcode = '42501',
            message = 'Candidate portal access is required.';
    end if;

    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise exception using
            errcode = '42501',
            message = 'An active candidate account is required.';
    end if;

    return query
    select
        ec.exit_case_id,
        ec.candidate_id,
        ec.exit_date,
        ec.exit_type::text,
        ec.overall_status::text,
        ec.candidate_form_completed,
        ec.hr_form_completed,
        ec.pod_name_snapshot,
        ec.created_at,
        cef.feedback_id,
        cef.submitted_at,
        (
            ec.candidate_form_completed
            or cef.feedback_id is not null
            or cef.submitted_at is not null
        ) as already_submitted
    from public.exit_cases ec
    left join public.candidate_exit_feedback cef
      on cef.exit_case_id = ec.exit_case_id
    where ec.candidate_id = v_candidate_id
    order by ec.created_at desc, ec.exit_case_id desc
    limit 1;
end;
$function$;

comment on function public.get_current_candidate_exit_case() is
    'Returns only the current authenticated candidate''s latest Exit case and candidate-submission state, including completed history. It never accepts a candidate identifier and never exposes HR evaluation data.';

create or replace function public.submit_current_candidate_exit_feedback(
    p_feedback jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_candidate_id uuid;
    v_case public.exit_cases%rowtype;
    v_feedback public.candidate_exit_feedback%rowtype;
    v_timestamp timestamptz := pg_catalog.now();
    v_handover_count integer := 0;
    v_inserted_handover_count integer := 0;
    v_successor_name text;
    v_repository_link text;
    v_transfer_documents text;
    v_access_to_revoke text;
    v_time_sensitive_notes text;
    v_overall_experience_rating integer;
    v_nps_score integer;
    v_learning_rating integer;
    v_guidance_rating integer;
    v_psychological_safety_rating integer;
    v_valued_contributor_rating integer;
    v_work_distribution_rating integer;
    v_pod_culture_rating integer;
    v_array_key text;
    v_text_key text;
    v_item jsonb;
begin
    if p_feedback is null
       or pg_catalog.jsonb_typeof(p_feedback) <> 'object' then
        raise exception using
            errcode = '22023',
            message = 'Exit feedback must be a valid object.';
    end if;

    if pg_catalog.octet_length(p_feedback::text) > 262144 then
        raise exception using
            errcode = '22023',
            message = 'Exit feedback is too large.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(array['CANDIDATE']::text[]) then
        raise exception using
            errcode = '42501',
            message = 'Candidate portal access is required.';
    end if;

    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise exception using
            errcode = '42501',
            message = 'An active candidate account is required.';
    end if;

    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.candidate_id = v_candidate_id
      and ec.overall_status <> 'COMPLETED'
    order by ec.created_at desc, ec.exit_case_id desc
    limit 1
    for update;

    if v_case.exit_case_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'No active exit case is available for this candidate.';
    end if;

    if v_case.candidate_form_completed
       or v_case.overall_status not in ('INITIATED', 'CANDIDATE_PENDING') then
        raise exception using
            errcode = '23505',
            message = 'Exit feedback has already been submitted for this case.';
    end if;

    if exists (
        select 1
        from public.candidate_exit_feedback cef
        where cef.exit_case_id = v_case.exit_case_id
    ) then
        raise exception using
            errcode = '23505',
            message = 'Exit feedback has already been submitted for this case.';
    end if;

    foreach v_text_key in array array[
        'completedFullDuration', 'primaryExitReason', 'otherReasonText',
        'preventableExit', 'wantedExtension', 'extensionReason',
        'expectationMatch', 'meaningfulWork', 'missingExposureOther',
        'feedbackFrequency', 'safetyIssue', 'safetyIssueDetails',
        'hrCommunicationOther', 'improvementOther', 'rejoinInterest',
        'briefedSomeone', 'personName', 'repositoryLink',
        'transferDocuments', 'accessToRevoke', 'timeSensitiveNotes'
    ] loop
        if p_feedback ? v_text_key
           and pg_catalog.jsonb_typeof(p_feedback -> v_text_key) not in ('string', 'null') then
            raise exception using
                errcode = '22023',
                message = 'One or more Exit feedback text fields are invalid.';
        end if;
    end loop;

    if pg_catalog.char_length(coalesce(p_feedback ->> 'primaryExitReason', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'preventableExit', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'wantedExtension', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'extensionReason', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'expectationMatch', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'meaningfulWork', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'feedbackFrequency', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'safetyIssue', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'rejoinInterest', '')) > 100
       or pg_catalog.char_length(coalesce(p_feedback ->> 'briefedSomeone', '')) > 100 then
        raise exception using
            errcode = '22023',
            message = 'One or more Exit feedback selections are too long.';
    end if;

    if pg_catalog.char_length(coalesce(p_feedback ->> 'otherReasonText', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'missingExposureOther', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'safetyIssueDetails', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'hrCommunicationOther', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'improvementOther', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'transferDocuments', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'accessToRevoke', '')) > 10000
       or pg_catalog.char_length(coalesce(p_feedback ->> 'timeSensitiveNotes', '')) > 10000 then
        raise exception using
            errcode = '22023',
            message = 'One or more Exit feedback text responses are too long.';
    end if;

    if pg_catalog.char_length(coalesce(p_feedback ->> 'personName', '')) > 500
       or pg_catalog.char_length(coalesce(p_feedback ->> 'repositoryLink', '')) > 2048 then
        raise exception using
            errcode = '22023',
            message = 'One or more Exit handover fields are too long.';
    end if;

    foreach v_array_key in array array[
        'otherExitReasons', 'missingExposure',
        'hrCommunicationIssues', 'improvementSuggestions'
    ] loop
        if p_feedback ? v_array_key
           and pg_catalog.jsonb_typeof(p_feedback -> v_array_key) not in ('array', 'null') then
            raise exception using
                errcode = '22023',
                message = 'One or more Exit feedback selections are invalid.';
        end if;

        if pg_catalog.jsonb_typeof(p_feedback -> v_array_key) = 'array' then
            if pg_catalog.jsonb_array_length(p_feedback -> v_array_key) > 20 then
                raise exception using
                    errcode = '22023',
                    message = 'Too many Exit feedback selections were provided.';
            end if;

            if exists (
                select 1
                from pg_catalog.jsonb_array_elements(p_feedback -> v_array_key) as element(value)
                where pg_catalog.jsonb_typeof(element.value) <> 'string'
                   or pg_catalog.char_length(element.value #>> '{}') > 100
            ) then
                raise exception using
                    errcode = '22023',
                    message = 'One or more Exit feedback selections are invalid.';
            end if;
        end if;
    end loop;

    if p_feedback ? 'ongoingTasks'
       and pg_catalog.jsonb_typeof(p_feedback -> 'ongoingTasks') not in ('array', 'null') then
        raise exception using
            errcode = '22023',
            message = 'Exit handover tasks must be a valid list.';
    end if;

    if pg_catalog.jsonb_typeof(p_feedback -> 'ongoingTasks') = 'array' then
        if pg_catalog.jsonb_array_length(p_feedback -> 'ongoingTasks') > 50 then
            raise exception using
                errcode = '22023',
                message = 'Too many Exit handover tasks were provided.';
        end if;

        for v_item in
            select task.value
            from pg_catalog.jsonb_array_elements(p_feedback -> 'ongoingTasks') as task(value)
        loop
            if pg_catalog.jsonb_typeof(v_item) <> 'object' then
                raise exception using
                    errcode = '22023',
                    message = 'One or more Exit handover tasks are invalid.';
            end if;

            foreach v_text_key in array array['taskName', 'taskStatus', 'nextSteps'] loop
                if v_item ? v_text_key
                   and pg_catalog.jsonb_typeof(v_item -> v_text_key) not in ('string', 'null') then
                    raise exception using
                        errcode = '22023',
                        message = 'One or more Exit handover task fields are invalid.';
                end if;
            end loop;

            if nullif(pg_catalog.btrim(v_item ->> 'taskName'), '') is null then
                raise exception using
                    errcode = '22023',
                    message = 'Each Exit handover task must include a task name.';
            end if;

            if pg_catalog.char_length(v_item ->> 'taskName') > 500
               or pg_catalog.char_length(coalesce(v_item ->> 'taskStatus', '')) > 50
               or pg_catalog.char_length(coalesce(v_item ->> 'nextSteps', '')) > 10000 then
                raise exception using
                    errcode = '22023',
                    message = 'One or more Exit handover task fields are too long.';
            end if;
        end loop;
    end if;

    if p_feedback ->> 'completedFullDuration' is null
       or p_feedback ->> 'completedFullDuration' not in ('yes', 'no') then
        raise exception using
            errcode = '22023',
            message = 'Please indicate whether the full internship duration was completed.';
    end if;

    if nullif(pg_catalog.btrim(p_feedback ->> 'primaryExitReason'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'A primary Exit reason is required.';
    end if;

    if (
        p_feedback ->> 'primaryExitReason' = 'other'
        or coalesce((p_feedback -> 'otherExitReasons') ? 'other', false)
    ) and nullif(pg_catalog.btrim(p_feedback ->> 'otherReasonText'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Please specify the other Exit reason.';
    end if;

    if coalesce((p_feedback -> 'missingExposure') ? 'other', false)
       and nullif(pg_catalog.btrim(p_feedback ->> 'missingExposureOther'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Please specify the other exposure desired.';
    end if;

    if coalesce((p_feedback -> 'hrCommunicationIssues') ? 'other', false)
       and nullif(pg_catalog.btrim(p_feedback ->> 'hrCommunicationOther'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Please specify the other HR communication issue.';
    end if;

    if coalesce((p_feedback -> 'improvementSuggestions') ? 'other', false)
       and nullif(pg_catalog.btrim(p_feedback ->> 'improvementOther'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Please specify the other improvement suggestion.';
    end if;

    if p_feedback ->> 'briefedSomeone' = 'yes'
       and nullif(pg_catalog.btrim(p_feedback ->> 'personName'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Please provide the name of the person who was briefed.';
    end if;

    foreach v_text_key in array array[
        'overallExperienceRating', 'npsScore', 'learningRating',
        'guidanceRating', 'psychologicalSafetyRating',
        'valuedContributorRating', 'workDistributionRating', 'podCultureRating'
    ] loop
        if nullif(pg_catalog.btrim(p_feedback ->> v_text_key), '') is null
           or pg_catalog.btrim(p_feedback ->> v_text_key) !~ '^[0-9]{1,2}$' then
            raise exception using
                errcode = '22023',
                message = 'All required Exit feedback ratings must be valid whole numbers.';
        end if;
    end loop;

    v_overall_experience_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'overallExperienceRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'overallExperienceRating')::integer
        else null
    end;
    v_nps_score := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'npsScore'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'npsScore')::integer
        else null
    end;
    v_learning_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'learningRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'learningRating')::integer
        else null
    end;
    v_guidance_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'guidanceRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'guidanceRating')::integer
        else null
    end;
    v_psychological_safety_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'psychologicalSafetyRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'psychologicalSafetyRating')::integer
        else null
    end;
    v_valued_contributor_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'valuedContributorRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'valuedContributorRating')::integer
        else null
    end;
    v_work_distribution_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'workDistributionRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'workDistributionRating')::integer
        else null
    end;
    v_pod_culture_rating := case
        when nullif(pg_catalog.btrim(p_feedback ->> 'podCultureRating'), '') ~ '^[0-9]+$'
            then (p_feedback ->> 'podCultureRating')::integer
        else null
    end;

    if v_overall_experience_rating is null or v_overall_experience_rating not between 1 and 5
       or v_nps_score is null or v_nps_score not between 0 and 10
       or v_learning_rating is null or v_learning_rating not between 1 and 5
       or v_guidance_rating is null or v_guidance_rating not between 1 and 5
       or v_psychological_safety_rating is null or v_psychological_safety_rating not between 1 and 5
       or v_valued_contributor_rating is null or v_valued_contributor_rating not between 1 and 5
       or v_work_distribution_rating is null or v_work_distribution_rating not between 1 and 5
       or v_pod_culture_rating is null or v_pod_culture_rating not between 1 and 5 then
        raise exception using
            errcode = '22023',
            message = 'One or more Exit feedback ratings are invalid.';
    end if;

    insert into public.candidate_exit_feedback (
        exit_case_id,
        candidate_id,
        completed_full_duration,
        primary_exit_reason,
        other_exit_reasons,
        other_reason_text,
        preventable_exit,
        wanted_extension,
        extension_reason,
        overall_experience_rating,
        nps_score,
        expectation_match,
        learning_rating,
        meaningful_work,
        missing_exposure,
        missing_exposure_other,
        guidance_rating,
        feedback_frequency,
        psychological_safety_rating,
        valued_contributor_rating,
        work_distribution_rating,
        pod_culture_rating,
        safety_issue,
        safety_issue_details,
        is_confidential,
        hr_communication_issues,
        hr_communication_other,
        improvement_suggestions,
        improvement_other,
        rejoin_interest,
        submitted_at,
        created_at,
        updated_at
    )
    values (
        v_case.exit_case_id,
        v_candidate_id,
        case p_feedback ->> 'completedFullDuration'
            when 'yes' then true
            when 'no' then false
            else null
        end,
        nullif(pg_catalog.btrim(p_feedback ->> 'primaryExitReason'), ''),
        case
            when pg_catalog.jsonb_typeof(p_feedback -> 'otherExitReasons') = 'array'
                 and pg_catalog.jsonb_array_length(p_feedback -> 'otherExitReasons') > 0
            then array(
                select pg_catalog.jsonb_array_elements_text(p_feedback -> 'otherExitReasons')
            )
            else null
        end,
        nullif(pg_catalog.btrim(p_feedback ->> 'otherReasonText'), ''),
        nullif(pg_catalog.btrim(p_feedback ->> 'preventableExit'), ''),
        nullif(pg_catalog.btrim(p_feedback ->> 'wantedExtension'), ''),
        nullif(pg_catalog.btrim(p_feedback ->> 'extensionReason'), ''),
        v_overall_experience_rating,
        v_nps_score,
        nullif(pg_catalog.btrim(p_feedback ->> 'expectationMatch'), ''),
        v_learning_rating,
        nullif(pg_catalog.btrim(p_feedback ->> 'meaningfulWork'), ''),
        case
            when pg_catalog.jsonb_typeof(p_feedback -> 'missingExposure') = 'array'
                 and pg_catalog.jsonb_array_length(p_feedback -> 'missingExposure') > 0
            then array(
                select pg_catalog.jsonb_array_elements_text(p_feedback -> 'missingExposure')
            )
            else null
        end,
        nullif(pg_catalog.btrim(p_feedback ->> 'missingExposureOther'), ''),
        v_guidance_rating,
        nullif(pg_catalog.btrim(p_feedback ->> 'feedbackFrequency'), ''),
        v_psychological_safety_rating,
        v_valued_contributor_rating,
        v_work_distribution_rating,
        v_pod_culture_rating,
        nullif(pg_catalog.btrim(p_feedback ->> 'safetyIssue'), ''),
        nullif(pg_catalog.btrim(p_feedback ->> 'safetyIssueDetails'), ''),
        coalesce(p_feedback ->> 'safetyIssue', '') = 'yes',
        case
            when pg_catalog.jsonb_typeof(p_feedback -> 'hrCommunicationIssues') = 'array'
                 and pg_catalog.jsonb_array_length(p_feedback -> 'hrCommunicationIssues') > 0
            then array(
                select pg_catalog.jsonb_array_elements_text(p_feedback -> 'hrCommunicationIssues')
            )
            else null
        end,
        nullif(pg_catalog.btrim(p_feedback ->> 'hrCommunicationOther'), ''),
        case
            when pg_catalog.jsonb_typeof(p_feedback -> 'improvementSuggestions') = 'array'
                 and pg_catalog.jsonb_array_length(p_feedback -> 'improvementSuggestions') > 0
            then array(
                select pg_catalog.jsonb_array_elements_text(p_feedback -> 'improvementSuggestions')
            )
            else null
        end,
        nullif(pg_catalog.btrim(p_feedback ->> 'improvementOther'), ''),
        nullif(pg_catalog.btrim(p_feedback ->> 'rejoinInterest'), ''),
        v_timestamp,
        v_timestamp,
        v_timestamp
    )
    returning * into v_feedback;

    v_successor_name := case
        when p_feedback ->> 'briefedSomeone' = 'yes'
            then nullif(pg_catalog.btrim(p_feedback ->> 'personName'), '')
        else null
    end;
    v_repository_link := nullif(pg_catalog.btrim(p_feedback ->> 'repositoryLink'), '');
    v_transfer_documents := nullif(pg_catalog.btrim(p_feedback ->> 'transferDocuments'), '');
    v_access_to_revoke := nullif(pg_catalog.btrim(p_feedback ->> 'accessToRevoke'), '');
    v_time_sensitive_notes := nullif(pg_catalog.btrim(p_feedback ->> 'timeSensitiveNotes'), '');

    if pg_catalog.jsonb_typeof(p_feedback -> 'ongoingTasks') = 'array' then
        insert into public.exit_handover_items (
            exit_case_id,
            task_name,
            task_status,
            next_steps,
            successor_name,
            repository_link,
            transfer_documents,
            access_to_revoke,
            time_sensitive_notes,
            created_at,
            updated_at
        )
        select
            v_case.exit_case_id,
            pg_catalog.btrim(task.item ->> 'taskName'),
            coalesce(nullif(pg_catalog.btrim(task.item ->> 'taskStatus'), ''), 'IN_PROGRESS'),
            nullif(pg_catalog.btrim(task.item ->> 'nextSteps'), ''),
            v_successor_name,
            v_repository_link,
            v_transfer_documents,
            v_access_to_revoke,
            v_time_sensitive_notes,
            v_timestamp,
            v_timestamp
        from pg_catalog.jsonb_array_elements(p_feedback -> 'ongoingTasks') as task(item)
        where nullif(pg_catalog.btrim(task.item ->> 'taskName'), '') is not null;

        get diagnostics v_inserted_handover_count = row_count;
        v_handover_count := v_handover_count + v_inserted_handover_count;
    end if;

    if v_handover_count = 0
       and (
           v_successor_name is not null
           or v_repository_link is not null
           or v_transfer_documents is not null
           or v_access_to_revoke is not null
           or v_time_sensitive_notes is not null
       ) then
        insert into public.exit_handover_items (
            exit_case_id,
            task_name,
            task_status,
            successor_name,
            repository_link,
            transfer_documents,
            access_to_revoke,
            time_sensitive_notes,
            created_at,
            updated_at
        ) values (
            v_case.exit_case_id,
            'General Handover Notes',
            'COMPLETED',
            v_successor_name,
            v_repository_link,
            v_transfer_documents,
            v_access_to_revoke,
            v_time_sensitive_notes,
            v_timestamp,
            v_timestamp
        );
        v_handover_count := 1;
    end if;

    update public.exit_cases
    set
        candidate_form_completed = true,
        overall_status = 'HR_PENDING',
        updated_at = v_timestamp
    where exit_case_id = v_case.exit_case_id
      and candidate_id = v_candidate_id
      and candidate_form_completed = false
      and overall_status in ('INITIATED', 'CANDIDATE_PENDING');

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case state changed before feedback could be submitted.';
    end if;

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
    ) values (
        v_candidate_id,
        'CANDIDATE_EXIT_FEEDBACK_SUBMITTED',
        v_case.overall_status,
        'HR_PENDING',
        'Candidate submitted the Exit questionnaire',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'exit_case_id', v_case.exit_case_id,
            'feedback_id', v_feedback.feedback_id,
            'handover_item_count', v_handover_count
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return pg_catalog.jsonb_build_object(
        'exitCaseId', v_case.exit_case_id,
        'candidateId', v_candidate_id,
        'feedbackId', v_feedback.feedback_id,
        'candidateFormCompleted', true,
        'overallStatus', 'HR_PENDING',
        'submittedAt', v_feedback.submitted_at,
        'handoverItemCount', v_handover_count
    );
end;
$function$;

comment on function public.submit_current_candidate_exit_feedback(jsonb) is
    'Atomically submits the current candidate''s Exit questionnaire and candidate handover, moves the open Exit case to HR_PENDING, and records a sanitized audit event. Candidate and case ownership are server-derived.';

create or replace function public.initiate_candidate_exit(
    p_candidate_id uuid,
    p_exit_type text,
    p_exit_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_candidate public.master_candidates%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_case public.exit_cases%rowtype;
    v_exit_type text := pg_catalog.upper(nullif(pg_catalog.btrim(p_exit_type), ''));
    v_timestamp timestamptz := pg_catalog.now();
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN',
               'HR_LEAD',
               'HR_SITE_CONNECT',
               'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE',
               'HR_EXECUTIVE_LEAD',
               'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using
            errcode = '42501',
            message = 'Authorized HR access is required.';
    end if;

    if p_candidate_id is null then
        raise exception using errcode = '22023', message = 'Candidate is required.';
    end if;

    if v_exit_type is null
       or v_exit_type not in ('COMPLETED_TERM', 'EARLY_EXIT', 'TERMINATED') then
        raise exception using errcode = '22023', message = 'A valid Exit type is required.';
    end if;

    if p_exit_date is null then
        raise exception using errcode = '22023', message = 'Exit date is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('candidate-exit:' || p_candidate_id::text, 0)
    );

    select mc.*
    into v_candidate
    from public.master_candidates mc
    where mc.candidate_id = p_candidate_id;

    if v_candidate.candidate_id is null then
        raise exception using errcode = 'P0001', message = 'Candidate was not found.';
    end if;

    select hl.*
    into v_lifecycle
    from public.hr_lifecycle hl
    where hl.candidate_id = p_candidate_id
    order by hl.updated_at desc, hl.lifecycle_id desc
    limit 1;

    if v_lifecycle.lifecycle_id is null then
        raise exception using
            errcode = 'P0001',
            message = 'No lifecycle record was found for this candidate.';
    end if;

    if not exists (
        select 1
        from public.hr_lifecycle hl
        left join public.hr_offer_letters hol
          on hol.candidate_id = hl.candidate_id
        where hl.candidate_id = p_candidate_id
          and (
              hl.lifecycle_status = 'ACTIVE'
              or hol.offer_status = 'OFFER_LETTER_SENT'
          )
    ) then
        raise exception using
            errcode = 'P0001',
            message = 'Exit can only be initiated for a candidate in the Active Interns workflow.';
    end if;

    if exists (
        select 1
        from public.exit_cases ec
        where ec.candidate_id = p_candidate_id
          and ec.overall_status <> 'COMPLETED'
    ) then
        raise exception using
            errcode = '23505',
            message = 'An Exit process has already been initiated for this candidate.';
    end if;

    begin
        insert into public.exit_cases (
            candidate_id,
            lifecycle_id,
            pod_id,
            initiated_by,
            mid,
            pod_name_snapshot,
            exit_date,
            exit_type,
            overall_status,
            candidate_form_completed,
            hr_form_completed,
            created_at,
            updated_at
        ) values (
            p_candidate_id,
            v_lifecycle.lifecycle_id,
            null,
            v_actor_user_id,
            v_lifecycle.mid,
            v_candidate.department,
            p_exit_date,
            v_exit_type,
            'INITIATED',
            false,
            false,
            v_timestamp,
            v_timestamp
        )
        returning * into v_case;
    exception
        when unique_violation then
            raise exception using
                errcode = '23505',
                message = 'An Exit process has already been initiated for this candidate.';
    end;

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
    ) values (
        p_candidate_id,
        'EXIT_INITIATED',
        null,
        'INITIATED',
        'Exit process initiated by an authorized HR user',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'exit_case_id', v_case.exit_case_id,
            'exit_type', v_case.exit_type,
            'exit_date', v_case.exit_date
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return pg_catalog.jsonb_build_object(
        'exitCaseId', v_case.exit_case_id,
        'candidateId', v_case.candidate_id,
        'lifecycleId', v_case.lifecycle_id,
        'mid', v_case.mid,
        'podNameSnapshot', v_case.pod_name_snapshot,
        'exitDate', v_case.exit_date,
        'exitType', v_case.exit_type,
        'overallStatus', v_case.overall_status,
        'candidateFormCompleted', v_case.candidate_form_completed,
        'hrFormCompleted', v_case.hr_form_completed,
        'createdAt', v_case.created_at
    );
end;
$function$;

comment on function public.initiate_candidate_exit(uuid, text, date) is
    'Atomically creates one open Exit case for a candidate currently eligible for the Active Interns workflow. The authorized HR initiator, lifecycle, MID, and existing department snapshot are resolved server-side.';

create or replace function public.get_hr_exit_queue()
returns table (
    exit_case_id uuid,
    candidate_id uuid,
    lifecycle_id uuid,
    mid text,
    pod_name_snapshot text,
    exit_date date,
    exit_type text,
    overall_status text,
    candidate_form_completed boolean,
    hr_form_completed boolean,
    created_at timestamptz,
    candidate_name text,
    candidate_email text,
    candidate_department text,
    probation_start_date date,
    current_end_date date,
    internship_duration_months integer
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    return query
    select
        ec.exit_case_id,
        ec.candidate_id,
        ec.lifecycle_id,
        ec.mid::text,
        ec.pod_name_snapshot,
        ec.exit_date,
        ec.exit_type::text,
        ec.overall_status::text,
        ec.candidate_form_completed,
        ec.hr_form_completed,
        ec.created_at,
        mc.full_name::text,
        mc.email::text,
        mc.department::text,
        hl.probation_start_date,
        hl.current_end_date,
        hl.internship_duration_months
    from public.exit_cases ec
    join public.master_candidates mc
      on mc.candidate_id = ec.candidate_id
    join public.hr_lifecycle hl
      on hl.lifecycle_id = ec.lifecycle_id
    where ec.candidate_form_completed = true
      and ec.hr_form_completed = false
    order by ec.created_at desc, ec.exit_case_id desc;
end;
$function$;

comment on function public.get_hr_exit_queue() is
    'Returns the existing pending HR Exit evaluation queue to active users in the current staff access group.';

create or replace function public.get_hr_open_exit_cases()
returns table (
    exit_case_id uuid,
    candidate_id uuid,
    overall_status text,
    candidate_form_completed boolean,
    hr_form_completed boolean,
    created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    return query
    select
        ec.exit_case_id,
        ec.candidate_id,
        ec.overall_status::text,
        ec.candidate_form_completed,
        ec.hr_form_completed,
        ec.created_at
    from public.exit_cases ec
    where ec.overall_status <> 'COMPLETED'
    order by ec.created_at desc, ec.exit_case_id desc;
end;
$function$;

comment on function public.get_hr_open_exit_cases() is
    'Returns the minimal open Exit case status fields required by the authorized staff Active Interns workspace.';

create or replace function public.get_hr_exit_case(
    p_exit_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_result jsonb;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;

    select pg_catalog.jsonb_build_object(
        'exitCase', pg_catalog.jsonb_build_object(
            'exit_case_id', ec.exit_case_id,
            'candidate_id', ec.candidate_id,
            'lifecycle_id', ec.lifecycle_id,
            'mid', ec.mid,
            'pod_name_snapshot', ec.pod_name_snapshot,
            'exit_date', ec.exit_date,
            'exit_type', ec.exit_type,
            'overall_status', ec.overall_status,
            'candidate_form_completed', ec.candidate_form_completed,
            'hr_form_completed', ec.hr_form_completed,
            'exit_completed_at', ec.exit_completed_at,
            'created_at', ec.created_at,
            'master_candidates', pg_catalog.jsonb_build_object(
                'full_name', mc.full_name,
                'email', mc.email,
                'phone', mc.phone,
                'department', mc.department,
                'applied_role', mc.applied_role
            ),
            'hr_lifecycle', pg_catalog.jsonb_build_object(
                'probation_start_date', hl.probation_start_date,
                'current_end_date', hl.current_end_date,
                'original_end_date', hl.original_end_date,
                'internship_duration_months', hl.internship_duration_months
            )
        ),
        'candidateFeedback', (
            select pg_catalog.to_jsonb(cef)
            from public.candidate_exit_feedback cef
            where cef.exit_case_id = ec.exit_case_id
        ),
        'existingEvaluation', (
            select pg_catalog.jsonb_build_object(
                'evaluation_id', hee.evaluation_id,
                'submitted_at', hee.submitted_at
            )
            from public.hr_exit_evaluations hee
            where hee.exit_case_id = ec.exit_case_id
        ),
        'existingHandoverItems', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(ehi) order by ehi.created_at, ehi.handover_item_id)
            from public.exit_handover_items ehi
            where ehi.exit_case_id = ec.exit_case_id
        ), '[]'::jsonb),
        'reviewer', (
            select pg_catalog.jsonb_build_object(
                'id', u.id,
                'name', u.name,
                'email', u.email,
                'role', coalesce(r.label, 'HR Evaluator')
            )
            from public.users u
            left join public.roles r on r.id = u.role_id
            where u.id = v_actor_user_id
        ),
        'staffUsers', coalesce((
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'value', u.id,
                    'label', u.name || ' (' || u.email || ')'
                )
                order by u.name, u.id
            )
            from public.users u
            where u.status = 'active'
        ), '[]'::jsonb)
    )
    into v_result
    from public.exit_cases ec
    join public.master_candidates mc
      on mc.candidate_id = ec.candidate_id
    join public.hr_lifecycle hl
      on hl.lifecycle_id = ec.lifecycle_id
    where ec.exit_case_id = p_exit_case_id;

    if v_result is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found.';
    end if;

    return v_result;
end;
$function$;

comment on function public.get_hr_exit_case(uuid) is
    'Returns one authorized HR Exit evaluation workspace record. Existing HR evaluation data is limited to submission state; candidate feedback and current handover data remain available to the HR evaluation screen.';

create or replace function public.get_exit_analytics(
    p_filters jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
    v_exit_type text;
    v_overall_status text;
    v_start_date date;
    v_end_date date;
    v_start_date_text text;
    v_end_date_text text;
    v_filter_key text;
    v_result jsonb;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    if pg_catalog.jsonb_typeof(v_filters) <> 'object' then
        raise exception using errcode = '22023', message = 'Exit analytics filters must be a valid object.';
    end if;

    if pg_catalog.octet_length(v_filters::text) > 8192 then
        raise exception using errcode = '22023', message = 'Exit analytics filters are too large.';
    end if;

    foreach v_filter_key in array array[
        'exitType', 'overallStatus', 'startDate', 'endDate',
        'department', 'completedInternship', 'rehireEligibility'
    ] loop
        if v_filters ? v_filter_key
           and pg_catalog.jsonb_typeof(v_filters -> v_filter_key) not in ('string', 'null') then
            raise exception using errcode = '22023', message = 'One or more Exit analytics filters are invalid.';
        end if;

        if pg_catalog.char_length(coalesce(v_filters ->> v_filter_key, '')) > 200 then
            raise exception using errcode = '22023', message = 'One or more Exit analytics filters are too long.';
        end if;
    end loop;

    v_exit_type := nullif(pg_catalog.btrim(v_filters ->> 'exitType'), '');
    v_overall_status := nullif(pg_catalog.btrim(v_filters ->> 'overallStatus'), '');
    v_start_date_text := nullif(pg_catalog.btrim(v_filters ->> 'startDate'), '');
    v_end_date_text := nullif(pg_catalog.btrim(v_filters ->> 'endDate'), '');

    if v_exit_type = 'ALL' then v_exit_type := null; end if;
    if v_overall_status = 'ALL' then v_overall_status := null; end if;

    if v_start_date_text is not null then
        if v_start_date_text !~ '^\d{4}-\d{2}-\d{2}$' then
            raise exception using errcode = '22023', message = 'Exit analytics start date is invalid.';
        end if;
        v_start_date := v_start_date_text::date;
    end if;

    if v_end_date_text is not null then
        if v_end_date_text !~ '^\d{4}-\d{2}-\d{2}$' then
            raise exception using errcode = '22023', message = 'Exit analytics end date is invalid.';
        end if;
        v_end_date := v_end_date_text::date;
    end if;

    with filtered_cases as (
        select
            ec.*,
            mc.full_name as candidate_name,
            mc.department as candidate_department
        from public.exit_cases ec
        join public.master_candidates mc
          on mc.candidate_id = ec.candidate_id
        left join public.candidate_exit_feedback cef
          on cef.exit_case_id = ec.exit_case_id
        left join public.hr_exit_evaluations hee
          on hee.exit_case_id = ec.exit_case_id
        where (v_exit_type is null or ec.exit_type = v_exit_type)
          and (v_overall_status is null or ec.overall_status = v_overall_status)
          and (v_start_date is null or ec.exit_date >= v_start_date)
          and (v_end_date is null or ec.exit_date <= v_end_date)
    )
    select pg_catalog.jsonb_build_object(
        'exitCases', coalesce((
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'exit_case_id', fc.exit_case_id,
                    'candidate_id', fc.candidate_id,
                    'lifecycle_id', fc.lifecycle_id,
                    'pod_id', fc.pod_id,
                    'mid', fc.mid,
                    'pod_name_snapshot', fc.pod_name_snapshot,
                    'exit_date', fc.exit_date,
                    'exit_type', fc.exit_type,
                    'overall_status', fc.overall_status,
                    'candidate_form_completed', fc.candidate_form_completed,
                    'hr_form_completed', fc.hr_form_completed,
                    'exit_completed_at', fc.exit_completed_at,
                    'created_at', fc.created_at,
                    'master_candidates', pg_catalog.jsonb_build_object(
                        'full_name', fc.candidate_name,
                        'department', fc.candidate_department
                    )
                )
                order by fc.exit_date desc, fc.exit_case_id
            )
            from filtered_cases fc
        ), '[]'::jsonb),
        'candidateFeedbacks', coalesce((
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'exit_case_id', cef.exit_case_id,
                    'completed_full_duration', cef.completed_full_duration,
                    'primary_exit_reason', cef.primary_exit_reason,
                    'preventable_exit', cef.preventable_exit,
                    'overall_experience_rating', cef.overall_experience_rating,
                    'nps_score', cef.nps_score,
                    'learning_rating', cef.learning_rating,
                    'guidance_rating', cef.guidance_rating,
                    'psychological_safety_rating', cef.psychological_safety_rating,
                    'valued_contributor_rating', cef.valued_contributor_rating,
                    'work_distribution_rating', cef.work_distribution_rating,
                    'pod_culture_rating', cef.pod_culture_rating
                )
                order by cef.exit_case_id
            )
            from public.candidate_exit_feedback cef
            join filtered_cases fc on fc.exit_case_id = cef.exit_case_id
        ), '[]'::jsonb),
        'hrEvaluations', coalesce((
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object(
                    'exit_case_id', hee.exit_case_id,
                    'reviewer_id', hee.reviewer_id,
                    'skill_rating', hee.skill_rating,
                    'communication_rating', hee.communication_rating,
                    'ownership_rating', hee.ownership_rating,
                    'reliability_rating', hee.reliability_rating,
                    'collaboration_rating', hee.collaboration_rating,
                    'adaptability_rating', hee.adaptability_rating,
                    'timeliness_rating', hee.timeliness_rating,
                    'independence_rating', hee.independence_rating,
                    'rehire_eligibility', hee.rehire_eligibility,
                    'handover_complete', hee.handover_complete,
                    'handover_method', hee.handover_method,
                    'handover_gap', hee.handover_gap,
                    'verified_by', hee.verified_by,
                    'submitted_at', hee.submitted_at
                )
                order by hee.exit_case_id
            )
            from public.hr_exit_evaluations hee
            join filtered_cases fc on fc.exit_case_id = hee.exit_case_id
        ), '[]'::jsonb),
        'handoverItems', coalesce((
            select pg_catalog.jsonb_agg(
                pg_catalog.jsonb_build_object('exit_case_id', ehi.exit_case_id)
                order by ehi.exit_case_id, ehi.handover_item_id
            )
            from public.exit_handover_items ehi
            join filtered_cases fc on fc.exit_case_id = ehi.exit_case_id
        ), '[]'::jsonb)
    ) into v_result;

    return v_result;
exception
    when datetime_field_overflow then
        raise exception using errcode = '22023', message = 'One or more Exit analytics dates are invalid.';
end;
$function$;

comment on function public.get_exit_analytics(jsonb) is
    'Returns only the non-confidential raw fields currently required for authorized staff Exit analytics aggregation. Exit type, workflow status, and date filters may be applied server-side; department, completion, and rehire filters remain client-side so department options retain their current semantics. Safety narratives, questionnaire free text, and HR internal notes are excluded.';

create or replace function public.get_completed_exit_case_details(
    p_exit_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_result jsonb;
begin
    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;

    select pg_catalog.jsonb_build_object(
        'exitCase', pg_catalog.jsonb_build_object(
            'exit_case_id', ec.exit_case_id,
            'candidate_id', ec.candidate_id,
            'lifecycle_id', ec.lifecycle_id,
            'mid', ec.mid,
            'pod_name_snapshot', ec.pod_name_snapshot,
            'exit_date', ec.exit_date,
            'exit_type', ec.exit_type,
            'overall_status', ec.overall_status,
            'candidate_form_completed', ec.candidate_form_completed,
            'hr_form_completed', ec.hr_form_completed,
            'exit_completed_at', ec.exit_completed_at,
            'created_at', ec.created_at,
            'master_candidates', pg_catalog.jsonb_build_object(
                'full_name', mc.full_name,
                'email', mc.email,
                'phone', mc.phone,
                'department', mc.department,
                'applied_role', mc.applied_role
            ),
            'hr_lifecycle', pg_catalog.jsonb_build_object(
                'probation_start_date', hl.probation_start_date,
                'current_end_date', hl.current_end_date,
                'original_end_date', hl.original_end_date,
                'internship_duration_months', hl.internship_duration_months
            )
        ),
        'candidateFeedback', (
            select pg_catalog.to_jsonb(cef)
            from public.candidate_exit_feedback cef
            where cef.exit_case_id = ec.exit_case_id
        ),
        'hrEvaluation', (
            select pg_catalog.to_jsonb(hee)
            from public.hr_exit_evaluations hee
            where hee.exit_case_id = ec.exit_case_id
        ),
        'handoverItems', coalesce((
            select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(ehi) order by ehi.created_at, ehi.handover_item_id)
            from public.exit_handover_items ehi
            where ehi.exit_case_id = ec.exit_case_id
        ), '[]'::jsonb),
        'reviewer', (
            select pg_catalog.jsonb_build_object(
                'name', reviewer.name,
                'email', reviewer.email,
                'role', coalesce(reviewer_role.label, 'HR Executive')
            )
            from public.hr_exit_evaluations hee
            join public.users reviewer on reviewer.id = hee.reviewer_id
            left join public.roles reviewer_role on reviewer_role.id = reviewer.role_id
            where hee.exit_case_id = ec.exit_case_id
        ),
        'verifier', (
            select pg_catalog.jsonb_build_object(
                'name', verifier.name,
                'email', verifier.email
            )
            from public.hr_exit_evaluations hee
            join public.users verifier on verifier.id = hee.verified_by
            where hee.exit_case_id = ec.exit_case_id
        )
    )
    into v_result
    from public.exit_cases ec
    join public.master_candidates mc
      on mc.candidate_id = ec.candidate_id
    join public.hr_lifecycle hl
      on hl.lifecycle_id = ec.lifecycle_id
    where ec.exit_case_id = p_exit_case_id
      and ec.overall_status = 'COMPLETED';

    if v_result is null then
        raise exception using
            errcode = 'P0001',
            message = 'Completed Exit case was not found.';
    end if;

    return v_result;
end;
$function$;

comment on function public.get_completed_exit_case_details(uuid) is
    'Returns the complete historical Exit record for one completed case to an active authorized staff user.';

create or replace function public.submit_hr_exit_evaluation(
    p_exit_case_id uuid,
    p_evaluation jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_actor_user_id uuid;
    v_case public.exit_cases%rowtype;
    v_evaluation public.hr_exit_evaluations%rowtype;
    v_timestamp timestamptz := pg_catalog.now();
    v_verified_by uuid;
    v_verified_by_text text;
    v_handover_count integer := 0;
    v_skill_rating integer;
    v_communication_rating integer;
    v_ownership_rating integer;
    v_reliability_rating integer;
    v_collaboration_rating integer;
    v_adaptability_rating integer;
    v_timeliness_rating integer;
    v_independence_rating integer;
    v_array_key text;
    v_text_key text;
    v_item jsonb;
begin
    if p_exit_case_id is null then
        raise exception using errcode = '22023', message = 'Exit case is required.';
    end if;

    if p_evaluation is null
       or pg_catalog.jsonb_typeof(p_evaluation) <> 'object' then
        raise exception using errcode = '22023', message = 'HR Exit evaluation must be a valid object.';
    end if;

    if pg_catalog.octet_length(p_evaluation::text) > 262144 then
        raise exception using errcode = '22023', message = 'HR Exit evaluation is too large.';
    end if;

    v_actor_user_id := public.current_app_user_id();

    if v_actor_user_id is null
       or not public.current_user_has_any_role(
           array[
               'ADMIN', 'HR_LEAD', 'HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD',
               'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'FOUNDERS_OFFICE'
           ]::text[]
       ) then
        raise exception using errcode = '42501', message = 'Authorized HR access is required.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exit-case:' || p_exit_case_id::text, 0)
    );

    select ec.*
    into v_case
    from public.exit_cases ec
    where ec.exit_case_id = p_exit_case_id
    for update;

    if v_case.exit_case_id is null then
        raise exception using errcode = 'P0001', message = 'Exit case was not found.';
    end if;

    if not v_case.candidate_form_completed
       or v_case.hr_form_completed
       or v_case.overall_status <> 'HR_PENDING' then
        raise exception using
            errcode = 'P0001',
            message = 'This Exit case is not eligible for HR evaluation.';
    end if;

    if exists (
        select 1
        from public.hr_exit_evaluations hee
        where hee.exit_case_id = p_exit_case_id
    ) then
        raise exception using
            errcode = '23505',
            message = 'HR evaluation has already been submitted for this Exit case.';
    end if;

    foreach v_text_key in array array[
        'hrPrimaryReason', 'hrPreventable', 'retentionAttempt',
        'retentionNotes', 'extensionOffer', 'leadExtensionRecommendation',
        'rehireEligibility', 'internalNotes', 'candidateSummary',
        'handoverComplete', 'handoverGap', 'verifiedBy'
    ] loop
        if p_evaluation ? v_text_key
           and pg_catalog.jsonb_typeof(p_evaluation -> v_text_key) not in ('string', 'null') then
            raise exception using
                errcode = '22023',
                message = 'One or more HR Exit evaluation text fields are invalid.';
        end if;
    end loop;

    if pg_catalog.char_length(coalesce(p_evaluation ->> 'hrPrimaryReason', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'hrPreventable', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'retentionAttempt', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'extensionOffer', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'leadExtensionRecommendation', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'rehireEligibility', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'handoverComplete', '')) > 100
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'verifiedBy', '')) > 100 then
        raise exception using
            errcode = '22023',
            message = 'One or more HR Exit evaluation selections are too long.';
    end if;

    if pg_catalog.char_length(coalesce(p_evaluation ->> 'retentionNotes', '')) > 10000
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'internalNotes', '')) > 10000
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'candidateSummary', '')) > 10000
       or pg_catalog.char_length(coalesce(p_evaluation ->> 'handoverGap', '')) > 10000 then
        raise exception using
            errcode = '22023',
            message = 'One or more HR Exit evaluation text responses are too long.';
    end if;

    foreach v_array_key in array array['hrOtherReasons', 'handoverMethod'] loop
        if p_evaluation ? v_array_key
           and pg_catalog.jsonb_typeof(p_evaluation -> v_array_key) not in ('array', 'null') then
            raise exception using
                errcode = '22023',
                message = 'One or more HR Exit evaluation selections are invalid.';
        end if;

        if pg_catalog.jsonb_typeof(p_evaluation -> v_array_key) = 'array' then
            if pg_catalog.jsonb_array_length(p_evaluation -> v_array_key) > 20 then
                raise exception using
                    errcode = '22023',
                    message = 'Too many HR Exit evaluation selections were provided.';
            end if;

            if exists (
                select 1
                from pg_catalog.jsonb_array_elements(p_evaluation -> v_array_key) as element(value)
                where pg_catalog.jsonb_typeof(element.value) <> 'string'
                   or pg_catalog.char_length(element.value #>> '{}') > 100
            ) then
                raise exception using
                    errcode = '22023',
                    message = 'One or more HR Exit evaluation selections are invalid.';
            end if;
        end if;
    end loop;

    if p_evaluation ? 'handoverItems'
       and pg_catalog.jsonb_typeof(p_evaluation -> 'handoverItems') not in ('array', 'null') then
        raise exception using
            errcode = '22023',
            message = 'HR Exit handover items must be a valid list.';
    end if;

    if pg_catalog.jsonb_typeof(p_evaluation -> 'handoverItems') = 'array' then
        if pg_catalog.jsonb_array_length(p_evaluation -> 'handoverItems') > 50 then
            raise exception using
                errcode = '22023',
                message = 'Too many HR Exit handover items were provided.';
        end if;

        for v_item in
            select item.value
            from pg_catalog.jsonb_array_elements(p_evaluation -> 'handoverItems') as item(value)
        loop
            if pg_catalog.jsonb_typeof(v_item) <> 'object' then
                raise exception using
                    errcode = '22023',
                    message = 'One or more HR Exit handover items are invalid.';
            end if;

            foreach v_text_key in array array[
                'taskName', 'taskStatus', 'nextSteps', 'successorName',
                'repositoryLink', 'transferDocuments',
                'accessToRevoke', 'timeSensitiveNotes'
            ] loop
                if v_item ? v_text_key
                   and pg_catalog.jsonb_typeof(v_item -> v_text_key) not in ('string', 'null') then
                    raise exception using
                        errcode = '22023',
                        message = 'One or more HR Exit handover item fields are invalid.';
                end if;
            end loop;

            if nullif(pg_catalog.btrim(v_item ->> 'taskName'), '') is null then
                raise exception using
                    errcode = '22023',
                    message = 'Each HR Exit handover item must include a task name.';
            end if;

            if pg_catalog.char_length(v_item ->> 'taskName') > 500
               or pg_catalog.char_length(coalesce(v_item ->> 'taskStatus', '')) > 50
               or pg_catalog.char_length(coalesce(v_item ->> 'successorName', '')) > 500
               or pg_catalog.char_length(coalesce(v_item ->> 'repositoryLink', '')) > 2048
               or pg_catalog.char_length(coalesce(v_item ->> 'nextSteps', '')) > 10000
               or pg_catalog.char_length(coalesce(v_item ->> 'transferDocuments', '')) > 10000
               or pg_catalog.char_length(coalesce(v_item ->> 'accessToRevoke', '')) > 10000
               or pg_catalog.char_length(coalesce(v_item ->> 'timeSensitiveNotes', '')) > 10000 then
                raise exception using
                    errcode = '22023',
                    message = 'One or more HR Exit handover item fields are too long.';
            end if;
        end loop;
    end if;

    if nullif(pg_catalog.btrim(p_evaluation ->> 'hrPrimaryReason'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'A primary HR Exit reason is required.';
    end if;

    if nullif(pg_catalog.btrim(p_evaluation ->> 'rehireEligibility'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Rehire eligibility is required.';
    end if;

    if nullif(pg_catalog.btrim(p_evaluation ->> 'retentionAttempt'), '') is not null
       and p_evaluation ->> 'retentionAttempt' not in ('yes', 'no') then
        raise exception using
            errcode = '22023',
            message = 'Retention attempt selection is invalid.';
    end if;

    if p_evaluation ->> 'retentionAttempt' = 'yes'
       and nullif(pg_catalog.btrim(p_evaluation ->> 'retentionNotes'), '') is null then
        raise exception using
            errcode = '22023',
            message = 'Retention notes are required when retention was attempted.';
    end if;

    foreach v_text_key in array array[
        'skillRating', 'communicationRating', 'ownershipRating',
        'reliabilityRating', 'collaborationRating', 'adaptabilityRating',
        'timelinessRating', 'independenceRating'
    ] loop
        if nullif(pg_catalog.btrim(p_evaluation ->> v_text_key), '') is null
           or pg_catalog.btrim(p_evaluation ->> v_text_key) !~ '^[0-9]$' then
            raise exception using
                errcode = '22023',
                message = 'All HR performance ratings must be valid whole numbers between 1 and 5.';
        end if;
    end loop;

    v_verified_by_text := nullif(pg_catalog.btrim(p_evaluation ->> 'verifiedBy'), '');

    if v_verified_by_text is null then
        v_verified_by := v_actor_user_id;
    else
        begin
            v_verified_by := v_verified_by_text::uuid;
        exception
            when invalid_text_representation then
                raise exception using errcode = '22023', message = 'Selected verifier is invalid.';
        end;

        if not exists (
            select 1
            from public.users u
            where u.id = v_verified_by
              and u.status = 'active'
        ) then
            raise exception using errcode = '22023', message = 'Selected verifier is not an active user.';
        end if;
    end if;

    v_skill_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'skillRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'skillRating')::integer
        else null
    end;
    v_communication_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'communicationRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'communicationRating')::integer
        else null
    end;
    v_ownership_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'ownershipRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'ownershipRating')::integer
        else null
    end;
    v_reliability_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'reliabilityRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'reliabilityRating')::integer
        else null
    end;
    v_collaboration_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'collaborationRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'collaborationRating')::integer
        else null
    end;
    v_adaptability_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'adaptabilityRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'adaptabilityRating')::integer
        else null
    end;
    v_timeliness_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'timelinessRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'timelinessRating')::integer
        else null
    end;
    v_independence_rating := case
        when nullif(pg_catalog.btrim(p_evaluation ->> 'independenceRating'), '') ~ '^[0-9]+$'
            then (p_evaluation ->> 'independenceRating')::integer
        else null
    end;

    if v_skill_rating is null or v_skill_rating not between 1 and 5
       or v_communication_rating is null or v_communication_rating not between 1 and 5
       or v_ownership_rating is null or v_ownership_rating not between 1 and 5
       or v_reliability_rating is null or v_reliability_rating not between 1 and 5
       or v_collaboration_rating is null or v_collaboration_rating not between 1 and 5
       or v_adaptability_rating is null or v_adaptability_rating not between 1 and 5
       or v_timeliness_rating is null or v_timeliness_rating not between 1 and 5
       or v_independence_rating is null or v_independence_rating not between 1 and 5 then
        raise exception using
            errcode = '22023',
            message = 'All HR performance ratings must be between 1 and 5.';
    end if;

    insert into public.hr_exit_evaluations (
        exit_case_id,
        reviewer_id,
        skill_rating,
        communication_rating,
        ownership_rating,
        reliability_rating,
        collaboration_rating,
        adaptability_rating,
        timeliness_rating,
        independence_rating,
        hr_primary_reason,
        hr_other_reasons,
        hr_preventable,
        retention_attempt,
        retention_notes,
        extension_offer,
        lead_extension_recommendation,
        rehire_eligibility,
        internal_notes,
        candidate_summary,
        handover_complete,
        handover_method,
        handover_gap,
        verified_by,
        submitted_at,
        created_at,
        updated_at
    ) values (
        p_exit_case_id,
        v_actor_user_id,
        v_skill_rating,
        v_communication_rating,
        v_ownership_rating,
        v_reliability_rating,
        v_collaboration_rating,
        v_adaptability_rating,
        v_timeliness_rating,
        v_independence_rating,
        nullif(pg_catalog.btrim(p_evaluation ->> 'hrPrimaryReason'), ''),
        case
            when pg_catalog.jsonb_typeof(p_evaluation -> 'hrOtherReasons') = 'array'
                 and pg_catalog.jsonb_array_length(p_evaluation -> 'hrOtherReasons') > 0
            then array(
                select pg_catalog.jsonb_array_elements_text(p_evaluation -> 'hrOtherReasons')
            )
            else null
        end,
        nullif(pg_catalog.btrim(p_evaluation ->> 'hrPreventable'), ''),
        p_evaluation ->> 'retentionAttempt' = 'yes',
        case
            when p_evaluation ->> 'retentionAttempt' = 'yes'
                then nullif(pg_catalog.btrim(p_evaluation ->> 'retentionNotes'), '')
            else null
        end,
        nullif(pg_catalog.btrim(p_evaluation ->> 'extensionOffer'), ''),
        nullif(pg_catalog.btrim(p_evaluation ->> 'leadExtensionRecommendation'), ''),
        nullif(pg_catalog.btrim(p_evaluation ->> 'rehireEligibility'), ''),
        nullif(pg_catalog.btrim(p_evaluation ->> 'internalNotes'), ''),
        nullif(pg_catalog.btrim(p_evaluation ->> 'candidateSummary'), ''),
        nullif(pg_catalog.btrim(p_evaluation ->> 'handoverComplete'), ''),
        case
            when pg_catalog.jsonb_typeof(p_evaluation -> 'handoverMethod') = 'array'
                 and pg_catalog.jsonb_array_length(p_evaluation -> 'handoverMethod') > 0
            then array(
                select pg_catalog.jsonb_array_elements_text(p_evaluation -> 'handoverMethod')
            )
            else null
        end,
        nullif(pg_catalog.btrim(p_evaluation ->> 'handoverGap'), ''),
        v_verified_by,
        v_timestamp,
        v_timestamp,
        v_timestamp
    )
    returning * into v_evaluation;

    if pg_catalog.jsonb_typeof(p_evaluation -> 'handoverItems') = 'array' then
        insert into public.exit_handover_items (
            exit_case_id,
            task_name,
            task_status,
            next_steps,
            successor_name,
            repository_link,
            transfer_documents,
            access_to_revoke,
            time_sensitive_notes,
            created_at,
            updated_at
        )
        select
            p_exit_case_id,
            pg_catalog.btrim(item.value ->> 'taskName'),
            coalesce(nullif(pg_catalog.btrim(item.value ->> 'taskStatus'), ''), 'COMPLETED'),
            nullif(pg_catalog.btrim(item.value ->> 'nextSteps'), ''),
            nullif(pg_catalog.btrim(item.value ->> 'successorName'), ''),
            nullif(pg_catalog.btrim(item.value ->> 'repositoryLink'), ''),
            nullif(pg_catalog.btrim(item.value ->> 'transferDocuments'), ''),
            nullif(pg_catalog.btrim(item.value ->> 'accessToRevoke'), ''),
            nullif(pg_catalog.btrim(item.value ->> 'timeSensitiveNotes'), ''),
            v_timestamp,
            v_timestamp
        from pg_catalog.jsonb_array_elements(p_evaluation -> 'handoverItems') as item(value)
        where nullif(pg_catalog.btrim(item.value ->> 'taskName'), '') is not null;

        get diagnostics v_handover_count = row_count;
    end if;

    update public.exit_cases
    set
        hr_form_completed = true,
        overall_status = 'COMPLETED',
        exit_completed_at = v_timestamp,
        updated_at = v_timestamp
    where exit_case_id = p_exit_case_id
      and candidate_form_completed = true
      and hr_form_completed = false
      and overall_status = 'HR_PENDING';

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'Exit case state changed before the HR evaluation could be submitted.';
    end if;

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
    ) values (
        v_case.candidate_id,
        'HR_EXIT_EVALUATION_SUBMITTED',
        'HR_PENDING',
        'COMPLETED',
        'HR Exit evaluation submitted by an authorized HR user',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'exit_case_id', p_exit_case_id,
            'evaluation_id', v_evaluation.evaluation_id,
            'handover_item_count', v_handover_count
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

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
    ) values (
        v_case.candidate_id,
        'EXIT_COMPLETED',
        'HR_PENDING',
        'COMPLETED',
        'Exit process completed after HR evaluation',
        'SUCCESS',
        pg_catalog.jsonb_build_object(
            'exit_case_id', p_exit_case_id,
            'evaluation_id', v_evaluation.evaluation_id
        ),
        v_actor_user_id::text,
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return pg_catalog.jsonb_build_object(
        'exitCaseId', p_exit_case_id,
        'candidateId', v_case.candidate_id,
        'evaluationId', v_evaluation.evaluation_id,
        'reviewerId', v_actor_user_id,
        'verifiedBy', v_verified_by,
        'hrFormCompleted', true,
        'overallStatus', 'COMPLETED',
        'exitCompletedAt', v_timestamp,
        'handoverItemCount', v_handover_count
    );
end;
$function$;

comment on function public.submit_hr_exit_evaluation(uuid, jsonb) is
    'Atomically submits one eligible HR Exit evaluation, derives the reviewer from the active authorized application user, validates the optional active verifier, completes the Exit case, and records sanitized audit events.';

revoke execute on function public.get_current_candidate_exit_case() from public;
revoke execute on function public.get_current_candidate_exit_case() from anon;
grant execute on function public.get_current_candidate_exit_case() to authenticated;
grant execute on function public.get_current_candidate_exit_case() to service_role;

revoke execute on function public.submit_current_candidate_exit_feedback(jsonb) from public;
revoke execute on function public.submit_current_candidate_exit_feedback(jsonb) from anon;
grant execute on function public.submit_current_candidate_exit_feedback(jsonb) to authenticated;
grant execute on function public.submit_current_candidate_exit_feedback(jsonb) to service_role;

revoke execute on function public.initiate_candidate_exit(uuid, text, date) from public;
revoke execute on function public.initiate_candidate_exit(uuid, text, date) from anon;
grant execute on function public.initiate_candidate_exit(uuid, text, date) to authenticated;
grant execute on function public.initiate_candidate_exit(uuid, text, date) to service_role;

revoke execute on function public.get_hr_exit_queue() from public;
revoke execute on function public.get_hr_exit_queue() from anon;
grant execute on function public.get_hr_exit_queue() to authenticated;
grant execute on function public.get_hr_exit_queue() to service_role;

revoke execute on function public.get_hr_open_exit_cases() from public;
revoke execute on function public.get_hr_open_exit_cases() from anon;
grant execute on function public.get_hr_open_exit_cases() to authenticated;
grant execute on function public.get_hr_open_exit_cases() to service_role;

revoke execute on function public.get_hr_exit_case(uuid) from public;
revoke execute on function public.get_hr_exit_case(uuid) from anon;
grant execute on function public.get_hr_exit_case(uuid) to authenticated;
grant execute on function public.get_hr_exit_case(uuid) to service_role;

revoke execute on function public.get_exit_analytics(jsonb) from public;
revoke execute on function public.get_exit_analytics(jsonb) from anon;
grant execute on function public.get_exit_analytics(jsonb) to authenticated;
grant execute on function public.get_exit_analytics(jsonb) to service_role;

revoke execute on function public.get_completed_exit_case_details(uuid) from public;
revoke execute on function public.get_completed_exit_case_details(uuid) from anon;
grant execute on function public.get_completed_exit_case_details(uuid) to authenticated;
grant execute on function public.get_completed_exit_case_details(uuid) to service_role;

revoke execute on function public.submit_hr_exit_evaluation(uuid, jsonb) from public;
revoke execute on function public.submit_hr_exit_evaluation(uuid, jsonb) from anon;
grant execute on function public.submit_hr_exit_evaluation(uuid, jsonb) to authenticated;
grant execute on function public.submit_hr_exit_evaluation(uuid, jsonb) to service_role;

revoke all privileges on table public.exit_cases from public;
revoke all privileges on table public.exit_cases from anon;
revoke all privileges on table public.candidate_exit_feedback from public;
revoke all privileges on table public.candidate_exit_feedback from anon;
revoke all privileges on table public.hr_exit_evaluations from public;
revoke all privileges on table public.hr_exit_evaluations from anon;
revoke all privileges on table public.exit_handover_items from public;
revoke all privileges on table public.exit_handover_items from anon;
revoke all privileges on table public.exit_clearance from public;
revoke all privileges on table public.exit_clearance from anon;
revoke all privileges on table public.exit_documents from public;
revoke all privileges on table public.exit_documents from anon;

commit;
