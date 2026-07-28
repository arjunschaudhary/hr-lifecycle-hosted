import { supabase } from "./supabaseClient";

const SAFE_LEAD_REVIEW_TASKS_ERROR =
  "Unable to load Lead Review tasks.";

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
