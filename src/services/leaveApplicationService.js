import { supabase } from "./supabaseClient";


const ELIGIBLE_STATUSES = [
  "WELCOME_MAIL_SENT",
  "IN_PROBATION",
  "PROBATION_REVIEW",
  "PROBATION_EXTENDED",
  "PROBATION_PASSED",
  "MID_GENERATED",
  "OFFER_LETTER_GENERATED",
  "OFFER_LETTER_SENT",
  "ACTIVE",
  "SIGNED_OFFER_VERIFIED"
];

// ------------------------------
// Calculate Leave Days
// Sundays are NOT counted
// ------------------------------
export function calculateLeaveDays(startDate, endDate) {
  const start = new Date(startDate);
  const end = new Date(endDate);

  if (start > end) {
    throw new Error("Start Date cannot be after End Date.");
  }

  let days = 0;
  const current = new Date(start);

  while (current <= end) {
    // Sunday = 0
    if (current.getDay() !== 0) {
      days++;
    }

    current.setDate(current.getDate() + 1);
  }

  return days;
}

// ------------------------------
// Validate Leave Form
// ------------------------------
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

  if (
    leaveDays > 15 &&
    !formData.supporting_document?.trim()
  ) {
    throw new Error(
      "Supporting document is mandatory for leave greater than 15 days."
    );
  }

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
    .in("lifecycle_status", ELIGIBLE_STATUSES)
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

  const requestedLeaveDays =
    validateLeaveApplication(formData);

  // Check candidate lifecycle status
  const { data: lifecycle, error: lifecycleError } =
  await supabase
    .from("hr_lifecycle")
    .select("lifecycle_status, mid")
    .eq("candidate_id", formData.candidate_id)
    .single();

  if (lifecycleError) {
    throw lifecycleError;
  }

  if (
    !ELIGIBLE_STATUSES.includes(
      lifecycle.lifecycle_status
    )
  ) {
    throw new Error(
      "Candidate is not eligible to apply for leave."
    );
  }

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

  if (!balance) {
    const { error: createBalanceError } = await supabase
      .from("leave_balances")
      .insert({
        candidate_id: formData.candidate_id,
        mid: lifecycle.mid,
        allocated_leave_days: 15,
        approved_leave_days: 0,
        remaining_leave_days: 15,
        extra_leave_days: 0,
        created_at: now,
      });

    if (createBalanceError) {
      throw createBalanceError;
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
