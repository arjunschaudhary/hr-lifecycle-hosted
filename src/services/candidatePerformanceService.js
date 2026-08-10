import { supabase } from "./supabaseClient";

const SAFE_HISTORY_ERROR = "Unable to load your performance history.";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const isNonEmptyString = (value) =>
  typeof value === "string" && value.trim().length > 0;

function mapPerformanceHistoryRow(row) {
  if (
    !isRecord(row) ||
    !isValidUuid(row.candidate_cycle_id) ||
    !isValidUuid(row.cycle_id) ||
    !isNonEmptyString(row.cycle_code) ||
    !isNonEmptyString(row.result_status)
  ) {
    throw new Error(SAFE_HISTORY_ERROR);
  }

  return {
    candidateCycleId: row.candidate_cycle_id,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    cycleNumber: row.cycle_number,
    cycleStartDate: row.cycle_start_date,
    cycleEndDate: row.cycle_end_date,
    cycleStatus: row.cycle_status,
    evaluationStartDate: row.evaluation_start_date,
    evaluationEndDate: row.evaluation_end_date,
    isPartialCycle: row.is_partial_cycle,
    eligibleDays: row.eligible_days,
    scoredDays: row.scored_days,
    dailyAverage: row.daily_average,
    dailyComponentScore: row.daily_component_score,
    leadScore: row.lead_score,
    hrScore: row.hr_score,
    exceptionalScore: row.exceptional_score,
    finalScore: row.final_score,
    performanceBand: row.performance_band,
    resultStatus: row.result_status,
    finalResultReady: row.final_result_ready,
    finalizedAt: row.finalized_at,
    assignmentCreatedAt: row.assignment_created_at,
  };
}

export async function fetchCurrentCandidatePerformanceHistory() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_HISTORY_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "get_current_candidate_performance_history"
    );

    if (error) {
      throw new Error(SAFE_HISTORY_ERROR);
    }

    if (!Array.isArray(data)) {
      throw new Error(SAFE_HISTORY_ERROR);
    }

    return data.map(mapPerformanceHistoryRow);
  } catch (err) {
    if (err instanceof Error && err.message === SAFE_HISTORY_ERROR) {
      throw err;
    }
    throw new Error(SAFE_HISTORY_ERROR, { cause: err });
  }
}
