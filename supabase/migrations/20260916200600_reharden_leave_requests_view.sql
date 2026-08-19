begin;

-- The view was hardened in 20260820_harden_lifecycle_view_security.sql,
-- but 20260916194600_leave_application_improvements.sql later recreated it.
-- Re-apply caller-permission semantics and least-privilege grants here so the
-- final migration state remains secure.
alter view public.leave_requests_view set (security_invoker = true);

revoke all privileges on public.leave_requests_view from public;
revoke all privileges on public.leave_requests_view from anon;
revoke all privileges on public.leave_requests_view from authenticated;

grant select on public.leave_requests_view to authenticated;

commit;
