-- Active approved staff roles can read signed-offer verification records.
-- Only PSYConnect verification roles, Founders Office, and Admin can insert or update records.
alter table public.signed_offer_verifications enable row level security;

drop policy if exists signed_offer_verifications_staff_select on public.signed_offer_verifications;
drop policy if exists signed_offer_verifications_verifier_insert on public.signed_offer_verifications;
drop policy if exists signed_offer_verifications_verifier_update on public.signed_offer_verifications;

create policy signed_offer_verifications_staff_select
on public.signed_offer_verifications
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy signed_offer_verifications_verifier_insert
on public.signed_offer_verifications
for insert
to authenticated
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy signed_offer_verifications_verifier_update
on public.signed_offer_verifications
for update
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
)
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

-- Candidate and intern self-submission access is deferred.
-- Anonymous users receive no access.
revoke all privileges on table public.signed_offer_verifications from anon;

-- RLS policies determine which authenticated roles can perform each operation.
revoke all privileges on table public.signed_offer_verifications from authenticated;
grant select, insert, update on table public.signed_offer_verifications to authenticated;

-- Service-role access remains unchanged.
-- Other operational tables will be secured separately.
