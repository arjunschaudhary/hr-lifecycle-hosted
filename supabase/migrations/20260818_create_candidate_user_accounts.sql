create table public.candidate_user_accounts (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null,
    user_id uuid not null,
    account_status text not null default 'ACTIVE',
    activated_at timestamptz not null default now(),
    deactivated_at timestamptz null,
    linked_by uuid null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint candidate_user_accounts_candidate_id_fk
        foreign key (candidate_id)
        references public.master_candidates(candidate_id)
        on delete restrict,
    constraint candidate_user_accounts_user_id_fk
        foreign key (user_id)
        references public.users(id)
        on delete restrict,
    constraint candidate_user_accounts_linked_by_fk
        foreign key (linked_by)
        references public.users(id)
        on delete set null,
    constraint candidate_user_accounts_candidate_id_unique
        unique (candidate_id),
    constraint candidate_user_accounts_user_id_unique
        unique (user_id),
    constraint candidate_user_accounts_status_check
        check (account_status in ('ACTIVE', 'INACTIVE')),
    constraint candidate_user_accounts_status_deactivated_at_check
        check (
            (account_status = 'ACTIVE' and deactivated_at is null)
            or (
                account_status = 'INACTIVE'
                and deactivated_at is not null
            )
        ),
    constraint candidate_user_accounts_deactivation_date_order_check
        check (
            deactivated_at is null
            or deactivated_at >= activated_at
        )
);

comment on table public.candidate_user_accounts is
    'Maps one authenticated application user to one candidate or intern record. Email matching is not an authorization mechanism, and inactive links are preserved for audit history.';

comment on column public.candidate_user_accounts.candidate_id is
    'The candidate or intern record in the one-to-one account mapping; authorization must not be inferred by matching email addresses.';

comment on column public.candidate_user_accounts.user_id is
    'The authenticated application user linked one-to-one with the candidate or intern record.';

comment on column public.candidate_user_accounts.account_status is
    'Indicates whether the account link is ACTIVE or preserved as INACTIVE for audit history.';

comment on column public.candidate_user_accounts.linked_by is
    'Identifies the staff application user who created the candidate-account link when available.';

-- No shared updated_at trigger function exists, so updated_at retains its default only.
alter table public.candidate_user_accounts enable row level security;

revoke all privileges on table public.candidate_user_accounts from anon;
revoke all privileges on table public.candidate_user_accounts from authenticated;
grant select on table public.candidate_user_accounts to authenticated;
grant all privileges on table public.candidate_user_accounts to service_role;
