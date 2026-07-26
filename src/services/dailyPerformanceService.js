import { supabase } from "./supabaseClient";

export const DAILY_PERFORMANCE_REASON_OPTIONS = [
  { value: "WORK_COMPLETED", label: "Work Completed" },
  { value: "PARTIAL_COMPLETION", label: "Partial Completion" },
  { value: "QUALITY_ISSUE", label: "Quality Issue" },
  { value: "DEADLINE_DELAY", label: "Deadline Delay" },
  { value: "BLOCKER_COMMUNICATED", label: "Blocker Communicated" },
  { value: "MISSED_UPDATE", label: "Missed Update" },
  { value: "STRONG_OWNERSHIP", label: "Strong Ownership" },
  { value: "MEETING_ABSENCE", label: "Meeting Absence" },
  { value: "FALSE_UPDATE", label: "False Update" },
  { value: "OTHER", label: "Other" },
];

const SAFE_DAILY_ENTRIES_ERROR =
  "Unable to load daily performance entries.";

const SAFE_SAVE_DAILY_ENTRY_ERROR =
  "Unable to save the daily performance entry.";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

const DAILY_ENTRY_COLUMNS = [
  "candidate_cycle_id",
  "candidate_id",
  "full_name",
  "cycle_id",
  "cycle_code",
  "pod_id",
  "pod_code",
  "pod_name",
  "evaluation_start_date",
  "evaluation_end_date",
  "result_status",
  "performance_date",
  "is_scorable",
  "exclusion_reason",
  "entry_id",
  "work_delivery_score",
  "communication_responsibility_score",
  "daily_total",
  "reason_code",
  "reviewer_comment",
  "reviewer_user_id",
  "reviewer_name",
  "submitted_at",
  "created_at",
  "updated_at",
];

const SAVE_RESPONSE_FIELDS = [
  "dailyEntryId",
  "candidateCycleId",
  "candidateId",
  "performanceDate",
  "workDeliveryScore",
  "communicationResponsibilityScore",
  "dailyTotal",
  "reasonCode",
  "reviewerComment",
  "reviewerUserId",
  "submittedAt",
  "scoredDays",
  "dailyAverage",
  "dailyComponentScore",
  "oldStatus",
  "newStatus",
  "operation",
];

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const isNonEmptyString = (value) =>
  typeof value === "string" && value.trim().length > 0;

const isValidDate = (value) => {
  if (typeof value !== "string" || !DATE_PATTERN.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00.000Z`);
  return (
    !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value
  );
};

const isNullableUuid = (value) => value === null || isValidUuid(value);

const isNullableString = (value) =>
  value === null || typeof value === "string";

const isIntegerInRange = (value, minimum, maximum) =>
  Number.isInteger(value) && value >= minimum && value <= maximum;

const isNullableIntegerInRange = (value, minimum, maximum) =>
  value === null || isIntegerInRange(value, minimum, maximum);

const isNullableFiniteNumber = (value) =>
  value === null || (typeof value === "number" && Number.isFinite(value));

const hasCompleteShape = (value, fields) =>
  fields.every((field) =>
    Object.prototype.hasOwnProperty.call(value, field)
  );

const APPROVED_REASON_CODES = new Set(
  DAILY_PERFORMANCE_REASON_OPTIONS.map((option) => option.value)
);

function mapDailyPerformanceEntry(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, DAILY_ENTRY_COLUMNS) ||
    !isValidUuid(row.candidate_cycle_id) ||
    !isValidUuid(row.candidate_id) ||
    !isValidUuid(row.cycle_id) ||
    !isValidUuid(row.pod_id) ||
    !isNonEmptyString(row.full_name) ||
    !isNonEmptyString(row.cycle_code) ||
    !isNonEmptyString(row.pod_code) ||
    !isNonEmptyString(row.pod_name) ||
    !isNonEmptyString(row.result_status) ||
    !isNonEmptyString(row.performance_date) ||
    !isValidDate(row.evaluation_start_date) ||
    !isValidDate(row.evaluation_end_date) ||
    typeof row.is_scorable !== "boolean" ||
    !isNullableString(row.exclusion_reason) ||
    !isNullableUuid(row.entry_id) ||
    !isNullableIntegerInRange(row.work_delivery_score, -5, 5) ||
    !isNullableIntegerInRange(
      row.communication_responsibility_score,
      -5,
      5
    ) ||
    !isNullableIntegerInRange(row.daily_total, -10, 10) ||
    !isNullableString(row.reason_code) ||
    !isNullableString(row.reviewer_comment) ||
    !isNullableUuid(row.reviewer_user_id) ||
    !isNullableString(row.reviewer_name) ||
    !isNullableString(row.submitted_at) ||
    !isNullableString(row.created_at) ||
    !isNullableString(row.updated_at) ||
    (row.entry_id !== null &&
      (row.work_delivery_score === null ||
        row.communication_responsibility_score === null ||
        row.daily_total === null))
  ) {
    throw new Error(SAFE_DAILY_ENTRIES_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    podId: row.pod_id,
    podCode: row.pod_code,
    podName: row.pod_name,
    evaluationStartDate: row.evaluation_start_date,
    evaluationEndDate: row.evaluation_end_date,
    resultStatus: row.result_status,
    performanceDate: row.performance_date,
    isScorable: row.is_scorable,
    exclusionReason: row.exclusion_reason,
    entryId: row.entry_id,
    workDeliveryScore: row.work_delivery_score,
    communicationResponsibilityScore:
      row.communication_responsibility_score,
    dailyTotal: row.daily_total,
    reasonCode: row.reason_code,
    reviewerComment: row.reviewer_comment,
    reviewerUserId: row.reviewer_user_id,
    reviewerName: row.reviewer_name,
    submittedAt: row.submitted_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapSaveResponse(data) {
  if (
    !isRecord(data) ||
    !hasCompleteShape(data, SAVE_RESPONSE_FIELDS) ||
    !isValidUuid(data.dailyEntryId) ||
    !isValidUuid(data.candidateCycleId) ||
    !isValidUuid(data.candidateId) ||
    !isValidUuid(data.reviewerUserId) ||
    !isValidDate(data.performanceDate) ||
    !isIntegerInRange(data.workDeliveryScore, -5, 5) ||
    !isIntegerInRange(data.communicationResponsibilityScore, -5, 5) ||
    !isIntegerInRange(data.dailyTotal, -10, 10) ||
    !Number.isInteger(data.scoredDays) ||
    data.scoredDays < 0 ||
    !isNullableFiniteNumber(data.dailyAverage) ||
    !isNullableFiniteNumber(data.dailyComponentScore) ||
    !isNullableString(data.reasonCode) ||
    !isNullableString(data.reviewerComment) ||
    !isNonEmptyString(data.submittedAt) ||
    !isNonEmptyString(data.oldStatus) ||
    !isNonEmptyString(data.newStatus) ||
    !["CREATED", "UPDATED"].includes(data.operation)
  ) {
    throw new Error(SAFE_SAVE_DAILY_ENTRY_ERROR);
  }

  return {
    dailyEntryId: data.dailyEntryId,
    candidateCycleId: data.candidateCycleId,
    candidateId: data.candidateId,
    performanceDate: data.performanceDate,
    workDeliveryScore: data.workDeliveryScore,
    communicationResponsibilityScore:
      data.communicationResponsibilityScore,
    dailyTotal: data.dailyTotal,
    reasonCode: data.reasonCode,
    reviewerComment: data.reviewerComment,
    reviewerUserId: data.reviewerUserId,
    submittedAt: data.submittedAt,
    scoredDays: data.scoredDays,
    dailyAverage: data.dailyAverage,
    dailyComponentScore: data.dailyComponentScore,
    oldStatus: data.oldStatus,
    newStatus: data.newStatus,
    operation: data.operation,
  };
}

export async function fetchCandidateDailyPerformanceEntries(
  candidateCycleId
) {
  if (!isValidUuid(candidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_DAILY_ENTRIES_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "get_candidate_daily_performance_entries",
      {
        p_candidate_cycle_id: candidateCycleId,
      }
    );

    if (error || !Array.isArray(data)) {
      throw new Error(SAFE_DAILY_ENTRIES_ERROR);
    }

    return data.map(mapDailyPerformanceEntry);
  } catch {
    throw new Error(SAFE_DAILY_ENTRIES_ERROR);
  }
}

export async function saveCandidateDailyPerformanceEntry(input) {
  if (!isRecord(input) || !isValidUuid(input.candidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  const {
    candidateCycleId,
    performanceDate,
    workDeliveryScore,
    communicationResponsibilityScore,
    reasonCode,
    reviewerComment,
  } = input;

  if (!isValidDate(performanceDate)) {
    throw new Error("A valid performance date is required.");
  }

  if (
    !isIntegerInRange(workDeliveryScore, -5, 5) ||
    !isIntegerInRange(communicationResponsibilityScore, -5, 5)
  ) {
    throw new Error(
      "Both scores must be whole numbers between -5 and 5."
    );
  }

  const normalizedReasonCode =
    reasonCode === null || reasonCode === undefined
      ? null
      : typeof reasonCode === "string"
        ? reasonCode.trim().toUpperCase() || null
        : reasonCode;

  const normalizedReviewerComment =
    reviewerComment === null || reviewerComment === undefined
      ? null
      : typeof reviewerComment === "string"
        ? reviewerComment.trim() || null
        : reviewerComment;

  if (
    !isNullableString(normalizedReasonCode) ||
    (normalizedReasonCode !== null &&
      !APPROVED_REASON_CODES.has(normalizedReasonCode))
  ) {
    throw new Error("Select a valid reason.");
  }

  if (
    !isNullableString(normalizedReviewerComment) ||
    (normalizedReviewerComment !== null &&
      normalizedReviewerComment.length > 2000)
  ) {
    throw new Error(
      "Reviewer comment must not exceed 2000 characters."
    );
  }

  const dailyTotal =
    workDeliveryScore + communicationResponsibilityScore;

  if (
    (dailyTotal <= -5 || dailyTotal === 10) &&
    normalizedReasonCode === null
  ) {
    throw new Error("A reason is required for this daily score.");
  }

  if (dailyTotal === -10 && normalizedReviewerComment === null) {
    throw new Error(
      "A reviewer comment is required for the minimum daily score."
    );
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_SAVE_DAILY_ENTRY_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "save_candidate_daily_performance_entry",
      {
        p_candidate_cycle_id: candidateCycleId,
        p_performance_date: performanceDate,
        p_work_delivery_score: workDeliveryScore,
        p_communication_responsibility_score:
          communicationResponsibilityScore,
        p_reason_code: normalizedReasonCode,
        p_reviewer_comment: normalizedReviewerComment,
      }
    );

    if (error) {
      throw new Error(SAFE_SAVE_DAILY_ENTRY_ERROR);
    }

    return mapSaveResponse(data);
  } catch {
    throw new Error(SAFE_SAVE_DAILY_ENTRY_ERROR);
  }
}
