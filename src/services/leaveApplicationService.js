import { supabase } from "./supabaseClient";
import {
  calculateAllocatedLeaveDays,
  calculateLeaveDays,
  calculateRemainingLeaveDays,
  ELIGIBLE_LEAVE_STATUSES,
} from "../utils/leaveRules";

const EXTRA_LEAVE_REASON_MIN_LENGTH = 12;

function sumExtensionMonths(extensionRows = []) {
  return extensionRows.reduce(
    (total, extension) => total + Number(extension.extension_value || 0),
    0
  );
}

function hasExtraLeaveProof(formData) {
  return (
    String(formData.supporting_document || "").trim().length > 0 ||
    String(formData.reason || "").trim().length >= EXTRA_LEAVE_REASON_MIN_LENGTH
  );
}

function assertExtraLeaveProof({
  formData,
  requestedLeaveDays,
  remainingLeaveDays,
}) {
  if (
    requestedLeaveDays > Number(remainingLeaveDays || 0) &&
    !hasExtraLeaveProof(formData)
  ) {
    throw new Error(
      "This request exceeds the remaining leave balance. Add a supporting document or a clear reason before submitting."
    );
  }
}

export function validateLeaveApplication(formData) {
  if (!formData.candidate_id) {
    throw new Error("Candidate ID is required.");
  }

  if (!formData.leave_type?.trim()) {
    throw new Error("Leave Type is required.");
  }

  if (!formData.start_date) {
    throw new Error("Start Date is required.");
  }

  if (!formData.end_date) {
    throw new Error("End Date is required.");
  }

  if (!formData.reason?.trim()) {
    throw new Error("Reason is required.");
  }

  const leaveDays = calculateLeaveDays(
    formData.start_date,
    formData.end_date
  );

  return leaveDays;
}

// ------------------------------
// Submit Leave Application
// ------------------------------
// ------------------------------
// Eligible Candidates
// ------------------------------
export async function getEligibleCandidates() {
  const { data, error } = await supabase
    .from("candidate_detail_view")
    .select(`
      candidate_id,
      full_name,
      lifecycle_status,
      mid
    `)
    .in("lifecycle_status", ELIGIBLE_LEAVE_STATUSES)
    .order("full_name");

  if (error) {
    throw error;
  }

  return data;
}

export async function submitLeaveApplication(formData) {
  const now = new Date().toISOString();
  if (!supabase) {
    throw new Error("Supabase is not configured.");
  }

  const requestedLeaveDays = validateLeaveApplication(formData);

  // Check candidate lifecycle status
  const { data: lifecycle, error: lifecycleError } =
  await supabase
    .from("hr_lifecycle")
    .select("lifecycle_status, mid, internship_duration_months")
    .eq("candidate_id", formData.candidate_id)
    .single();

  if (lifecycleError) {
    throw lifecycleError;
  }

  if (
    !ELIGIBLE_LEAVE_STATUSES.includes(
      lifecycle.lifecycle_status
    )
  ) {
    throw new Error(
      "Candidate is not eligible to apply for leave."
    );
  }

  const { data: extensionRows, error: extensionError } = await supabase
    .from("internship_extensions")
    .select("extension_value")
    .eq("candidate_id", formData.candidate_id)
    .eq("extension_type", "MONTHS")
    .eq("is_processed", true);

  if (extensionError) {
    throw extensionError;
  }

  const extensionMonths = sumExtensionMonths(extensionRows);
  const allocatedLeaveDays = calculateAllocatedLeaveDays(
    lifecycle.internship_duration_months,
    extensionMonths
  );

  const { data: overlappingLeave, error: overlapError } =
    await supabase
      .from("leave_requests")
      .select("leave_request_id")
      .eq("candidate_id", formData.candidate_id)
      .in("leave_status", ["PENDING", "APPROVED"])
      .lte("start_date", formData.end_date)
      .gte("end_date", formData.start_date)
      .limit(1)
      .maybeSingle();

  if (overlapError) {
    throw overlapError;
  }

  if (overlappingLeave) {
    throw new Error(
      "This leave request overlaps with an existing leave request."
    );
  }
// ------------------------------------
// Ensure Leave Balance Exists
// ------------------------------------
  const { data: balance, error: balanceError } = await supabase
    .from("leave_balances")
    .select("*")
    .eq("candidate_id", formData.candidate_id)
    .maybeSingle();

  if (balanceError) {
    throw balanceError;
  }

  const approvedLeaveDays = Number(balance?.approved_leave_days || 0);
  const extraLeaveDays = Number(balance?.extra_leave_days || 0);
  const remainingLeaveDays = calculateRemainingLeaveDays(
    allocatedLeaveDays,
    approvedLeaveDays
  );

  assertExtraLeaveProof({
    formData,
    requestedLeaveDays,
    remainingLeaveDays,
  });

  if (!balance) {
    const { error: createBalanceError } = await supabase
      .from("leave_balances")
      .insert({
        candidate_id: formData.candidate_id,
        mid: lifecycle.mid,
        allocated_leave_days: allocatedLeaveDays,
        approved_leave_days: 0,
        remaining_leave_days: allocatedLeaveDays,
        extra_leave_days: 0,
        created_at: now,
      });

    if (createBalanceError) {
      throw createBalanceError;
    }
  } else if (
    Number(balance.allocated_leave_days || 0) !== allocatedLeaveDays ||
    Number(balance.remaining_leave_days || 0) !== remainingLeaveDays
  ) {
    const { error: updateBalanceError } = await supabase
      .from("leave_balances")
      .update({
        allocated_leave_days: allocatedLeaveDays,
        approved_leave_days: approvedLeaveDays,
        remaining_leave_days: remainingLeaveDays,
        extra_leave_days: extraLeaveDays,
        updated_at: now,
      })
      .eq("candidate_id", formData.candidate_id);

    if (updateBalanceError) {
      throw updateBalanceError;
    }
  }
  // Insert Leave Request
  const { data, error } = await supabase
    .from("leave_requests")
    .insert({
      candidate_id: formData.candidate_id,
      mid: lifecycle.mid,
      leave_type: formData.leave_type,
      start_date: formData.start_date,
      end_date: formData.end_date,
      requested_leave_days: requestedLeaveDays,
      reason: formData.reason,
      supporting_document:
        formData.supporting_document || null,
      created_at: now,
    })
    .select()
    .single();

  if (error) {
    throw error;
  }
  const { error: logError } = await supabase
    .from("hr_activity_logs")
    .insert({
      candidate_id: formData.candidate_id,
      activity_type: "LEAVE_APPLIED",
      from_status: null,
      to_status: "PENDING",
      remarks: "Leave application submitted.",
      activity_status: "SUCCESS",
      performed_by: "HR",
      performed_at: now,
    });

  if (logError) {
    throw logError;
  }
  return data;
}
