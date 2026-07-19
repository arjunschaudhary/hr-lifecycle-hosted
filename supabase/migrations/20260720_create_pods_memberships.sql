create extension if not exists pgcrypto;

create table if not exists public.pods (
    id uuid primary key default gen_random_uuid(),
    pod_code text not null,
    pod_name text not null,
    description text null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint pods_pod_code_unique unique (pod_code),
    constraint pods_pod_code_uppercase_check check (pod_code = upper(pod_code)),
    constraint pods_pod_code_not_empty_check check (btrim(pod_code) <> ''),
    constraint pods_pod_name_not_empty_check check (btrim(pod_name) <> '')
);

create table if not exists public.pod_memberships (
    id uuid primary key default gen_random_uuid(),
    pod_id uuid not null,
    candidate_id uuid null,
    user_id uuid null,
    membership_type text not null,
    effective_from date not null default current_date,
    effective_to date null,
    is_active boolean not null default true,
    assigned_by uuid null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint pod_memberships_pod_id_fk foreign key (pod_id) references public.pods(id) on delete restrict,
    constraint pod_memberships_candidate_id_fk foreign key (candidate_id) references public.master_candidates(candidate_id) on delete restrict,
    constraint pod_memberships_user_id_fk foreign key (user_id) references public.users(id) on delete restrict,
    constraint pod_memberships_assigned_by_fk foreign key (assigned_by) references public.users(id) on delete set null,
    constraint pod_memberships_type_check check (
        membership_type in (
            'CANDIDATE',
            'POD_LEAD',
            'TECH_LEAD',
            'TEAM_LEAD',
            'HR_SITE_CONNECT'
        )
    ),
    constraint pod_memberships_exactly_one_identity_check check (
        (candidate_id is not null and user_id is null)
        or (candidate_id is null and user_id is not null)
    ),
    constraint pod_memberships_identity_matches_type_check check (
        (
            candidate_id is not null
            and user_id is null
            and membership_type = 'CANDIDATE'
        )
        or (
            candidate_id is null
            and user_id is not null
            and membership_type in (
                'POD_LEAD',
                'TECH_LEAD',
                'TEAM_LEAD',
                'HR_SITE_CONNECT'
            )
        )
    ),
    constraint pod_memberships_active_effective_to_check check (
        (is_active = true and effective_to is null)
        or (is_active = false and effective_to is not null)
    ),
    constraint pod_memberships_effective_date_order_check check (
        effective_to is null or effective_to >= effective_from
    )
);

comment on table public.pods is
    'Pods group candidates and reviewers for HR PsyConnect performance workflows. Pod records should be deactivated instead of deleted so historical assignments are preserved. No permission policies are included yet.';

comment on table public.pod_memberships is
    'A pod may have multiple active leads, and a user may be assigned to more than one pod. A candidate may have only one active pod assignment. Pod, candidate, and reviewer records should be deactivated instead of deleted so previous assignments remain preserved using effective_from, effective_to, and is_active. No permission policies are included yet.';

alter table public.pods enable row level security;
alter table public.pod_memberships enable row level security;

create index if not exists idx_pod_memberships_pod_id
    on public.pod_memberships (pod_id);

create index if not exists idx_pod_memberships_candidate_id
    on public.pod_memberships (candidate_id);

create index if not exists idx_pod_memberships_user_id
    on public.pod_memberships (user_id);

create index if not exists idx_pod_memberships_membership_type
    on public.pod_memberships (membership_type);

create index if not exists idx_pod_memberships_effective_from
    on public.pod_memberships (effective_from);

create index if not exists idx_pod_memberships_active_candidates
    on public.pod_memberships (pod_id, candidate_id)
    where is_active = true
      and membership_type = 'CANDIDATE'
      and candidate_id is not null;

create unique index if not exists uq_pod_memberships_active_candidate
    on public.pod_memberships (candidate_id)
    where is_active = true
      and membership_type = 'CANDIDATE'
      and candidate_id is not null;

create unique index if not exists uq_pod_memberships_active_reviewer
    on public.pod_memberships (pod_id, user_id, membership_type)
    where is_active = true
      and user_id is not null;
