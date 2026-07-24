import { supabase } from "./supabaseClient";

const SAFE_CYCLE_OVERVIEW_ERROR = "Unable to load performance cycles.";
const SAFE_CANDIDATE_LIST_ERROR =
  "Unable to load candidate performance records.";
const SAFE_ACTION_QUEUE_ERROR =
  "Unable to load performance action items.";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const CYCLE_OVERVIEW_COLUMNS = [
  "cycle_id",
  "cycle_code",
  "cycle_number",
  "start_date",
  "end_date",
  "review_open_date",
  "lock_date",
  "cycle_status",
  "assignment_count",
  "pod_count",
  "partial_cycle_count",
  "total_eligible_days",
  "total_scored_days",
  "scoring_completion_percent",
  "pending_count",
  "daily_scoring_count",
  "awaiting_reviews_count",
  "ready_to_calculate_count",
  "candidate_review_count",
  "finalized_count",
  "locked_count",
  "daily_summary_ready_count",
  "lead_review_ready_count",
  "hr_review_ready_count",
  "review_summary_ready_count",
  "exceptional_summary_ready_count",
  "final_result_count",
  "average_final_score",
  "cycle_created_at",
  "cycle_updated_at",
];

const CANDIDATE_LIST_COLUMNS = [
  "candidate_cycle_id",
  "cycle_id",
  "cycle_code",
  "cycle_number",
  "cycle_start_date",
  "cycle_end_date",
  "review_open_date",
  "lock_date",
  "cycle_status",
  "candidate_id",
  "full_name",
  "email",
  "applied_role",
  "role_code",
  "department",
  "pod_id",
  "pod_code",
  "pod_name",
  "evaluation_start_date",
  "evaluation_end_date",
  "is_partial_cycle",
  "eligible_days",
  "scored_days",
  "remaining_scoring_days",
  "scoring_completion_percent",
  "daily_average",
  "daily_component_score",
  "lead_score",
  "hr_score",
  "exceptional_score",
  "final_score",
  "performance_band",
  "result_status",
  "daily_summary_ready",
  "lead_review_ready",
  "hr_review_ready",
  "exceptional_summary_ready",
  "all_components_ready",
  "final_result_ready",
  "ready_for_finalization",
  "is_protected",
  "calculated_at",
  "finalized_at",
  "assignment_created_at",
  "assignment_updated_at",
];

const ACTION_QUEUE_COLUMNS = [
  "action_key",
  "action_code",
  "action_label",
  "action_owner_scope",
  "candidate_cycle_id",
  "candidate_id",
  "full_name",
  "email",
  "applied_role",
  "role_code",
  "pod_id",
  "pod_code",
  "pod_name",
  "cycle_id",
  "cycle_code",
  "cycle_number",
  "cycle_start_date",
  "cycle_end_date",
  "evaluation_start_date",
  "evaluation_end_date",
  "review_open_date",
  "lock_date",
  "result_status",
  "eligible_days",
  "scored_days",
  "remaining_scoring_days",
  "pending_exceptional_count",
  "due_date",
  "days_until_due",
  "is_overdue",
  "action_reason",
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

function mapCycleOverviewRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, CYCLE_OVERVIEW_COLUMNS) ||
    !hasValidUuids(row, ["cycle_id"]) ||
    !hasNonEmptyStrings(row, ["cycle_code", "cycle_status"])
  ) {
    throw new Error(SAFE_CYCLE_OVERVIEW_ERROR);
  }

  return {
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    cycleNumber: row.cycle_number,
    startDate: row.start_date,
    endDate: row.end_date,
    reviewOpenDate: row.review_open_date,
    lockDate: row.lock_date,
    cycleStatus: row.cycle_status,
    assignmentCount: row.assignment_count,
    podCount: row.pod_count,
    partialCycleCount: row.partial_cycle_count,
    totalEligibleDays: row.total_eligible_days,
    totalScoredDays: row.total_scored_days,
    scoringCompletionPercent: row.scoring_completion_percent,
    pendingCount: row.pending_count,
    dailyScoringCount: row.daily_scoring_count,
    awaitingReviewsCount: row.awaiting_reviews_count,
    readyToCalculateCount: row.ready_to_calculate_count,
    candidateReviewCount: row.candidate_review_count,
    finalizedCount: row.finalized_count,
    lockedCount: row.locked_count,
    dailySummaryReadyCount: row.daily_summary_ready_count,
    leadReviewReadyCount: row.lead_review_ready_count,
    hrReviewReadyCount: row.hr_review_ready_count,
    reviewSummaryReadyCount: row.review_summary_ready_count,
    exceptionalSummaryReadyCount: row.exceptional_summary_ready_count,
    finalResultCount: row.final_result_count,
    averageFinalScore: row.average_final_score,
    cycleCreatedAt: row.cycle_created_at,
    cycleUpdatedAt: row.cycle_updated_at,
  };
}

function mapCandidatePerformanceRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, CANDIDATE_LIST_COLUMNS) ||
    !hasValidUuids(row, [
      "candidate_cycle_id",
      "cycle_id",
      "candidate_id",
      "pod_id",
    ]) ||
    !hasNonEmptyStrings(row, [
      "cycle_code",
      "full_name",
      "email",
      "pod_code",
      "pod_name",
      "result_status",
    ])
  ) {
    throw new Error(SAFE_CANDIDATE_LIST_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    cycleNumber: row.cycle_number,
    cycleStartDate: row.cycle_start_date,
    cycleEndDate: row.cycle_end_date,
    reviewOpenDate: row.review_open_date,
    lockDate: row.lock_date,
    cycleStatus: row.cycle_status,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    appliedRole: row.applied_role,
    roleCode: row.role_code,
    department: row.department,
    podId: row.pod_id,
    podCode: row.pod_code,
    podName: row.pod_name,
    evaluationStartDate: row.evaluation_start_date,
    evaluationEndDate: row.evaluation_end_date,
    isPartialCycle: row.is_partial_cycle,
    eligibleDays: row.eligible_days,
    scoredDays: row.scored_days,
    remainingScoringDays: row.remaining_scoring_days,
    scoringCompletionPercent: row.scoring_completion_percent,
    dailyAverage: row.daily_average,
    dailyComponentScore: row.daily_component_score,
    leadScore: row.lead_score,
    hrScore: row.hr_score,
    exceptionalScore: row.exceptional_score,
    finalScore: row.final_score,
    performanceBand: row.performance_band,
    resultStatus: row.result_status,
    dailySummaryReady: row.daily_summary_ready,
    leadReviewReady: row.lead_review_ready,
    hrReviewReady: row.hr_review_ready,
    exceptionalSummaryReady: row.exceptional_summary_ready,
    allComponentsReady: row.all_components_ready,
    finalResultReady: row.final_result_ready,
    readyForFinalization: row.ready_for_finalization,
    isProtected: row.is_protected,
    calculatedAt: row.calculated_at,
    finalizedAt: row.finalized_at,
    assignmentCreatedAt: row.assignment_created_at,
    assignmentUpdatedAt: row.assignment_updated_at,
  };
}

function mapActionQueueRow(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, ACTION_QUEUE_COLUMNS) ||
    !hasValidUuids(row, [
      "candidate_cycle_id",
      "candidate_id",
      "pod_id",
      "cycle_id",
    ]) ||
    !hasNonEmptyStrings(row, [
      "action_key",
      "action_code",
      "action_label",
      "action_owner_scope",
      "full_name",
      "email",
      "pod_code",
      "pod_name",
      "cycle_code",
      "result_status",
      "action_reason",
    ])
  ) {
    throw new Error(SAFE_ACTION_QUEUE_ERROR);
  }

  return {
    actionKey: row.action_key,
    actionCode: row.action_code,
    actionLabel: row.action_label,
    actionOwnerScope: row.action_owner_scope,
    candidateCycleId: row.candidate_cycle_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    appliedRole: row.applied_role,
    roleCode: row.role_code,
    podId: row.pod_id,
    podCode: row.pod_code,
    podName: row.pod_name,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    cycleNumber: row.cycle_number,
    cycleStartDate: row.cycle_start_date,
    cycleEndDate: row.cycle_end_date,
    evaluationStartDate: row.evaluation_start_date,
    evaluationEndDate: row.evaluation_end_date,
    reviewOpenDate: row.review_open_date,
    lockDate: row.lock_date,
    resultStatus: row.result_status,
    eligibleDays: row.eligible_days,
    scoredDays: row.scored_days,
    remainingScoringDays: row.remaining_scoring_days,
    pendingExceptionalCount: row.pending_exceptional_count,
    dueDate: row.due_date,
    daysUntilDue: row.days_until_due,
    isOverdue: row.is_overdue,
    actionReason: row.action_reason,
  };
}

async function fetchRpcRows(rpcName, mapRow, safeErrorMessage) {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(safeErrorMessage);
  }

  try {
    const { data, error } = await supabase.rpc(rpcName);

    if (error || !Array.isArray(data)) {
      throw new Error(safeErrorMessage);
    }

    return data.map(mapRow);
  } catch {
    throw new Error(safeErrorMessage);
  }
}

export async function fetchPerformanceCycleOverview() {
  return fetchRpcRows(
    "get_performance_cycle_overview",
    mapCycleOverviewRow,
    SAFE_CYCLE_OVERVIEW_ERROR
  );
}

export async function fetchCandidatePerformanceList() {
  return fetchRpcRows(
    "get_candidate_performance_list",
    mapCandidatePerformanceRow,
    SAFE_CANDIDATE_LIST_ERROR
  );
}

export async function fetchPerformanceActionQueue() {
  return fetchRpcRows(
    "get_performance_action_queue",
    mapActionQueueRow,
    SAFE_ACTION_QUEUE_ERROR
  );
}
