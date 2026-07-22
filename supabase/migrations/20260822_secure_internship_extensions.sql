-- Only active authenticated users with approved staff roles can read or create internship-extension records.
alter table public.internship_extensions enable row level security;

drop policy if exists internship_extensions_staff_select on public.internship_extensions;
drop policy if exists internship_extensions_staff_insert on public.internship_extensions;

create policy internship_extensions_staff_select
on public.internship_extensions
for select
to authenticated
using (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

create policy internship_extensions_staff_insert
on public.internship_extensions
for insert
to authenticated
with check (
    public.current_user_is_active()
    and public.current_user_has_any_role(
        array['HR_SITE_CONNECT', 'HR_SITE_CONNECT_LEAD', 'HR_EXECUTIVE', 'HR_EXECUTIVE_LEAD', 'HR_LEAD', 'FOUNDERS_OFFICE', 'ADMIN']::text[]
    )
);

-- Anonymous users receive no access.
revoke all privileges on table public.internship_extensions from anon;

-- The current application does not require update or delete access.
revoke all privileges on table public.internship_extensions from authenticated;
grant select, insert on table public.internship_extensions to authenticated;

-- Service-role access remains unchanged.
-- Other operational tables will be secured separately.
