create or replace function public.generate_performance_cycles_for_month(p_month date)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
    v_month_start date;
    v_next_month_start date;
    v_month_end date;
    v_inserted_count integer;
    v_cycle_code_prefix text;
begin
    if p_month is null then
        raise exception 'p_month must not be null.'
            using errcode = '22004';
    end if;

    v_month_start := date_trunc('month', p_month)::date;
    v_next_month_start := (v_month_start + interval '1 month')::date;
    v_month_end := v_next_month_start - 1;
    v_cycle_code_prefix := 'PERF-' || to_char(v_month_start, 'YYYY-MM');

    insert into public.performance_cycles (
        cycle_code,
        cycle_number,
        start_date,
        end_date,
        review_open_date,
        lock_date,
        cycle_status
    )
    values
        (
            v_cycle_code_prefix || '-C1',
            1,
            v_month_start,
            v_month_start + 9,
            v_month_start + 10,
            v_month_start + 20,
            'DRAFT'
        ),
        (
            v_cycle_code_prefix || '-C2',
            2,
            v_month_start + 10,
            v_month_start + 19,
            v_month_start + 20,
            v_next_month_start,
            'DRAFT'
        ),
        (
            v_cycle_code_prefix || '-C3',
            3,
            v_month_start + 20,
            v_month_end,
            v_next_month_start,
            v_next_month_start + 10,
            'DRAFT'
        )
    on conflict (start_date, end_date) do nothing;

    get diagnostics v_inserted_count = row_count;

    return v_inserted_count;
end;
$function$;

comment on function public.generate_performance_cycles_for_month(date) is
    'Creates the three monthly company performance periods. It does not assign candidates or activate cycles. It is idempotent, and candidate-specific partial periods will be generated separately.';

revoke execute on function public.generate_performance_cycles_for_month(date) from public;
revoke execute on function public.generate_performance_cycles_for_month(date) from anon;
revoke execute on function public.generate_performance_cycles_for_month(date) from authenticated;
grant execute on function public.generate_performance_cycles_for_month(date) to service_role;
