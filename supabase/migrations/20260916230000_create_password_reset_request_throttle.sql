begin;

-- Public password-reset requests are throttled by an HMAC key produced only
-- inside the Edge Function. Raw email addresses are never stored here.
create table public.password_reset_request_throttles (
    request_key text primary key,
    first_requested_at timestamptz not null default pg_catalog.clock_timestamp(),
    last_requested_at timestamptz not null default pg_catalog.clock_timestamp(),
    constraint password_reset_request_throttles_key_check check (
        request_key ~ '^[0-9a-f]{64}$'
    )
);

comment on table public.password_reset_request_throttles is
    'Stores only HMAC-derived password-reset request keys for short server-side resend throttling; it never stores raw email addresses.';

alter table public.password_reset_request_throttles enable row level security;

revoke all privileges on table public.password_reset_request_throttles
from public, anon, authenticated;
grant select, insert, update, delete
on table public.password_reset_request_throttles
to service_role;

create index password_reset_request_throttles_last_requested_idx
on public.password_reset_request_throttles (last_requested_at);

create or replace function public.claim_password_reset_request_slot(
    p_request_key text,
    p_window_seconds integer default 300
)
returns boolean
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
    v_now timestamptz := pg_catalog.clock_timestamp();
    v_last_requested_at timestamptz;
begin
    if p_request_key is null
       or p_request_key !~ '^[0-9a-f]{64}$' then
        raise exception using
            errcode = '22023',
            message = 'Password reset request key is invalid.';
    end if;

    if p_window_seconds is null
       or p_window_seconds < 60
       or p_window_seconds > 3600 then
        raise exception using
            errcode = '22023',
            message = 'Password reset request window is invalid.';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'password-reset-request:' || p_request_key,
            0
        )
    );

    -- Bound storage without retaining long-lived request history.
    delete from public.password_reset_request_throttles throttle
    where throttle.last_requested_at < v_now - interval '30 days';

    select throttle.last_requested_at
    into v_last_requested_at
    from public.password_reset_request_throttles throttle
    where throttle.request_key = p_request_key
    for update;

    if v_last_requested_at is not null
       and v_last_requested_at >=
           v_now - pg_catalog.make_interval(secs => p_window_seconds) then
        return false;
    end if;

    insert into public.password_reset_request_throttles (
        request_key,
        first_requested_at,
        last_requested_at
    ) values (
        p_request_key,
        v_now,
        v_now
    )
    on conflict (request_key) do update
    set last_requested_at = excluded.last_requested_at;

    return true;
end;
$function$;

comment on function public.claim_password_reset_request_slot(text, integer) is
    'Service-role-only atomic throttle claim for the public password-reset Edge Function. Returns false during the active resend window without revealing account existence.';

revoke all privileges on function
    public.claim_password_reset_request_slot(text, integer)
from public, anon, authenticated;
grant execute on function
    public.claim_password_reset_request_slot(text, integer)
to service_role;

commit;
