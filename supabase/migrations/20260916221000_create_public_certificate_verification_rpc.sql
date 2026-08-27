begin;

create or replace function public.get_certificate_verification(
    p_certificate_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_result jsonb;
    v_clean_id text;
begin
    if p_certificate_id is null then
        return jsonb_build_object(
            'valid', false,
            'reason', 'Certificate ID is required.'
        );
    end if;

    v_clean_id := upper(btrim(p_certificate_id));

    select jsonb_build_object(
        'valid', true,
        'certificateId', ed.certificate_id,
        'candidateName', mc.full_name,
        'appliedRole', mc.applied_role,
        'documentVariant', ed.document_variant,
        'startDate', hl.probation_start_date,
        'endDate', hl.current_end_date,
        'issuedAt', ed.generated_at,
        'revoked', (ed.revoked_at is not null)
    ) into v_result
    from public.exit_documents ed
    join public.exit_cases ec on ec.exit_case_id = ed.exit_case_id
    join public.master_candidates mc on mc.candidate_id = ec.candidate_id
    left join public.hr_lifecycle hl on hl.lifecycle_id = ec.lifecycle_id
    where upper(ed.certificate_id) = v_clean_id
      and ed.revoked_at is null;

    if v_result is null then
        return jsonb_build_object(
            'valid', false,
            'reason', 'Certificate not found or invalid.'
        );
    end if;

    return v_result;
end;
$function$;

comment on function public.get_certificate_verification(text) is
    'Public unauthenticated verification endpoint for issued certificates by Certificate ID. Returns non-sensitive details only.';

grant execute on function public.get_certificate_verification(text) to anon;
grant execute on function public.get_certificate_verification(text) to authenticated;
grant execute on function public.get_certificate_verification(text) to service_role;

commit;
