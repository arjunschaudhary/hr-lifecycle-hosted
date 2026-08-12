-- Migration: 20260916195400_fix_portal_summary_leave_entitlement.sql
--
-- Problem:
--   get_current_candidate_portal_summary() returns leave.available = false
--   and all leave fields as null when no leave_balances row exists for the
--   candidate. This happens for candidates who have never applied for leave,
--   because the leave_balances row is created lazily on first leave submission.
--
-- Fix:
--   When no leave_balances row exists, compute the candidate's entitlement
--   from their lifecycle record using the same policy already in
--   submit_current_candidate_leave_request():
--       3-month internship → 9 days  + (extension_months * 3)
--       4-month internship → 15 days + (extension_months * 3)
--   If the entitlement can be derived, expose it as a computed balance
--   (allocated = entitlement, approved = 0, remaining = entitlement, extra = 0)
--   and set leave.available = true so the portal always shows real values.
--   If the internship duration is not 3 or 4 months (e.g., no lifecycle or
--   6/12-month duration), leave.available remains false — the portal will show
--   the existing "not yet available" message.
--
-- Nothing else changes: existing leave_balances rows, entitlement rules,
-- approval/rejection logic, or extra-leave rules are untouched.

begin;

create or replace function public.get_current_candidate_portal_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
    v_candidate_id           uuid;
    v_candidate              public.master_candidates%rowtype;
    v_lifecycle              public.hr_lifecycle%rowtype;
    v_leave_balance          public.leave_balances%rowtype;
    v_signed_offer           public.signed_offer_verifications%rowtype;
    v_has_lifecycle          boolean := false;
    v_has_leave_balance      boolean := false;
    v_has_signed_offer       boolean := false;
    v_can_submit             boolean := false;
    v_can_resubmit           boolean := false;

    -- Leave display values (populated from the balance row OR computed
    -- from lifecycle data when no balance row exists yet).
    v_leave_available        boolean := false;
    v_allocated_leave_days   integer;
    v_approved_leave_days    integer;
    v_remaining_leave_days   integer;
    v_extra_leave_days       integer;

    -- Intermediate values for entitlement computation.
    v_extension_months       integer := 0;
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

    -- ─────────────────────────────────────────────────────────────────────────
    -- Populate leave display values.
    --
    -- Priority 1 — a real leave_balances row exists: use it directly.
    -- Priority 2 — no balance row yet: compute from lifecycle (same policy as
    --              submit_current_candidate_leave_request).
    -- Priority 3 — neither applies: leave.available stays false.
    -- ─────────────────────────────────────────────────────────────────────────
    if v_has_leave_balance then
        -- Real balance row — unchanged from original behaviour.
        v_leave_available      := true;
        v_allocated_leave_days := v_leave_balance.allocated_leave_days;
        v_approved_leave_days  := v_leave_balance.approved_leave_days;
        v_remaining_leave_days := v_leave_balance.remaining_leave_days;
        v_extra_leave_days     := v_leave_balance.extra_leave_days;

    elsif v_has_lifecycle
          and v_lifecycle.internship_duration_months in (3, 4) then
        -- No balance row yet, but we can derive the entitlement from the
        -- lifecycle record.  Use the same extension-months lookup that
        -- submit_current_candidate_leave_request already uses.
        select coalesce(sum(ie.extension_value), 0)::integer
        into   v_extension_months
        from   public.internship_extensions ie
        where  ie.candidate_id  = v_candidate_id
          and  ie.extension_type = 'MONTHS'
          and  ie.is_processed   is true;

        v_allocated_leave_days := case v_lifecycle.internship_duration_months
            when 3 then 9  + (v_extension_months * 3)
            when 4 then 15 + (v_extension_months * 3)
        end;

        -- Candidate has never taken leave, so approved and extra are both 0.
        v_approved_leave_days  := 0;
        v_remaining_leave_days := v_allocated_leave_days;
        v_extra_leave_days     := 0;

        -- Mark as available so the portal renders the real values.
        v_leave_available      := true;
    end if;
    -- else: v_leave_available stays false (no lifecycle, or 6/12-month
    -- internship with no defined entitlement).

    select sov.*
    into v_signed_offer
    from public.signed_offer_verifications sov
    where sov.candidate_id = v_candidate_id
    order by sov.updated_at desc nulls last,
             sov.created_at desc nulls last,
             sov.verification_id desc
    limit 1;
    v_has_signed_offer := found;

    -- canSubmit: unchanged — only true when lifecycle is ACTIVE and no
    -- in-progress verification row exists.
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

    -- canResubmit: true only when lifecycle is MISMATCH_REVIEW and an
    -- active MISMATCH_REVIEW verification row exists.
    v_can_resubmit := coalesce(
        v_has_lifecycle
        and v_lifecycle.lifecycle_status = 'MISMATCH_REVIEW'
        and v_has_signed_offer
        and v_signed_offer.signed_offer_status = 'MISMATCH_REVIEW'
        and exists (
            select 1
            from public.candidate_signed_offer_files f
            where f.candidate_id = v_candidate_id
              and f.file_status  = 'MISMATCH_REVIEW'
        ),
        false
    );

    return jsonb_build_object(
        'profile', jsonb_build_object(
            'candidateId',        v_candidate.candidate_id,
            'fullName',           v_candidate.full_name,
            'email',              v_candidate.email,
            'phone',              v_candidate.phone,
            'alternatePhone',     v_candidate.alternate_phone,
            'address',            v_candidate.address,
            'city',               v_candidate.city,
            'state',              v_candidate.state,
            'appliedRole',        v_candidate.applied_role,
            'roleCode',           v_candidate.role_code,
            'department',         v_candidate.department,
            'qualification',      v_candidate.qualification,
            'collegeName',        v_candidate.college_name,
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
            'available',          v_leave_available,
            'allocatedLeaveDays', v_allocated_leave_days,
            'approvedLeaveDays',  v_approved_leave_days,
            'remainingLeaveDays', v_remaining_leave_days,
            'extraLeaveDays',     v_extra_leave_days
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
            'canSubmit',   v_can_submit,
            'canResubmit', v_can_resubmit,
            -- verificationNotes only exposed when status is MISMATCH_REVIEW.
            'verificationNotes', case
                when v_has_signed_offer
                     and v_signed_offer.signed_offer_status = 'MISMATCH_REVIEW'
                then v_signed_offer.verification_notes
                else null
            end
        )
    );
end;
$function$;

comment on function public.get_current_candidate_portal_summary() is
    'Returns the safe portal summary for the current authenticated candidate. The candidate is resolved through current_candidate_id(). When no leave_balances row exists yet, leave entitlement is derived from the lifecycle record using the same 3/4-month internship policy used by submit_current_candidate_leave_request(), so the portal always shows real values instead of nulls for eligible candidates. Exposes canResubmit and verificationNotes (only for MISMATCH_REVIEW) in the signedOffer block.';

revoke execute on function public.get_current_candidate_portal_summary() from public;
revoke execute on function public.get_current_candidate_portal_summary() from anon;
grant execute on function public.get_current_candidate_portal_summary() to authenticated;
grant execute on function public.get_current_candidate_portal_summary() to service_role;

commit;
