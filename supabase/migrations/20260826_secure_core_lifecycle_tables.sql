-- The normalized-email index prevents race-condition duplicates.
create unique index if not exists master_candidates_email_normalized_uidx
    on public.master_candidates (lower(btrim(email)));

-- Public candidate submission is routed through one atomic security-definer RPC.
create or replace function public.submit_candidate_application(p_application jsonb)
returns setof public.master_candidates
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_candidate public.master_candidates%rowtype;
    v_timestamp timestamptz := pg_catalog.now();
    v_first_name text;
    v_last_name text;
    v_full_name text;
    v_derived_first_name text;
    v_derived_last_name text;
    v_email text;
    v_phone text;
    v_alternate_phone text;
    v_address text;
    v_city text;
    v_state text;
    v_applied_role text;
    v_role_code text;
    v_expected_role_code text;
    v_department text;
    v_qualification text;
    v_college_name text;
    v_source text;
    v_referral_name text;
    v_availability_status text;
    v_notes text;
begin
    if p_application is null
       or pg_catalog.jsonb_typeof(p_application) <> 'object' then
        raise exception using
            errcode = '22023',
            message = 'Candidate application must be a JSON object.';
    end if;

    v_first_name := nullif(pg_catalog.btrim(p_application ->> 'first_name'), '');
    v_last_name := nullif(pg_catalog.btrim(p_application ->> 'last_name'), '');
    v_full_name := nullif(pg_catalog.btrim(p_application ->> 'full_name'), '');
    v_email := nullif(pg_catalog.lower(pg_catalog.btrim(p_application ->> 'email')), '');
    v_phone := nullif(pg_catalog.btrim(p_application ->> 'phone'), '');
    v_alternate_phone := nullif(pg_catalog.btrim(p_application ->> 'alternate_phone'), '');
    v_address := nullif(pg_catalog.btrim(p_application ->> 'address'), '');
    v_city := nullif(pg_catalog.btrim(p_application ->> 'city'), '');
    v_state := nullif(pg_catalog.btrim(p_application ->> 'state'), '');
    v_applied_role := nullif(pg_catalog.btrim(p_application ->> 'applied_role'), '');
    v_role_code := nullif(pg_catalog.upper(pg_catalog.btrim(p_application ->> 'role_code')), '');
    v_department := nullif(pg_catalog.btrim(p_application ->> 'department'), '');
    v_qualification := nullif(pg_catalog.btrim(p_application ->> 'qualification'), '');
    v_college_name := nullif(pg_catalog.btrim(p_application ->> 'college_name'), '');
    v_source := coalesce(
        nullif(pg_catalog.btrim(p_application ->> 'source'), ''),
        'Candidate Form'
    );
    v_referral_name := nullif(pg_catalog.btrim(p_application ->> 'referral_name'), '');
    v_availability_status := nullif(pg_catalog.btrim(p_application ->> 'availability_status'), '');
    v_notes := nullif(pg_catalog.btrim(p_application ->> 'notes'), '');

    if v_full_name is null then
        v_full_name := nullif(
            pg_catalog.btrim(pg_catalog.concat_ws(' ', v_first_name, v_last_name)),
            ''
        );
    end if;

    if v_email is null then
        raise exception using
            errcode = '22023',
            message = 'Email is required.';
    end if;

    if v_full_name is null then
        raise exception using
            errcode = '22023',
            message = 'Full name is required.';
    end if;

    v_derived_first_name := nullif(
        (pg_catalog.regexp_match(v_full_name, '^\S+'))[1],
        ''
    );
    v_derived_last_name := nullif(
        pg_catalog.btrim(
            pg_catalog.regexp_replace(v_full_name, '^\S+\s*', '')
        ),
        ''
    );
    v_first_name := coalesce(v_first_name, v_derived_first_name);
    v_last_name := coalesce(v_last_name, v_derived_last_name);

    if v_applied_role is null then
        raise exception using
            errcode = '22023',
            message = 'Applied role is required.';
    end if;

    if v_role_code is null then
        raise exception using
            errcode = '22023',
            message = 'Role code is required.';
    end if;

    v_expected_role_code := case v_applied_role
        when 'Business Analyst Intern' then 'BAI'
        when 'Content Intern' then 'CON'
        when 'Data Intern' then 'DAT'
        when 'Design Intern' then 'DES'
        when 'Finance Intern' then 'FIN'
        when 'HR Intern' then 'HRI'
        when 'Marketing Intern' then 'MKT'
        when 'Operation Intern' then 'OPR'
        when 'Product Intern' then 'PRD'
        when 'QA Intern' then 'QAI'
        when 'Research Intern' then 'RES'
        when 'Software Intern' then 'SWI'
        when 'Support Intern' then 'SUP'
        else null
    end;

    if v_expected_role_code is null then
        raise exception using
            errcode = '22023',
            message = 'Applied role is not approved.';
    end if;

    if v_role_code <> v_expected_role_code then
        raise exception using
            errcode = '22023',
            message = 'Role code does not match the selected applied role.';
    end if;

    insert into public.master_candidates (
        first_name,
        last_name,
        full_name,
        email,
        phone,
        alternate_phone,
        address,
        city,
        state,
        applied_role,
        role_code,
        department,
        qualification,
        college_name,
        source,
        referral_name,
        availability_status,
        notes,
        submitted_at,
        created_at,
        updated_at
    ) values (
        v_first_name,
        v_last_name,
        v_full_name,
        v_email,
        v_phone,
        v_alternate_phone,
        v_address,
        v_city,
        v_state,
        v_applied_role,
        v_role_code,
        v_department,
        v_qualification,
        v_college_name,
        v_source,
        v_referral_name,
        v_availability_status,
        v_notes,
        v_timestamp,
        v_timestamp,
        v_timestamp
    )
    returning * into v_candidate;

    insert into public.hr_lifecycle (
        candidate_id,
        lifecycle_status,
        created_at,
        updated_at
    ) values (
        v_candidate.candidate_id,
        'HR_REVIEW_PENDING',
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
        performed_by,
        performed_at,
        created_at,
        updated_at
    ) values (
        v_candidate.candidate_id,
        'CANDIDATE_FORM_SUBMITTED',
        null,
        'HR_REVIEW_PENDING',
        'Candidate form submitted and moved to HR review pending',
        'SUCCESS',
        'Candidate',
        v_timestamp,
        v_timestamp,
        v_timestamp
    );

    return next v_candidate;
    return;
exception
    when unique_violation then
        raise exception using
            errcode = '23505',
            message = 'Candidate with this email already exists.';
end;
$function$;

revoke all privileges on function public.submit_candidate_application(jsonb) from public;
grant execute on function public.submit_candidate_application(jsonb) to anon;
grant execute on function public.submit_candidate_application(jsonb) to authenticated;
grant execute on function public.submit_candidate_application(jsonb) to service_role;

-- Authenticated staff receive only operations required by the current frontend.
alter table public.master_candidates enable row level security;
alter table public.hr_lifecycle enable row level security;
alter table public.hr_activity_logs enable row level security;

drop policy if exists master_candidates_staff_select on public.master_candidates;
drop policy if exists hr_lifecycle_staff_select on public.hr_lifecycle;
drop policy if exists hr_lifecycle_staff_update on public.hr_lifecycle;
drop policy if exists hr_activity_logs_staff_select on public.hr_activity_logs;
drop policy if exists hr_activity_logs_staff_insert on public.hr_activity_logs;

create policy master_candidates_staff_select
on public.master_candidates
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy hr_lifecycle_staff_select
on public.hr_lifecycle
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy hr_lifecycle_staff_update
on public.hr_lifecycle
for update
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
)
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy hr_activity_logs_staff_select
on public.hr_activity_logs
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy hr_activity_logs_staff_insert
on public.hr_activity_logs
for insert
to authenticated
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

-- Anonymous users have no direct core-table access.
revoke all privileges on table public.master_candidates from anon;
revoke all privileges on table public.hr_lifecycle from anon;
revoke all privileges on table public.hr_activity_logs from anon;

revoke all privileges on table public.master_candidates from authenticated;
grant select on table public.master_candidates to authenticated;

revoke all privileges on table public.hr_lifecycle from authenticated;
grant select, update on table public.hr_lifecycle to authenticated;

revoke all privileges on table public.hr_activity_logs from authenticated;
grant select, insert on table public.hr_activity_logs to authenticated;

-- Candidate and intern self-service policies remain deferred.
-- Service-role privileges remain unchanged.
