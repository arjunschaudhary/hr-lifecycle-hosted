-- Migration: 20260916195300_create_pod_on_leave_today_rpc.sql
--
-- Creates an RPC that returns candidates from the current candidate's own pod
-- who have an APPROVED leave request that covers today's date (inclusive).
--
-- Security:
--   - The current candidate's identity is resolved via current_candidate_id()
--     (which uses current_app_user_id() → candidate_user_accounts).
--   - The candidate's pod is resolved server-side from pod_memberships.
--     The frontend never supplies a pod_id.
--   - Only APPROVED leave requests where today falls inclusively between
--     start_date and end_date are returned.
--   - The current candidate is excluded from their own results.
--   - Only candidates in the same pod (active membership, CANDIDATE type) are included.
--   - No data from candidates in other pods is exposed.

begin;

create or replace function public.get_pod_on_leave_today()
returns table (
    candidate_id      uuid,
    full_name         text,
    start_date        date,
    end_date          date,
    leave_type        text,
    requested_leave_days integer
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_pod_id       uuid;
    v_today        date;
begin
    -- Only active authenticated candidates may call this.
    if not coalesce(public.current_user_is_active(), false)
       or not coalesce(public.current_user_has_role('CANDIDATE'), false) then
        raise insufficient_privilege
            using message = 'Candidate portal access is not available.';
    end if;

    -- Resolve the current candidate's identity server-side.
    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate portal access is not available.';
    end if;

    -- Resolve today's date in Asia/Kolkata timezone (consistent with the rest of the app).
    v_today := (timezone('Asia/Kolkata', now()))::date;

    -- Resolve the current candidate's active pod membership server-side.
    -- A candidate may have at most one active pod membership (unique index enforces this).
    select pm.pod_id
    into   v_pod_id
    from   public.pod_memberships pm
    where  pm.candidate_id    = v_candidate_id
      and  pm.is_active       = true
      and  pm.membership_type = 'CANDIDATE'
    limit 1;

    -- If the candidate is not in any pod, return an empty result set gracefully.
    if v_pod_id is null then
        return;
    end if;

    -- Return pod-mates who are on approved leave today.
    return query
    select
        mc.candidate_id,
        mc.full_name::text,
        lr.start_date,
        lr.end_date,
        lr.leave_type::text,
        lr.requested_leave_days
    from   public.pod_memberships pm
    join   public.master_candidates mc
        on mc.candidate_id = pm.candidate_id
    join   public.leave_requests lr
        on lr.candidate_id = pm.candidate_id
    where  pm.pod_id        = v_pod_id
      and  pm.is_active     = true
      and  pm.membership_type = 'CANDIDATE'
      and  pm.candidate_id  is not null
      -- Exclude the requesting candidate themselves.
      and  pm.candidate_id  <> v_candidate_id
      -- Only approved leave.
      and  lr.leave_status  = 'APPROVED'
      -- Today falls inclusively within the leave period.
      and  lr.start_date    <= v_today
      and  lr.end_date      >= v_today
    order by mc.full_name asc nulls last,
             lr.start_date asc;
end;
$function$;

comment on function public.get_pod_on_leave_today() is
    'Returns candidates from the current authenticated candidate''s own pod who have an approved leave request covering today. The current candidate''s pod and identity are resolved server-side via current_candidate_id() and pod_memberships. No pod_id is accepted from the caller. Only APPROVED leave that spans today (inclusive) is returned. The requesting candidate is excluded from the results.';

revoke execute on function public.get_pod_on_leave_today() from public;
revoke execute on function public.get_pod_on_leave_today() from anon;
grant execute on function public.get_pod_on_leave_today() to authenticated;
grant execute on function public.get_pod_on_leave_today() to service_role;

commit;
