-- Approved active staff can read and submit leave requests.
-- Approved active staff can approve or reject only requests belonging to other candidates.
-- Staff members who are also interns cannot approve or reject their own leave requests.
alter table public.leave_requests enable row level security;

drop policy if exists leave_requests_staff_select on public.leave_requests;
drop policy if exists leave_requests_staff_insert on public.leave_requests;
drop policy if exists leave_requests_staff_update_others on public.leave_requests;

create policy leave_requests_staff_select
on public.leave_requests
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy leave_requests_staff_insert
on public.leave_requests
for insert
to authenticated
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy leave_requests_staff_update_others
on public.leave_requests
for update
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
    and candidate_id is distinct from public.current_candidate_id()
)
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
    and candidate_id is distinct from public.current_candidate_id()
);

-- Candidate and intern self-service access is deferred.
-- Anonymous users receive no access.
revoke all privileges on table public.leave_requests from anon;

-- Authenticated staff receive only the privileges required by the existing workflow.
revoke all privileges on table public.leave_requests from authenticated;
grant select, insert, update on table public.leave_requests to authenticated;

-- Service-role access remains unchanged.
-- Other operational tables will be secured separately.
