create extension if not exists pgcrypto;

create table if not exists public.roles (
    id uuid primary key default gen_random_uuid(),
    slug text not null,
    label text not null,
    hierarchy_level integer not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint roles_slug_unique unique (slug),
    constraint roles_slug_uppercase_check check (slug = upper(slug)),
    constraint roles_hierarchy_level_non_negative_check check (hierarchy_level >= 0),
    constraint roles_slug_not_empty_check check (btrim(slug) <> ''),
    constraint roles_label_not_empty_check check (btrim(label) <> '')
);

insert into public.roles (slug, label, hierarchy_level)
values
    ('ADMIN', 'Admin', 100),
    ('FOUNDERS_OFFICE', 'Founders Office', 90),
    ('HR_LEAD', 'HR Lead', 80),
    ('HR_EXECUTIVE_LEAD', 'HR Executive Lead', 70),
    ('HR_EXECUTIVE', 'HR Executive', 60),
    ('HR_SITE_CONNECT_LEAD', 'HR Site Connect Lead', 50),
    ('HR_SITE_CONNECT', 'HR Site Connect', 40),
    ('POD_LEAD', 'Pod Lead', 35),
    ('TECH_LEAD', 'Tech Lead', 30),
    ('TEAM_LEAD', 'Team Lead', 25),
    ('CANDIDATE', 'Candidate', 0)
on conflict (slug) do nothing;

create table if not exists public.users (
    id uuid primary key,
    name text not null,
    email text not null,
    status text not null default 'active',
    role_id uuid null,
    joined_at timestamptz null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint users_auth_user_id_fk foreign key (id) references auth.users(id) on delete cascade,
    constraint users_role_id_fk foreign key (role_id) references public.roles(id) on delete set null,
    constraint users_name_not_empty_check check (btrim(name) <> ''),
    constraint users_email_not_empty_check check (btrim(email) <> ''),
    constraint users_status_check check (status in ('active', 'on_leave', 'exited'))
);

comment on column public.users.role_id is
    'Primary role used for simple dashboard routing. Multiple roles are stored in public.user_roles.';

create table if not exists public.user_roles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    role_id uuid not null,
    is_active boolean not null default true,
    assigned_by uuid null,
    assigned_at timestamptz not null default now(),
    ended_at timestamptz null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint user_roles_user_id_fk foreign key (user_id) references public.users(id) on delete cascade,
    constraint user_roles_role_id_fk foreign key (role_id) references public.roles(id) on delete restrict,
    constraint user_roles_assigned_by_fk foreign key (assigned_by) references public.users(id) on delete set null,
    constraint user_roles_active_ended_at_check check (is_active = false or ended_at is null)
);

comment on column public.roles.hierarchy_level is
    'Used only for ordering and display. Do not treat hierarchy_level as permission enforcement.';

alter table public.roles enable row level security;
alter table public.users enable row level security;
alter table public.user_roles enable row level security;

comment on table public.roles is
    'Identity foundation roles only. Row Level Security is enabled, but policies will be introduced with the HR PsyConnect permission matrix.';

comment on table public.users is
    'Application user profiles linked to auth.users. Row Level Security is enabled, but policies will be introduced with the HR PsyConnect permission matrix.';

comment on table public.user_roles is
    'Supports multiple roles per user and preserves role assignment history. Row Level Security is enabled, but policies will be introduced with the HR PsyConnect permission matrix.';

create unique index if not exists uq_users_email_lower
    on public.users (lower(email));

create index if not exists idx_users_role_id on public.users (role_id);
create index if not exists idx_user_roles_user_id on public.user_roles (user_id);
create index if not exists idx_user_roles_role_id on public.user_roles (role_id);

create unique index if not exists uq_user_roles_active_user_role
    on public.user_roles (user_id, role_id)
    where is_active = true;
