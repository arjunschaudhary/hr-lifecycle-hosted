-- Only active authenticated users with approved staff roles can read or change leave-balance records.
-- SELECT, INSERT, and UPDATE are required for existing reads, writes, and upserts.
alter table public.leave_balances enable row level security;

drop policy if exists leave_balances_staff_select on public.leave_balances;
drop policy if exists leave_balances_staff_insert on public.leave_balances;
drop policy if exists leave_balances_staff_update on public.leave_balances;

create policy leave_balances_staff_select
on public.leave_balances
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy leave_balances_staff_insert
on public.leave_balances
for insert
to authenticated
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy leave_balances_staff_update
on public.leave_balances
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

-- Candidate and intern self-service access is deferred.
-- Anonymous users receive no access.
revoke all privileges on table public.leave_balances from anon;

-- Authenticated staff receive only the privileges required for reads, writes, and upserts.
revoke all privileges on table public.leave_balances from authenticated;
grant select, insert, update on table public.leave_balances to authenticated;

-- Service-role access remains unchanged.
-- Other operational tables will be secured separately.
