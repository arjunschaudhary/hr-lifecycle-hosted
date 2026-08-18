begin;

alter table public.exit_cases enable row level security;
alter table public.candidate_exit_feedback enable row level security;
alter table public.hr_exit_evaluations enable row level security;
alter table public.exit_handover_items enable row level security;
alter table public.exit_clearance enable row level security;
alter table public.exit_documents enable row level security;

revoke all privileges on table public.exit_cases from public;
revoke all privileges on table public.exit_cases from anon;
revoke all privileges on table public.exit_cases from authenticated;

revoke all privileges on table public.candidate_exit_feedback from public;
revoke all privileges on table public.candidate_exit_feedback from anon;
revoke all privileges on table public.candidate_exit_feedback from authenticated;

revoke all privileges on table public.hr_exit_evaluations from public;
revoke all privileges on table public.hr_exit_evaluations from anon;
revoke all privileges on table public.hr_exit_evaluations from authenticated;

revoke all privileges on table public.exit_handover_items from public;
revoke all privileges on table public.exit_handover_items from anon;
revoke all privileges on table public.exit_handover_items from authenticated;

revoke all privileges on table public.exit_clearance from public;
revoke all privileges on table public.exit_clearance from anon;
revoke all privileges on table public.exit_clearance from authenticated;

revoke all privileges on table public.exit_documents from public;
revoke all privileges on table public.exit_documents from anon;
revoke all privileges on table public.exit_documents from authenticated;

commit;
