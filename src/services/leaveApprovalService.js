import { supabase } from "./supabaseClient";
import {
  calculateAllocatedLeaveDays,
  calculateCurrentEndDate,
  calculateLeaveApprovalBalance,
} from "../utils/leaveRules";

function sumExtensionMonths(extensionRows = []) {
  return extensionRows.reduce(
    (total, extension) => total + Number(extension.extension_value || 0),
    0
  );
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

  const { data: request, error: requestError } = await supabase
    .from("leave_requests")
    .select("*")
    .eq("leave_request_id", leaveRequestId)
    .single();

  if (requestError) throw requestError;

  if (request.leave_status !== "PENDING") {
    throw new Error("Only pending leave requests can be approved.");
  }

  const { data: lifecycle, error: lifecycleError } = await supabase
    .from("hr_lifecycle")
    .select("probation_start_date, internship_duration_months, mid")
    .eq("candidate_id", request.candidate_id)
    .single();

  if (lifecycleError) throw lifecycleError;

  const { data: extensionRows, error: extensionError } = await supabase
    .from("internship_extensions")
    .select("extension_value")
    .eq("candidate_id", request.candidate_id)
    .eq("extension_type", "MONTHS")
    .eq("is_processed", true);

  if (extensionError) throw extensionError;

  const { data: balance, error: balanceError } = await supabase
    .from("leave_balances")
    .select("*")
    .eq("candidate_id", request.candidate_id)
    .maybeSingle();

  if (balanceError) throw balanceError;

  const extensionMonths = sumExtensionMonths(extensionRows);
  const requestedLeaveDays = Number(request.requested_leave_days);
  const allocatedLeaveDays = calculateAllocatedLeaveDays(
    lifecycle.internship_duration_months,
    extensionMonths
  );
  const nextBalance = calculateLeaveApprovalBalance({
    allocatedLeaveDays,
    approvedLeaveDays: balance?.approved_leave_days,
    extraLeaveDays: balance?.extra_leave_days,
    requestedLeaveDays,
  });
  const currentEndDate = calculateCurrentEndDate({
    probationStartDate: lifecycle.probation_start_date,
    durationMonths: lifecycle.internship_duration_months,
    extensionMonths,
    approvedLeaveDays: nextBalance.approved_leave_days,
    extraLeaveDays: nextBalance.extra_leave_days,
  });
  const extensionMid = request.mid || lifecycle.mid;

  const { data: updatedRequest, error: updateRequestError } = await supabase
    .from("leave_requests")
    .update({
      leave_status: "APPROVED",
      approved_at: now,
    })
    .eq("leave_request_id", leaveRequestId)
    .eq("leave_status", "PENDING")
    .select("leave_request_id")
    .maybeSingle();

  if (updateRequestError) throw updateRequestError;

  if (!updatedRequest) {
    throw new Error("Only pending leave requests can be approved.");
  }

  const balancePayload = {
    candidate_id: request.candidate_id,
    mid: extensionMid,
    allocated_leave_days: allocatedLeaveDays,
    approved_leave_days: nextBalance.approved_leave_days,
    remaining_leave_days: nextBalance.remaining_leave_days,
    extra_leave_days: nextBalance.extra_leave_days,
    updated_at: now,
  };

  const { error: upsertBalanceError } = await supabase
    .from("leave_balances")
    .upsert(
      balance
        ? balancePayload
        : {
            ...balancePayload,
            created_at: now,
          },
      { onConflict: "candidate_id" }
    );

  if (upsertBalanceError) throw upsertBalanceError;

  const { error: lifecycleUpdateError } = await supabase
    .from("hr_lifecycle")
    .update({
      current_end_date: currentEndDate,
      updated_at: now,
    })
    .eq("candidate_id", request.candidate_id);

  if (lifecycleUpdateError) throw lifecycleUpdateError;

  if (extensionMid) {
    const { error: extensionInsertError } = await supabase
      .from("internship_extensions")
      .insert({
        candidate_id: request.candidate_id,
        mid: extensionMid,
        extension_type: "LEAVE",
        extension_value: requestedLeaveDays,
        reason: "Approved leave extension",
        created_at: now,
        is_processed: true,
      });

    if (extensionInsertError) throw extensionInsertError;
  }

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
      performed_at: now,
    });

  if (logError) throw logError;

  return true;
}

export async function rejectLeave(leaveRequestId) {
  const { data: request, error: requestError } = await supabase
    .from("leave_requests")
    .select("*")
    .eq("leave_request_id", leaveRequestId)
    .single();

  if (requestError) throw requestError;

  const { error: updateError } = await supabase
    .from("leave_requests")
    .update({
      leave_status: "REJECTED",
      rejected_at: new Date().toISOString(),
    })
    .eq("leave_request_id", leaveRequestId);

  if (updateError) throw updateError;

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
      performed_at: new Date().toISOString(),
    });

  if (logError) throw logError;

  return true;
}
