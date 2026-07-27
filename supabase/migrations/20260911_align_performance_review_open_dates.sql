begin;

alter table public.performance_cycles
drop constraint performance_cycles_review_open_date_check;

update public.performance_cycles
set review_open_date = case
    when extract(dow from end_date) = 0
        then end_date - 1
    else end_date
end;

alter table public.performance_cycles
add constraint performance_cycles_review_open_date_check
check (
    review_open_date = case
        when extract(dow from end_date) = 0
            then end_date - 1
        else end_date
    end
);

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
    v_cycle_1_end date;
    v_cycle_2_end date;
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
    v_cycle_1_end := v_month_start + 9;
    v_cycle_2_end := v_month_start + 19;
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
            v_cycle_1_end,
            case
                when extract(dow from v_cycle_1_end) = 0
                    then v_cycle_1_end - 1
                else v_cycle_1_end
            end,
            v_month_start + 20,
            'DRAFT'
        ),
        (
            v_cycle_code_prefix || '-C2',
            2,
            v_month_start + 10,
            v_cycle_2_end,
            case
                when extract(dow from v_cycle_2_end) = 0
                    then v_cycle_2_end - 1
                else v_cycle_2_end
            end,
            v_next_month_start,
            'DRAFT'
        ),
        (
            v_cycle_code_prefix || '-C3',
            3,
            v_month_start + 20,
            v_month_end,
            case
                when extract(dow from v_month_end) = 0
                    then v_month_end - 1
                else v_month_end
            end,
            v_next_month_start + 10,
            'DRAFT'
        )
    on conflict (start_date, end_date) do nothing;

    get diagnostics v_inserted_count = row_count;

    return v_inserted_count;
end;
$function$;

comment on function public.generate_performance_cycles_for_month(date) is
    'Creates the three monthly company performance periods. Reviews open on each cycle end date, or one day earlier when the cycle ends on Sunday. It does not assign candidates, activate cycles, finalize results, or lock results. It is idempotent, and candidate-specific partial periods are generated separately.';

revoke execute on function public.generate_performance_cycles_for_month(date) from public;
revoke execute on function public.generate_performance_cycles_for_month(date) from anon;
revoke execute on function public.generate_performance_cycles_for_month(date) from authenticated;
grant execute on function public.generate_performance_cycles_for_month(date) to service_role;

commit;
