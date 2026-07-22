-- This is the first controlled operational-table RLS migration.
-- Only active authenticated users with approved staff roles can read or change offer-letter records.
alter table public.hr_offer_letters enable row level security;

drop policy if exists hr_offer_letters_staff_select on public.hr_offer_letters;
drop policy if exists hr_offer_letters_staff_insert on public.hr_offer_letters;
drop policy if exists hr_offer_letters_staff_update on public.hr_offer_letters;

create policy hr_offer_letters_staff_select
on public.hr_offer_letters
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy hr_offer_letters_staff_insert
on public.hr_offer_letters
for insert
to authenticated
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy hr_offer_letters_staff_update
on public.hr_offer_letters
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

-- Anonymous users receive no access.
revoke all privileges on table public.hr_offer_letters from anon;

-- Authenticated staff receive only the operational privileges required by the frontend.
revoke all privileges on table public.hr_offer_letters from authenticated;
grant select, insert, update on table public.hr_offer_letters to authenticated;

-- Service-role access remains unchanged.
-- Other lifecycle tables will be secured separately.
