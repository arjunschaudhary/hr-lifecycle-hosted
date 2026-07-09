import { supabase } from "./supabaseClient";
import {
  calculateAllocatedLeaveDays,
  calculateCurrentEndDate,
  calculateRemainingLeaveDays,
  ELIGIBLE_LEAVE_STATUSES,
  getInternshipDurationDays,
} from "../utils/leaveRules";

function sumExtensionMonths(extensionRows = []) {
  return extensionRows.reduce(
    (total, extension) => total + Number(extension.extension_value || 0),
    0
  );
}

function normalizeSearch(value) {
  return String(value || "").trim().toLowerCase();
}

function filterBySearch(candidates, searchTerm) {
  const normalizedSearch = normalizeSearch(searchTerm);

  if (!normalizedSearch) {
    return candidates;
  }

  return candidates.filter((candidate) =>
    [
      candidate.full_name,
      candidate.email,
      candidate.phone,
      candidate.mid,
      candidate.applied_role,
    ]
      .filter(Boolean)
      .some((value) =>
        String(value).toLowerCase().includes(normalizedSearch)
      )
  );
}

export async function fetchExtensionCandidates(searchTerm = "") {
  if (!supabase) {
    throw new Error("Supabase is not configured.");
  }

  const { data, error } = await supabase
    .from("candidate_detail_view")
    .select(
      [
        "candidate_id",
        "full_name",
        "email",
        "phone",
        "applied_role",
        "lifecycle_status",
        "probation_start_date",
        "internship_duration_months",
        "total_extension_months",
        "total_internship_duration_days",
        "current_internship_duration_days",
        "current_end_date",
        "mid",
        "allocated_leave_days",
        "approved_leave_days",
        "remaining_leave_days",
        "extra_leave_days",
      ].join(",")
    )
    .in("lifecycle_status", ELIGIBLE_LEAVE_STATUSES)
    .order("full_name");

  if (error) {
    throw error;
  }

  return filterBySearch(data || [], searchTerm);
}

export async function extendInternship({
  candidateId,
  extensionMonths,
  reason,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase is not configured.");
  }

  const months = Number(extensionMonths);
  const trimmedReason = String(reason || "").trim();

  if (!candidateId) {
    throw new Error("Candidate is required.");
  }

  if (!Number.isInteger(months) || months < 1 || months > 6) {
    throw new Error("Extension months must be between 1 and 6.");
  }

  if (!trimmedReason) {
    throw new Error("Extension reason is required.");
  }

  const now = new Date().toISOString();

  const { data: lifecycle, error: lifecycleError } = await supabase
    .from("hr_lifecycle")
    .select(
      [
        "lifecycle_status",
        "probation_start_date",
        "internship_duration_months",
        "mid",
      ].join(",")
    )
    .eq("candidate_id", candidateId)
    .single();

  if (lifecycleError) {
    throw lifecycleError;
  }

  if (!ELIGIBLE_LEAVE_STATUSES.includes(lifecycle.lifecycle_status)) {
    throw new Error("Candidate is not eligible for internship extension.");
  }

  const { data: extensionRows, error: extensionRowsError } = await supabase
    .from("internship_extensions")
    .select("extension_value")
    .eq("candidate_id", candidateId)
    .eq("extension_type", "MONTHS")
    .eq("is_processed", true);

  if (extensionRowsError) {
    throw extensionRowsError;
  }

  const previousExtensionMonths = sumExtensionMonths(extensionRows);
  const totalExtensionMonths = previousExtensionMonths + months;
  const totalInternshipDurationDays =
    getInternshipDurationDays(lifecycle.internship_duration_months) +
    totalExtensionMonths * 30;

  const { data: balance, error: balanceError } = await supabase
    .from("leave_balances")
    .select("*")
    .eq("candidate_id", candidateId)
    .maybeSingle();

  if (balanceError) {
    throw balanceError;
  }

  const allocatedLeaveDays = calculateAllocatedLeaveDays(
    lifecycle.internship_duration_months,
    totalExtensionMonths
  );
  const approvedLeaveDays = Number(balance?.approved_leave_days || 0);
  const extraLeaveDays = Number(balance?.extra_leave_days || 0);
  const remainingLeaveDays = calculateRemainingLeaveDays(
    allocatedLeaveDays,
    approvedLeaveDays
  );
  const currentEndDate = calculateCurrentEndDate({
    probationStartDate: lifecycle.probation_start_date,
    durationMonths: lifecycle.internship_duration_months,
    extensionMonths: totalExtensionMonths,
    approvedLeaveDays,
    extraLeaveDays,
  });

  const { error: extensionInsertError } = await supabase
    .from("internship_extensions")
    .insert({
      candidate_id: candidateId,
      mid: lifecycle.mid || null,
      extension_type: "MONTHS",
      extension_value: months,
      reason: trimmedReason,
      created_at: now,
      is_processed: true,
    });

  if (extensionInsertError) {
    throw extensionInsertError;
  }

  const { error: lifecycleUpdateError } = await supabase
    .from("hr_lifecycle")
    .update({
      total_extension_months: totalExtensionMonths,
      total_internship_duration_days: totalInternshipDurationDays,
      current_internship_duration_days: totalInternshipDurationDays,
      current_end_date: currentEndDate,
      updated_at: now,
    })
    .eq("candidate_id", candidateId);

  if (lifecycleUpdateError) {
    throw lifecycleUpdateError;
  }

  const balancePayload = {
    candidate_id: candidateId,
    mid: lifecycle.mid || balance?.mid || null,
    allocated_leave_days: allocatedLeaveDays,
    approved_leave_days: approvedLeaveDays,
    remaining_leave_days: remainingLeaveDays,
    extra_leave_days: extraLeaveDays,
    updated_at: now,
  };

  const { error: balanceUpsertError } = await supabase
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

  if (balanceUpsertError) {
    throw balanceUpsertError;
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: "INTERNSHIP_EXTENDED",
    from_status: lifecycle.lifecycle_status,
    to_status: lifecycle.lifecycle_status,
    remarks: `Internship extended by ${months} month(s). ${trimmedReason}`,
    activity_status: "SUCCESS",
    metadata: {
      extension_months: months,
      total_extension_months: totalExtensionMonths,
      allocated_leave_days: allocatedLeaveDays,
      current_end_date: currentEndDate,
    },
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return {
    allocatedLeaveDays,
    currentEndDate,
    totalExtensionMonths,
    totalInternshipDurationDays,
  };
}
