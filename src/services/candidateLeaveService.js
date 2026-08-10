import { calculateLeaveDays, getTodayKolkataString } from "../utils/leaveRules";
import { supabase } from "./supabaseClient";

export const CANDIDATE_LEAVE_TYPES = [
  "Casual Leave",
  "Sick Leave",
  "Medical / Health",
  "Family Emergency",
  "Personal Work",
  "Family / Personal Event",
  "Bereavement",
  "Academic / Examination",
  "College / University Requirement",
  "Travel",
  "Religious / Cultural Event",
  "Mental Wellbeing / Personal Wellbeing",
  "Emergency",
  "Other",
];

const SAFE_HISTORY_ERROR = "Unable to load your leave-request history.";
const SAFE_SUBMISSION_ERROR = "Unable to submit your leave request.";

const SAFE_RPC_MESSAGES = new Set([
  "Candidate leave access is not available.",
  "Candidate lifecycle record is not available.",
  "Candidate has multiple lifecycle records.",
  "Candidate is not eligible to apply for leave.",
  "Start date and end date are required.",
  "Start date cannot be after end date.",
  "Start date cannot be in the past.",
  "End date cannot be in the past.",
  "Leave type is not available.",
  "Reason is required.",
  "Specify reason is required for other leave type.",
  "Selected dates do not include an eligible leave day.",
  "Leave entitlement is defined only for 3 or 4 month internships.",
  "A supporting document link is required when requested leave exceeds the remaining balance.",
  "Supporting document link must use HTTP or HTTPS.",
  "Supporting document must be a valid URL or candidate storage path.",
  "Supporting document must be a valid URL or storage path.",
  "You already have a pending leave request. Wait for HR to review it before submitting another.",
  "This leave request overlaps with an existing leave request.",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isNonEmptyString = (value) =>
  typeof value === "string" && value.trim().length > 0;

const isNullableString = (value) =>
  value === null || typeof value === "string";

const getSafeHttpUrl = (value) => {
  if (!isNonEmptyString(value)) {
    return null;
  }

  try {
    const url = new URL(value);

    return url.protocol === "http:" || url.protocol === "https:"
      ? url.toString()
      : null;
  } catch {
    return null;
  }
};

const getSafeRpcMessage = (error, fallbackMessage) => {
  const message =
    error && typeof error.message === "string" ? error.message.trim() : "";

  return SAFE_RPC_MESSAGES.has(message) ? message : fallbackMessage;
};

function mapLeaveRequest(row) {
  if (
    !isRecord(row) ||
    !UUID_PATTERN.test(row.leave_request_id) ||
    !isNonEmptyString(row.leave_type) ||
    !DATE_PATTERN.test(row.start_date) ||
    !DATE_PATTERN.test(row.end_date) ||
    !Number.isInteger(row.requested_leave_days) ||
    row.requested_leave_days <= 0 ||
    !isNullableString(row.reason) ||
    !isNullableString(row.supporting_document) ||
    !["PENDING", "APPROVED", "REJECTED"].includes(row.leave_status) ||
    !isNullableString(row.created_at) ||
    !isNullableString(row.updated_at) ||
    !isNullableString(row.approved_at) ||
    !isNullableString(row.rejected_at)
  ) {
    throw new Error(SAFE_HISTORY_ERROR);
  }

  return {
    leaveRequestId: row.leave_request_id,
    leaveType: row.leave_type,
    startDate: row.start_date,
    endDate: row.end_date,
    requestedLeaveDays: row.requested_leave_days,
    reason: row.reason,
    supportingDocument: row.supporting_document || null,
    leaveStatus: row.leave_status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    approvedAt: row.approved_at,
    rejectedAt: row.rejected_at,
  };
}

function mapSubmissionResponse(data) {
  if (
    !isRecord(data) ||
    !UUID_PATTERN.test(data.leaveRequestId) ||
    !isNonEmptyString(data.leaveType) ||
    !DATE_PATTERN.test(data.startDate) ||
    !DATE_PATTERN.test(data.endDate) ||
    !Number.isInteger(data.requestedLeaveDays) ||
    data.requestedLeaveDays <= 0 ||
    !isNonEmptyString(data.reason) ||
    !isNullableString(data.supportingDocument) ||
    data.leaveStatus !== "PENDING" ||
    !isNonEmptyString(data.createdAt)
  ) {
    throw new Error(SAFE_SUBMISSION_ERROR);
  }

  return data;
}

export async function fetchCurrentCandidateLeaveRequests() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_HISTORY_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "get_current_candidate_leave_requests",
    );

    if (error) {
      throw new Error(getSafeRpcMessage(error, SAFE_HISTORY_ERROR));
    }

    if (!Array.isArray(data)) {
      throw new Error(SAFE_HISTORY_ERROR);
    }

    return data.map(mapLeaveRequest);
  } catch (error) {
    if (error instanceof Error && SAFE_RPC_MESSAGES.has(error.message)) {
      throw error;
    }

    throw new Error(SAFE_HISTORY_ERROR, { cause: error });
  }
}

export async function submitCurrentCandidateLeaveRequest({
  leaveType,
  startDate,
  endDate,
  reason,
  supportingDocument,
  remainingLeaveDays,
  otherLeaveTypeReason,
}) {
  const normalizedLeaveType = String(leaveType || "").trim();
  const normalizedReason = String(reason || "").trim();
  const normalizedSupportingDocument = String(
    supportingDocument || "",
  ).trim();
  const normalizedOtherLeaveTypeReason = String(
    otherLeaveTypeReason || "",
  ).trim();

  if (!CANDIDATE_LEAVE_TYPES.includes(normalizedLeaveType)) {
    throw new Error("Select an available leave type.");
  }

  if (!startDate || !endDate) {
    throw new Error("Start date and end date are required.");
  }

  if (!DATE_PATTERN.test(startDate) || !DATE_PATTERN.test(endDate)) {
    throw new Error("Start date and end date are required.");
  }

  const todayStr = getTodayKolkataString();
  if (startDate < todayStr) {
    throw new Error("Start date cannot be in the past.");
  }
  if (endDate < todayStr) {
    throw new Error("End date cannot be in the past.");
  }

  if (normalizedLeaveType === "Other" && !normalizedOtherLeaveTypeReason) {
    throw new Error("Specify reason is required for other leave type.");
  }

  if (!normalizedReason) {
    throw new Error("Reason is required.");
  }

  const requestedLeaveDays = calculateLeaveDays(startDate, endDate);

  if (requestedLeaveDays <= 0) {
    throw new Error("Selected dates do not include an eligible leave day.");
  }

  const isStoragePath = (val) => {
    return typeof val === "string" && val.startsWith("candidate/") && val.endsWith(".pdf");
  };

  if (
    normalizedSupportingDocument &&
    !getSafeHttpUrl(normalizedSupportingDocument) &&
    !isStoragePath(normalizedSupportingDocument)
  ) {
    throw new Error("Supporting document must be a valid URL or storage path.");
  }

  const hasKnownRemainingLeaveDays =
    remainingLeaveDays !== null &&
    remainingLeaveDays !== undefined &&
    remainingLeaveDays !== "";
  const normalizedRemainingLeaveDays = hasKnownRemainingLeaveDays
    ? Number(remainingLeaveDays)
    : null;

  if (
    normalizedRemainingLeaveDays !== null &&
    Number.isFinite(normalizedRemainingLeaveDays) &&
    requestedLeaveDays > normalizedRemainingLeaveDays &&
    !normalizedSupportingDocument
  ) {
    throw new Error(
      "A supporting document link is required when requested leave exceeds the remaining balance.",
    );
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_SUBMISSION_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "submit_current_candidate_leave_request",
      {
        p_leave_type: normalizedLeaveType,
        p_start_date: startDate,
        p_end_date: endDate,
        p_reason: normalizedReason,
        p_supporting_document: normalizedSupportingDocument || null,
        p_other_leave_type_reason: normalizedOtherLeaveTypeReason || null,
      },
    );

    if (error) {
      throw new Error(getSafeRpcMessage(error, SAFE_SUBMISSION_ERROR));
    }

    return mapSubmissionResponse(data);
  } catch (error) {
    if (error instanceof Error && SAFE_RPC_MESSAGES.has(error.message)) {
      throw error;
    }

    throw new Error(SAFE_SUBMISSION_ERROR, { cause: error });
  }
}

export async function uploadLeaveDocument(candidateId, file) {
  if (
    !supabase ||
    !supabase.storage ||
    typeof supabase.storage.from !== "function"
  ) {
    throw new Error("Storage is not configured.");
  }

  const uploadUuid = globalThis.crypto.randomUUID();
  const objectPath = `candidate/${candidateId}/leave-documents/${uploadUuid}.pdf`;

  const { error } = await supabase.storage
    .from("candidate-leave-documents")
    .upload(objectPath, file, {
      upsert: false,
      contentType: "application/pdf",
    });

  if (error) {
    throw error;
  }

  return objectPath;
}

export async function deleteLeaveDocument(objectPath) {
  if (
    !supabase ||
    !supabase.storage ||
    typeof supabase.storage.from !== "function"
  ) {
    return;
  }

  await supabase.storage.from("candidate-leave-documents").remove([objectPath]);
}

export async function getSupportingDocumentUrl(objectPath) {
  if (
    !supabase ||
    !supabase.storage ||
    typeof supabase.storage.from !== "function"
  ) {
    throw new Error("Storage is not configured.");
  }

  const { data, error } = await supabase.storage
    .from("candidate-leave-documents")
    .createSignedUrl(objectPath, 60);

  if (error) {
    throw error;
  }

  return data.signedUrl;
}
