import { supabase } from "./supabaseClient";

const SAFE_LEAD_REVIEW_TASKS_ERROR =
  "Unable to load Lead Review tasks.";
const SAFE_LEAD_REVIEW_ERROR =
  "Unable to load the Lead Review.";
const SAFE_SAVE_LEAD_REVIEW_ERROR =
  "Unable to save the Lead Review.";
const SAFE_SAVE_LEAD_REVIEW_MESSAGES = new Set([
  "You cannot submit a Lead Review for your own candidate cycle.",
  "Project Manager Lead Reviews require an eligible Pod Lead.",
  "Pod Lead candidates cannot receive a Lead Review.",
  "This Lead Review draft is already owned by another reviewer.",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const LEAD_REVIEW_TASK_COLUMNS = [
  "candidate_cycle_id",
  "candidate_id",
  "full_name",
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
  "eligible_days",
  "scored_days",
  "daily_component_score",
  "daily_scoring_complete",
  "review_is_open",
  "review_id",
  "review_status",
  "review_display_status",
  "reviewer_user_id",
  "reviewer_name",
  "work_quality_score",
  "role_capability_score",
  "deadline_delivery_score",
  "ownership_teamwork_score",
  "total_score",
  "reviewer_comment",
  "submitted_at",
  "review_created_at",
  "review_updated_at",
  "can_edit",
];

const LEAD_REVIEW_COLUMNS = [
  "candidate_cycle_id",
  "candidate_id",
  "full_name",
  "cycle_id",
  "cycle_code",
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
  "reviewer_user_id",
  "reviewer_name",
  "work_quality_score",
  "role_capability_score",
  "deadline_delivery_score",
  "ownership_teamwork_score",
  "total_score",
  "reviewer_comment",
  "review_status",
  "submitted_at",
  "review_created_at",
  "review_updated_at",
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

const getSafeSaveLeadReviewMessage = (error) => {
  const message =
    isRecord(error) && typeof error.message === "string"
      ? error.message.trim()
      : "";

  return SAFE_SAVE_LEAD_REVIEW_MESSAGES.has(message)
    ? message
    : SAFE_SAVE_LEAD_REVIEW_ERROR;
};

function mapLeadReviewTaskRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, LEAD_REVIEW_TASK_COLUMNS) ||
    !hasValidUuids(row, [
      "candidate_cycle_id",
      "candidate_id",
      "cycle_id",
      "pod_id",
    ]) ||
    !hasNonEmptyStrings(row, [
      "full_name",
      "cycle_code",
      "cycle_status",
      "pod_code",
      "pod_name",
      "review_display_status",
    ]) ||
    (row.review_id !== null && !isValidUuid(row.review_id)) ||
    (row.reviewer_user_id !== null &&
      !isValidUuid(row.reviewer_user_id)) ||
    typeof row.daily_scoring_complete !== "boolean" ||
    typeof row.review_is_open !== "boolean" ||
    typeof row.can_edit !== "boolean"
  ) {
    throw new Error(SAFE_LEAD_REVIEW_TASKS_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
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
    eligibleDays: row.eligible_days,
    scoredDays: row.scored_days,
    dailyComponentScore: row.daily_component_score,
    dailyScoringComplete: row.daily_scoring_complete,
    reviewIsOpen: row.review_is_open,
    reviewId: row.review_id,
    reviewStatus: row.review_status,
    reviewDisplayStatus: row.review_display_status,
    reviewerUserId: row.reviewer_user_id,
    reviewerName: row.reviewer_name,
    workQualityScore: row.work_quality_score,
    roleCapabilityScore: row.role_capability_score,
    deadlineDeliveryScore: row.deadline_delivery_score,
    ownershipTeamworkScore: row.ownership_teamwork_score,
    totalScore: row.total_score,
    reviewerComment: row.reviewer_comment,
    submittedAt: row.submitted_at,
    reviewCreatedAt: row.review_created_at,
    reviewUpdatedAt: row.review_updated_at,
    canEdit: row.can_edit,
  };
}

function mapCandidateLeadReviewRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, LEAD_REVIEW_COLUMNS) ||
    !hasValidUuids(row, [
      "candidate_cycle_id",
      "candidate_id",
      "cycle_id",
      "pod_id",
    ]) ||
    !hasNonEmptyStrings(row, [
      "full_name",
      "cycle_code",
      "cycle_status",
      "pod_code",
      "pod_name",
      "result_status",
    ]) ||
    !isNullableUuid(row.review_id) ||
    !isNullableUuid(row.reviewer_user_id) ||
    !isNullableString(row.reviewer_name) ||
    !isNullableString(row.reviewer_comment) ||
    !isNullableString(row.review_status) ||
    !isNullableString(row.submitted_at) ||
    !isNullableString(row.review_created_at) ||
    !isNullableString(row.review_updated_at) ||
    !Number.isInteger(row.eligible_days) ||
    row.eligible_days < 0 ||
    !Number.isInteger(row.scored_days) ||
    row.scored_days < 0 ||
    row.scored_days > row.eligible_days ||
    !isNullableFiniteNumber(row.daily_component_score) ||
    typeof row.daily_scoring_complete !== "boolean" ||
    typeof row.review_is_open !== "boolean" ||
    !isNullableIntegerInRange(row.work_quality_score, 0, 10) ||
    !isNullableIntegerInRange(row.role_capability_score, 0, 5) ||
    !isNullableIntegerInRange(row.deadline_delivery_score, 0, 5) ||
    !isNullableIntegerInRange(row.ownership_teamwork_score, 0, 5) ||
    !isNullableIntegerInRange(row.total_score, 0, 25) ||
    (row.review_status !== null &&
      !["DRAFT", "SUBMITTED"].includes(row.review_status))
  ) {
    throw new Error(SAFE_LEAD_REVIEW_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
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
    reviewerUserId: row.reviewer_user_id,
    reviewerName: row.reviewer_name,
    workQualityScore: row.work_quality_score,
    roleCapabilityScore: row.role_capability_score,
    deadlineDeliveryScore: row.deadline_delivery_score,
    ownershipTeamworkScore: row.ownership_teamwork_score,
    totalScore: row.total_score,
    reviewerComment: row.reviewer_comment,
    reviewStatus: row.review_status,
    submittedAt: row.submitted_at,
    reviewCreatedAt: row.review_created_at,
    reviewUpdatedAt: row.review_updated_at,
  };
}

export async function fetchLeadReviewTasks() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_LEAD_REVIEW_TASKS_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc("get_lead_review_tasks");

    if (error || !Array.isArray(data)) {
      throw new Error(SAFE_LEAD_REVIEW_TASKS_ERROR);
    }

    return data.map(mapLeadReviewTaskRow);
  } catch {
    throw new Error(SAFE_LEAD_REVIEW_TASKS_ERROR);
  }
}

export async function fetchCandidateLeadReview(candidateCycleId) {
  if (!isValidUuid(candidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_LEAD_REVIEW_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "get_candidate_lead_review",
      {
        p_candidate_cycle_id: candidateCycleId,
      }
    );

    if (error || !Array.isArray(data) || data.length !== 1) {
      throw new Error(SAFE_LEAD_REVIEW_ERROR);
    }

    return mapCandidateLeadReviewRow(data[0]);
  } catch {
    throw new Error(SAFE_LEAD_REVIEW_ERROR);
  }
}

export async function saveCandidateLeadReview(input) {
  if (!isRecord(input) || !isValidUuid(input.candidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  const {
    candidateCycleId,
    workQualityScore,
    roleCapabilityScore,
    deadlineDeliveryScore,
    ownershipTeamworkScore,
    reviewerComment,
    reviewStatus,
  } = input;

  if (!isNullableIntegerInRange(workQualityScore, 0, 10)) {
    throw new Error("Work Quality score must be between 0 and 10.");
  }

  if (!isNullableIntegerInRange(roleCapabilityScore, 0, 5)) {
    throw new Error("Role Capability score must be between 0 and 5.");
  }

  if (!isNullableIntegerInRange(deadlineDeliveryScore, 0, 5)) {
    throw new Error("Deadline Delivery score must be between 0 and 5.");
  }

  if (!isNullableIntegerInRange(ownershipTeamworkScore, 0, 5)) {
    throw new Error("Ownership and Teamwork score must be between 0 and 5.");
  }

  if (!["DRAFT", "SUBMITTED"].includes(reviewStatus)) {
    throw new Error("Review status must be DRAFT or SUBMITTED.");
  }

  if (
    reviewStatus === "SUBMITTED" &&
    [
      workQualityScore,
      roleCapabilityScore,
      deadlineDeliveryScore,
      ownershipTeamworkScore,
    ].some((score) => score === null)
  ) {
    throw new Error("All Lead Review scores are required for submission.");
  }

  const normalizedReviewerComment =
    reviewerComment === null || reviewerComment === undefined
      ? null
      : typeof reviewerComment === "string"
        ? reviewerComment.trim() || null
        : reviewerComment;

  if (
    !isNullableString(normalizedReviewerComment) ||
    (normalizedReviewerComment !== null &&
      normalizedReviewerComment.length > 2000)
  ) {
    throw new Error(
      "Reviewer comment must not exceed 2000 characters."
    );
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_SAVE_LEAD_REVIEW_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "save_candidate_lead_review",
      {
        p_candidate_cycle_id: candidateCycleId,
        p_work_quality_score: workQualityScore,
        p_role_capability_score: roleCapabilityScore,
        p_deadline_delivery_score: deadlineDeliveryScore,
        p_ownership_teamwork_score: ownershipTeamworkScore,
        p_reviewer_comment: normalizedReviewerComment,
        p_review_status: reviewStatus,
      }
    );

    if (error) {
      throw new Error(getSafeSaveLeadReviewMessage(error));
    }

    if (!isRecord(data)) {
      throw new Error(SAFE_SAVE_LEAD_REVIEW_ERROR);
    }

    return data;
  } catch (error) {
    throw new Error(getSafeSaveLeadReviewMessage(error), { cause: error });
  }
}
