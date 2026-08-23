begin;

update public.hr_lifecycle
set probation_extension_count = 0
where probation_extension_count is null;

alter table public.hr_lifecycle
    alter column probation_extension_count set default 0,
    alter column probation_extension_count set not null;

commit;
