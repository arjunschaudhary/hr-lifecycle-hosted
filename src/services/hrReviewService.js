import { supabase } from "./supabaseClient";

const SAFE_HR_REVIEW_TASKS_ERROR =
  "Unable to load HR Review tasks.";
const SAFE_HR_REVIEW_ERROR =
  "Unable to load the HR Review.";
const SAFE_SAVE_HR_REVIEW_ERROR =
  "Unable to save the HR Review.";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const HR_REVIEW_TASK_COLUMNS = [
  "candidate_cycle_id",
  "candidate_id",
  "full_name",
  "email",
  "applied_role",
  "role_code",
  "cycle_id",
  "cycle_code",
  "cycle_number",
  "cycle_start_date",
  "cycle_end_date",
  "review_open_date",
  "lock_date",
  "cycle_status",
  "pod_id",
  "pod_code",
  "pod_name",
  "evaluation_start_date",
  "evaluation_end_date",
  "is_partial_cycle",
  "result_status",
  "eligible_days",
  "scored_days",
  "daily_component_score",
  "daily_scoring_complete",
  "review_is_open",
  "review_id",
  "review_status",
  "task_status",
  "reviewer_user_id",
  "reviewer_name",
  "communication_professionalism_score",
  "attendance_update_discipline_score",
  "reporting_policy_compliance_score",
  "total_score",
  "reviewer_comment",
  "submitted_at",
  "review_created_at",
  "review_updated_at",
  "can_edit",
];

const HR_REVIEW_COLUMNS = [
  "candidate_cycle_id",
  "candidate_id",
  "full_name",
  "email",
  "applied_role",
  "role_code",
  "cycle_id",
  "cycle_code",
  "cycle_number",
  "cycle_start_date",
  "cycle_end_date",
  "cycle_status",
  "review_open_date",
  "lock_date",
  "pod_id",
  "pod_code",
  "pod_name",
  "evaluation_start_date",
  "evaluation_end_date",
  "result_status",
  "eligible_days",
  "scored_days",
  "daily_component_score",
  "daily_scoring_complete",
  "review_is_open",
  "review_id",
  "communication_professionalism_score",
  "attendance_update_discipline_score",
  "reporting_policy_compliance_score",
  "total_score",
  "reviewer_comment",
  "review_status",
  "reviewer_user_id",
  "reviewer_name",
  "submitted_at",
  "review_created_at",
  "review_updated_at",
  "task_status",
  "can_edit",
  "edit_reason",
];

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const isNonEmptyString = (value) =>
  typeof value === "string" && value.trim().length > 0;

const hasCompleteShape = (row, columns) =>
  columns.every((column) =>
    Object.prototype.hasOwnProperty.call(row, column)
  );

const hasValidUuids = (row, fields) =>
  fields.every((field) => isValidUuid(row[field]));

const hasNonEmptyStrings = (row, fields) =>
  fields.every((field) => isNonEmptyString(row[field]));

const isNullableUuid = (value) => value === null || isValidUuid(value);

const isNullableString = (value) =>
  value === null || typeof value === "string";

const isIntegerInRange = (value, minimum, maximum) =>
  Number.isInteger(value) && value >= minimum && value <= maximum;

const isNullableIntegerInRange = (value, minimum, maximum) =>
  value === null || isIntegerInRange(value, minimum, maximum);

const isNullableFiniteNumber = (value) =>
  value === null || (typeof value === "number" && Number.isFinite(value));

function mapHrReviewTaskRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, HR_REVIEW_TASK_COLUMNS) ||
    !hasValidUuids(row, [
      "candidate_cycle_id",
      "candidate_id",
      "cycle_id",
      "pod_id",
    ]) ||
    !hasNonEmptyStrings(row, [
      "full_name",
      "email",
      "cycle_code",
      "cycle_status",
      "pod_code",
      "pod_name",
      "result_status",
      "task_status",
    ]) ||
    !isNullableUuid(row.review_id) ||
    !isNullableUuid(row.reviewer_user_id) ||
    typeof row.daily_scoring_complete !== "boolean" ||
    typeof row.review_is_open !== "boolean" ||
    typeof row.can_edit !== "boolean"
  ) {
    throw new Error(SAFE_HR_REVIEW_TASKS_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    appliedRole: row.applied_role,
    roleCode: row.role_code,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    cycleNumber: row.cycle_number,
    cycleStartDate: row.cycle_start_date,
    cycleEndDate: row.cycle_end_date,
    reviewOpenDate: row.review_open_date,
    lockDate: row.lock_date,
    cycleStatus: row.cycle_status,
    podId: row.pod_id,
    podCode: row.pod_code,
    podName: row.pod_name,
    evaluationStartDate: row.evaluation_start_date,
    evaluationEndDate: row.evaluation_end_date,
    isPartialCycle: row.is_partial_cycle,
    resultStatus: row.result_status,
    eligibleDays: row.eligible_days,
    scoredDays: row.scored_days,
    dailyComponentScore: row.daily_component_score,
    dailyScoringComplete: row.daily_scoring_complete,
    reviewIsOpen: row.review_is_open,
    reviewId: row.review_id,
    reviewStatus: row.review_status,
    taskStatus: row.task_status,
    reviewerUserId: row.reviewer_user_id,
    reviewerName: row.reviewer_name,
    communicationProfessionalismScore:
      row.communication_professionalism_score,
    attendanceUpdateDisciplineScore:
      row.attendance_update_discipline_score,
    reportingPolicyComplianceScore:
      row.reporting_policy_compliance_score,
    totalScore: row.total_score,
    reviewerComment: row.reviewer_comment,
    submittedAt: row.submitted_at,
    reviewCreatedAt: row.review_created_at,
    reviewUpdatedAt: row.review_updated_at,
    canEdit: row.can_edit,
  };
}

function mapCandidateHrReviewRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, HR_REVIEW_COLUMNS) ||
    !hasValidUuids(row, [
      "candidate_cycle_id",
      "candidate_id",
      "cycle_id",
      "pod_id",
    ]) ||
    !hasNonEmptyStrings(row, [
      "full_name",
      "email",
      "cycle_code",
      "cycle_status",
      "pod_code",
      "pod_name",
      "result_status",
      "task_status",
    ]) ||
    !isNullableUuid(row.review_id) ||
    !isNullableUuid(row.reviewer_user_id) ||
    !isNullableString(row.reviewer_name) ||
    !isNullableString(row.reviewer_comment) ||
    !isNullableString(row.review_status) ||
    !isNullableString(row.submitted_at) ||
    !isNullableString(row.review_created_at) ||
    !isNullableString(row.review_updated_at) ||
    !isNullableString(row.edit_reason) ||
    !Number.isInteger(row.eligible_days) ||
    row.eligible_days < 0 ||
    !Number.isInteger(row.scored_days) ||
    row.scored_days < 0 ||
    row.scored_days > row.eligible_days ||
    !isNullableFiniteNumber(row.daily_component_score) ||
    typeof row.daily_scoring_complete !== "boolean" ||
    typeof row.review_is_open !== "boolean" ||
    typeof row.can_edit !== "boolean" ||
    !isNullableIntegerInRange(
      row.communication_professionalism_score,
      0,
      5
    ) ||
    !isNullableIntegerInRange(
      row.attendance_update_discipline_score,
      0,
      5
    ) ||
    !isNullableIntegerInRange(
      row.reporting_policy_compliance_score,
      0,
      5
    ) ||
    !isNullableIntegerInRange(row.total_score, 0, 15) ||
    (row.review_status !== null &&
      !["DRAFT", "SUBMITTED"].includes(row.review_status))
  ) {
    throw new Error(SAFE_HR_REVIEW_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    appliedRole: row.applied_role,
    roleCode: row.role_code,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    cycleNumber: row.cycle_number,
    cycleStartDate: row.cycle_start_date,
    cycleEndDate: row.cycle_end_date,
    cycleStatus: row.cycle_status,
    reviewOpenDate: row.review_open_date,
    lockDate: row.lock_date,
    podId: row.pod_id,
    podCode: row.pod_code,
    podName: row.pod_name,
    evaluationStartDate: row.evaluation_start_date,
    evaluationEndDate: row.evaluation_end_date,
    resultStatus: row.result_status,
    eligibleDays: row.eligible_days,
    scoredDays: row.scored_days,
    dailyComponentScore: row.daily_component_score,
    dailyScoringComplete: row.daily_scoring_complete,
    reviewIsOpen: row.review_is_open,
    reviewId: row.review_id,
    communicationProfessionalismScore:
      row.communication_professionalism_score,
    attendanceUpdateDisciplineScore:
      row.attendance_update_discipline_score,
    reportingPolicyComplianceScore:
      row.reporting_policy_compliance_score,
    totalScore: row.total_score,
    reviewerComment: row.reviewer_comment,
    reviewStatus: row.review_status,
    reviewerUserId: row.reviewer_user_id,
    reviewerName: row.reviewer_name,
    submittedAt: row.submitted_at,
    reviewCreatedAt: row.review_created_at,
    reviewUpdatedAt: row.review_updated_at,
    taskStatus: row.task_status,
    canEdit: row.can_edit,
    editReason: row.edit_reason,
  };
}

export async function getHrReviewTasks() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_HR_REVIEW_TASKS_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc("get_hr_review_tasks");

    if (error || !Array.isArray(data)) {
      throw new Error(SAFE_HR_REVIEW_TASKS_ERROR);
    }

    return data.map(mapHrReviewTaskRow);
  } catch {
    throw new Error(SAFE_HR_REVIEW_TASKS_ERROR);
  }
}

export async function getCandidateHrReview(candidateCycleId) {
  if (!isValidUuid(candidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_HR_REVIEW_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "get_candidate_hr_review",
      {
        p_candidate_cycle_id: candidateCycleId,
      }
    );

    if (error || !Array.isArray(data) || data.length !== 1) {
      throw new Error(SAFE_HR_REVIEW_ERROR);
    }

    return mapCandidateHrReviewRow(data[0]);
  } catch {
    throw new Error(SAFE_HR_REVIEW_ERROR);
  }
}

export async function saveCandidateHrReview({
  candidateCycleId,
  communicationProfessionalismScore,
  attendanceUpdateDisciplineScore,
  reportingPolicyComplianceScore,
  reviewerComment,
  reviewStatus,
  amendmentReason,
}) {
  if (!isValidUuid(candidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  const normalizedCommunicationScore =
    communicationProfessionalismScore ?? null;
  const normalizedAttendanceScore =
    attendanceUpdateDisciplineScore ?? null;
  const normalizedComplianceScore =
    reportingPolicyComplianceScore ?? null;

  if (!isNullableIntegerInRange(normalizedCommunicationScore, 0, 5)) {
    throw new Error(
      "Communication and Professionalism score must be between 0 and 5."
    );
  }

  if (!isNullableIntegerInRange(normalizedAttendanceScore, 0, 5)) {
    throw new Error(
      "Attendance and Update Discipline score must be between 0 and 5."
    );
  }

  if (!isNullableIntegerInRange(normalizedComplianceScore, 0, 5)) {
    throw new Error(
      "Reporting and Policy Compliance score must be between 0 and 5."
    );
  }

  if (!["DRAFT", "SUBMITTED"].includes(reviewStatus)) {
    throw new Error("Review status must be DRAFT or SUBMITTED.");
  }

  if (
    reviewStatus === "SUBMITTED" &&
    [
      normalizedCommunicationScore,
      normalizedAttendanceScore,
      normalizedComplianceScore,
    ].some((score) => score === null)
  ) {
    throw new Error("All HR Review scores are required for submission.");
  }

  if (
    reviewerComment !== null &&
    reviewerComment !== undefined &&
    (typeof reviewerComment !== "string" || reviewerComment.length > 2000)
  ) {
    throw new Error(
      "Reviewer comment must not exceed 2000 characters."
    );
  }

  if (
    amendmentReason !== null &&
    amendmentReason !== undefined &&
    (typeof amendmentReason !== "string" || amendmentReason.length > 2000)
  ) {
    throw new Error(
      "Amendment reason must not exceed 2000 characters."
    );
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_SAVE_HR_REVIEW_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "save_candidate_hr_review",
      {
        p_candidate_cycle_id: candidateCycleId,
        p_communication_professionalism_score:
          communicationProfessionalismScore ?? null,
        p_attendance_update_discipline_score:
          attendanceUpdateDisciplineScore ?? null,
        p_reporting_policy_compliance_score:
          reportingPolicyComplianceScore ?? null,
        p_reviewer_comment: reviewerComment ?? null,
        p_review_status: reviewStatus,
        p_amendment_reason: amendmentReason ?? null,
      }
    );

    if (error || !isRecord(data)) {
      throw new Error(SAFE_SAVE_HR_REVIEW_ERROR);
    }

    return data;
  } catch {
    throw new Error(SAFE_SAVE_HR_REVIEW_ERROR);
  }
}
