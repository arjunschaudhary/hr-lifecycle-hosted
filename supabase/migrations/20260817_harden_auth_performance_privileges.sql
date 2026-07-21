-- Remove broad default table grants before introducing the HR PsyConnect RLS policies.
-- anon receives no direct access, while authenticated receives read-only table access.
-- RLS policies will separately determine which rows authenticated users can see.
-- No authenticated write access is granted, and service_role access remains unchanged.

revoke all privileges on table
    public.users,
    public.roles,
    public.user_roles,
    public.pods,
    public.pod_memberships,
    public.performance_cycles,
    public.candidate_performance_cycles,
    public.daily_performance_entries,
    public.performance_reviews,
    public.exceptional_contributions
from anon;

revoke all privileges on table
    public.users,
    public.roles,
    public.user_roles,
    public.pods,
    public.pod_memberships,
    public.performance_cycles,
    public.candidate_performance_cycles,
    public.daily_performance_entries,
    public.performance_reviews,
    public.exceptional_contributions
from authenticated;

grant select on table
    public.users,
    public.roles,
    public.user_roles,
    public.pods,
    public.pod_memberships,
    public.performance_cycles,
    public.candidate_performance_cycles,
    public.daily_performance_entries,
    public.performance_reviews,
    public.exceptional_contributions
to authenticated;
