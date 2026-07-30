begin;

-- The security-invoker view needs staff-scoped base-table visibility for portal status.
drop policy if exists candidate_user_accounts_staff_select
on public.candidate_user_accounts;

create policy candidate_user_accounts_staff_select
on public.candidate_user_accounts
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array[
    'HR_SITE_CONNECT',
    'HR_SITE_CONNECT_LEAD',
    'HR_LEAD',
    'ADMIN'
    ]::text[]
    )
);

create or replace view public.active_interns_view
with (security_invoker = true)
as
select
    c.candidate_id,
    c.full_name,
    c.email,
    c.phone,
    c.applied_role,
    l.lifecycle_status,
    l.mid,
    o.offer_letter_number,
    o.sent_at as offer_letter_sent_at,
    s.signed_offer_status,
    s.signed_offer_submitted_at,
    s.verified_at,
    cua.account_status as portal_account_status,
    cua.user_id as portal_user_id
from public.master_candidates c
join public.hr_lifecycle l
    on l.candidate_id = c.candidate_id
left join public.hr_offer_letters o
    on o.candidate_id = c.candidate_id
left join public.signed_offer_verifications s
    on s.candidate_id = c.candidate_id
left join public.candidate_user_accounts cua
    on cua.candidate_id = c.candidate_id
where l.lifecycle_status = 'ACTIVE'
   or o.offer_status = 'OFFER_LETTER_SENT';

-- Preserve the hardened read-only view privilege boundary.
revoke all privileges on public.active_interns_view from public;
revoke all privileges on public.active_interns_view from anon;
revoke all privileges on public.active_interns_view from authenticated;
grant select on public.active_interns_view to authenticated;

commit;
