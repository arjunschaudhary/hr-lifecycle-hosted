import { supabase } from "./supabaseClient";

function parseDateOnly(dateValue) {
  const [year, month, day] = String(dateValue || "")
    .split("-")
    .map(Number);

  if (!year || !month || !day) {
    throw new Error("A valid internship end date is required.");
  }

  return new Date(Date.UTC(year, month - 1, day));
}

function formatDateOnly(dateValue) {
  return dateValue.toISOString().split("T")[0];
}

function extendEndDateSkippingSundays(currentEndDate, leaveDays) {
  const nextDate = parseDateOnly(currentEndDate);
  let countedDays = 0;

  while (countedDays < leaveDays) {
    nextDate.setUTCDate(nextDate.getUTCDate() + 1);

    if (nextDate.getUTCDay() !== 0) {
      countedDays += 1;
    }
  }

  return formatDateOnly(nextDate);
}

export async function getPendingLeaveRequests() {
  const { data, error } = await supabase
    .from("leave_requests_view")
    .select("*")
    .eq("leave_status", "PENDING")
    .order("start_date");

  if (error) throw error;

  return data;
}

export async function approveLeave(leaveRequestId) {
  const now = new Date().toISOString();

  // Fetch leave request
  const { data: request, error: requestError } = await supabase
    .from("leave_requests")
    .select("*")
    .eq("leave_request_id", leaveRequestId)
    .single();

  if (requestError) throw requestError;

  if (request.leave_status !== "PENDING") {
    throw new Error("Only pending leave requests can be approved.");
  }

  // Fetch balance
  const { data: balance, error: balanceError } = await supabase
    .from("leave_balances")
    .select("*")
    .eq("candidate_id", request.candidate_id)
    .single();

  if (balanceError) throw balanceError;

  const { data: lifecycle, error: lifecycleError } = await supabase
    .from("hr_lifecycle")
    .select("current_end_date, mid")
    .eq("candidate_id", request.candidate_id)
    .single();

  if (lifecycleError) throw lifecycleError;

  const requestedLeaveDays = Number(request.requested_leave_days);
  const allocatedLeaveDays = Number(balance.allocated_leave_days || 15);
  const existingApprovedLeaveDays = Number(
    balance.approved_leave_days || 0
  );
  const existingExtraLeaveDays = Number(balance.extra_leave_days || 0);
  const totalApprovedLeaveDays =
    existingApprovedLeaveDays +
    existingExtraLeaveDays +
    requestedLeaveDays;

  const approvedLeaveDays = Math.min(
    totalApprovedLeaveDays,
    allocatedLeaveDays
  );
  const remainingLeaveDays = Math.max(
    allocatedLeaveDays - approvedLeaveDays,
    0
  );
  const extraLeaveDays = Math.max(
    totalApprovedLeaveDays - allocatedLeaveDays,
    0
  );
  const currentEndDate = extendEndDateSkippingSundays(
    lifecycle.current_end_date,
    requestedLeaveDays
  );

  // Update leave request
  const { data: updatedRequest, error: updateRequestError } = await supabase
    .from("leave_requests")
    .update({
      leave_status: "APPROVED",
      approved_at: now
    })
    .eq("leave_request_id", leaveRequestId)
    .eq("leave_status", "PENDING")
    .select("leave_request_id")
    .maybeSingle();

  if (updateRequestError) throw updateRequestError;

  if (!updatedRequest) {
    throw new Error("Only pending leave requests can be approved.");
  }

  // Update balance
  const { error: updateBalanceError } = await supabase
    .from("leave_balances")
    .update({
      approved_leave_days: approvedLeaveDays,
      remaining_leave_days: remainingLeaveDays,
      extra_leave_days: extraLeaveDays,
      updated_at: now
    })
    .eq("candidate_id", request.candidate_id);

  if (updateBalanceError) throw updateBalanceError;

  const { error: lifecycleUpdateError } = await supabase
    .from("hr_lifecycle")
    .update({
      current_end_date: currentEndDate,
      updated_at: now
    })
    .eq("candidate_id", request.candidate_id);

  if (lifecycleUpdateError) throw lifecycleUpdateError;

  const extensionMid = request.mid || lifecycle.mid;

  if (extensionMid) {
    const { error: extensionError } = await supabase
      .from("internship_extensions")
      .insert({
        candidate_id: request.candidate_id,
        mid: extensionMid,
        extension_type: "LEAVE",
        extension_value: requestedLeaveDays,
        reason: "Approved leave extension",
        created_at: now,
        is_processed: true
      });

    if (extensionError) throw extensionError;
  }

  // Activity Log
  const { error: logError } = await supabase
    .from("hr_activity_logs")
    .insert({
      candidate_id: request.candidate_id,
      activity_type: "LEAVE_APPROVED",
      from_status: "PENDING",
      to_status: "APPROVED",
      remarks: "Leave approved",
      activity_status: "SUCCESS",
      performed_by: "HR",
      performed_at: now
    });

  if (logError) throw logError;

  return true;
}

export async function rejectLeave(leaveRequestId) {
  // Fetch leave request
  const { data: request, error: requestError } = await supabase
    .from("leave_requests")
    .select("*")
    .eq("leave_request_id", leaveRequestId)
    .single();

  if (requestError) throw requestError;

  // Update leave request
  const { error: updateError } = await supabase
    .from("leave_requests")
    .update({
      leave_status: "REJECTED",
      rejected_at: new Date().toISOString()
    })
    .eq("leave_request_id", leaveRequestId);

  if (updateError) throw updateError;

  // Activity Log
  const { error: logError } = await supabase
    .from("hr_activity_logs")
    .insert({
      candidate_id: request.candidate_id,
      activity_type: "LEAVE_REJECTED",
      from_status: "PENDING",
      to_status: "REJECTED",
      remarks: "Leave rejected",
      activity_status: "SUCCESS",
      performed_by: "HR",
      performed_at: new Date().toISOString()
    });

  if (logError) throw logError;

  return true;
}
