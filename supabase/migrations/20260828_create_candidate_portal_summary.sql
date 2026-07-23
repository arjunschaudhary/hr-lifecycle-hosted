create or replace function public.get_current_candidate_portal_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_candidate_id uuid;
    v_candidate public.master_candidates%rowtype;
    v_lifecycle public.hr_lifecycle%rowtype;
    v_leave_balance public.leave_balances%rowtype;
    v_signed_offer public.signed_offer_verifications%rowtype;
    v_has_lifecycle boolean := false;
    v_has_leave_balance boolean := false;
    v_has_signed_offer boolean := false;
    v_can_submit boolean := false;
begin
    if not public.current_user_is_active()
       or not public.current_user_has_role('CANDIDATE') then
        raise insufficient_privilege
            using message = 'Candidate portal access is not available.';
    end if;

    v_candidate_id := public.current_candidate_id();

    if v_candidate_id is null then
        raise insufficient_privilege
            using message = 'Candidate portal access is not available.';
    end if;

    select c.*
    into v_candidate
    from public.master_candidates c
    where c.candidate_id = v_candidate_id;

    if not found then
        raise insufficient_privilege
            using message = 'Candidate portal record is not available.';
    end if;

    begin
        select l.*
        into strict v_lifecycle
        from public.hr_lifecycle l
        where l.candidate_id = v_candidate_id;

        v_has_lifecycle := true;
    exception
        when no_data_found then
            v_has_lifecycle := false;
        when too_many_rows then
            raise exception using
                errcode = 'P0001',
                message = 'Candidate has multiple lifecycle records.';
    end;

    begin
        select lb.*
        into strict v_leave_balance
        from public.leave_balances lb
        where lb.candidate_id = v_candidate_id;

        v_has_leave_balance := true;
    exception
        when no_data_found then
            v_has_leave_balance := false;
    end;

    select sov.*
    into v_signed_offer
    from public.signed_offer_verifications sov
    where sov.candidate_id = v_candidate_id
    order by sov.updated_at desc nulls last,
             sov.created_at desc nulls last,
             sov.verification_id desc
    limit 1;
    v_has_signed_offer := found;

    v_can_submit := coalesce(
        v_has_lifecycle
        and v_lifecycle.lifecycle_status = 'ACTIVE'
        and not exists (
            select 1
            from public.signed_offer_verifications submitted_offer
            where submitted_offer.candidate_id = v_candidate_id
              and (
                  submitted_offer.signed_offer_submitted_at is not null
                  or submitted_offer.signed_offer_status in (
                      'SIGNED_OFFER_SUBMITTED',
                      'SIGNED_OFFER_VERIFIED',
                      'MISMATCH_REVIEW'
                  )
              )
        ),
        false
    );

    return jsonb_build_object(
        'profile', jsonb_build_object(
            'candidateId', v_candidate.candidate_id,
            'fullName', v_candidate.full_name,
            'email', v_candidate.email,
            'phone', v_candidate.phone,
            'alternatePhone', v_candidate.alternate_phone,
            'address', v_candidate.address,
            'city', v_candidate.city,
            'state', v_candidate.state,
            'appliedRole', v_candidate.applied_role,
            'roleCode', v_candidate.role_code,
            'department', v_candidate.department,
            'qualification', v_candidate.qualification,
            'collegeName', v_candidate.college_name,
            'availabilityStatus', v_candidate.availability_status,
            'mid', case
                when v_has_lifecycle then v_lifecycle.mid
                else null
            end
        ),
        'internship', jsonb_build_object(
            'lifecycleStatus', case
                when v_has_lifecycle then v_lifecycle.lifecycle_status
                else null
            end,
            'startDate', case
                when v_has_lifecycle then v_lifecycle.probation_start_date
                else null
            end,
            'currentEndDate', case
                when v_has_lifecycle then v_lifecycle.current_end_date
                else null
            end,
            'internshipDurationMonths', case
                when v_has_lifecycle then v_lifecycle.internship_duration_months
                else null
            end
        ),
        'leave', jsonb_build_object(
            'available', v_has_leave_balance,
            'allocatedLeaveDays', case
                when v_has_leave_balance then v_leave_balance.allocated_leave_days
                else null
            end,
            'approvedLeaveDays', case
                when v_has_leave_balance then v_leave_balance.approved_leave_days
                else null
            end,
            'remainingLeaveDays', case
                when v_has_leave_balance then v_leave_balance.remaining_leave_days
                else null
            end,
            'extraLeaveDays', case
                when v_has_leave_balance then v_leave_balance.extra_leave_days
                else null
            end
        ),
        'signedOffer', jsonb_build_object(
            'status', case
                when v_has_signed_offer then v_signed_offer.signed_offer_status
                else null
            end,
            'submittedAt', case
                when v_has_signed_offer then v_signed_offer.signed_offer_submitted_at
                else null
            end,
            'verifiedAt', case
                when v_has_signed_offer then v_signed_offer.verified_at
                else null
            end,
            'canSubmit', v_can_submit
        )
    );
end;
$function$;

comment on function public.get_current_candidate_portal_summary() is
    'Returns only the safe portal summary for the current authenticated candidate. The candidate is resolved through current_candidate_id() and no other candidate data is exposed.';

revoke execute on function public.get_current_candidate_portal_summary() from public;
revoke execute on function public.get_current_candidate_portal_summary() from anon;
grant execute on function public.get_current_candidate_portal_summary() to authenticated;
grant execute on function public.get_current_candidate_portal_summary() to service_role;
