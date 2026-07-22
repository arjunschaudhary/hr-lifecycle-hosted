-- These views use caller permissions and future base-table RLS through security_invoker.
alter view public.hr_dashboard_view set (security_invoker = true);
alter view public.probation_review_view set (security_invoker = true);
alter view public.offer_letter_process_view set (security_invoker = true);
alter view public.active_interns_view set (security_invoker = true);
alter view public.signed_offer_verification_view set (security_invoker = true);
alter view public.candidate_detail_view set (security_invoker = true);
alter view public.activity_log_view set (security_invoker = true);
alter view public.leave_requests_view set (security_invoker = true);
alter view public.leave_balance_view set (security_invoker = true);

-- Anonymous users receive no view access.
revoke all privileges on public.hr_dashboard_view from anon;
revoke all privileges on public.probation_review_view from anon;
revoke all privileges on public.offer_letter_process_view from anon;
revoke all privileges on public.active_interns_view from anon;
revoke all privileges on public.signed_offer_verification_view from anon;
revoke all privileges on public.candidate_detail_view from anon;
revoke all privileges on public.activity_log_view from anon;
revoke all privileges on public.leave_requests_view from anon;
revoke all privileges on public.leave_balance_view from anon;

-- Authenticated users receive read-only view access.
revoke all privileges on public.hr_dashboard_view from authenticated;
revoke all privileges on public.probation_review_view from authenticated;
revoke all privileges on public.offer_letter_process_view from authenticated;
revoke all privileges on public.active_interns_view from authenticated;
revoke all privileges on public.signed_offer_verification_view from authenticated;
revoke all privileges on public.candidate_detail_view from authenticated;
revoke all privileges on public.activity_log_view from authenticated;
revoke all privileges on public.leave_requests_view from authenticated;
revoke all privileges on public.leave_balance_view from authenticated;

grant select on public.hr_dashboard_view to authenticated;
grant select on public.probation_review_view to authenticated;
grant select on public.offer_letter_process_view to authenticated;
grant select on public.active_interns_view to authenticated;
grant select on public.signed_offer_verification_view to authenticated;
grant select on public.candidate_detail_view to authenticated;
grant select on public.activity_log_view to authenticated;
grant select on public.leave_requests_view to authenticated;
grant select on public.leave_balance_view to authenticated;

-- Base-table RLS will be introduced separately.
-- Service-role access remains unchanged.
