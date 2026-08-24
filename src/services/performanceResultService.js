import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const RESULT_STATUSES = new Set([
  "PENDING",
  "DAILY_SCORING",
  "AWAITING_REVIEWS",
  "READY_TO_CALCULATE",
  "CANDIDATE_REVIEW",
  "FINALIZED",
  "LOCKED",
  "NOT_EVALUATED",
]);

const SAFE_EXCEPTIONAL_SCORE_ERROR =
  "Unable to save the Exceptional Score.";
const SAFE_FINALIZATION_ERROR =
  "Unable to finalize the performance result.";
const SAFE_FINALIZATION_ACCESS_ERROR =
  "Unable to verify performance finalization access.";

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const normalizeUuid = (value) =>
  typeof value === "string" ? value.trim().toLowerCase() : "";

const isNullableFiniteNumber = (value) =>
  value === null || (typeof value === "number" && Number.isFinite(value));

const isNullableString = (value) =>
  value === null || typeof value === "string";

const getSingleRow = (data, safeErrorMessage) => {
  if (!Array.isArray(data) || data.length !== 1 || !isRecord(data[0])) {
    throw new Error(safeErrorMessage);
  }

  return data[0];
};

export async function getCurrentUserHasExactHrSiteConnectLeadRole() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_FINALIZATION_ACCESS_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc("current_user_has_role", {
      p_role_slug: "HR_SITE_CONNECT_LEAD",
    });

    if (error || typeof data !== "boolean") {
      throw new Error(SAFE_FINALIZATION_ACCESS_ERROR);
    }

    return data;
  } catch {
    throw new Error(SAFE_FINALIZATION_ACCESS_ERROR);
  }
}

export async function saveCandidateExceptionalScore(
  candidateCycleId,
  exceptionalScore,
) {
  const normalizedCandidateCycleId = normalizeUuid(candidateCycleId);

  if (!isValidUuid(normalizedCandidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  if (
    typeof exceptionalScore !== "number" ||
    !Number.isFinite(exceptionalScore) ||
    exceptionalScore < 0 ||
    exceptionalScore > 10
  ) {
    throw new Error("Exceptional Score must be between 0 and 10.");
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_EXCEPTIONAL_SCORE_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "save_candidate_exceptional_score",
      {
        p_candidate_cycle_id: normalizedCandidateCycleId,
        p_exceptional_score: exceptionalScore,
      },
    );

    if (error) {
      throw new Error(SAFE_EXCEPTIONAL_SCORE_ERROR);
    }

    const row = getSingleRow(data, SAFE_EXCEPTIONAL_SCORE_ERROR);

    if (
      !isValidUuid(row.candidate_cycle_id) ||
      row.candidate_cycle_id.toLowerCase() !== normalizedCandidateCycleId ||
      !isNullableFiniteNumber(row.previous_exceptional_score) ||
      typeof row.exceptional_score !== "number" ||
      !Number.isFinite(row.exceptional_score) ||
      row.exceptional_score < 0 ||
      row.exceptional_score > 10 ||
      typeof row.result_status !== "string" ||
      !RESULT_STATUSES.has(row.result_status) ||
      !isNullableFiniteNumber(row.final_score) ||
      !isNullableString(row.performance_band) ||
      !isNullableString(row.calculated_at)
    ) {
      throw new Error(SAFE_EXCEPTIONAL_SCORE_ERROR);
    }

    return {
      candidateCycleId: row.candidate_cycle_id,
      previousExceptionalScore: row.previous_exceptional_score,
      exceptionalScore: row.exceptional_score,
      resultStatus: row.result_status,
      finalScore: row.final_score,
      performanceBand: row.performance_band,
      calculatedAt: row.calculated_at,
    };
  } catch {
    throw new Error(SAFE_EXCEPTIONAL_SCORE_ERROR);
  }
}

export async function finalizeAndLockCandidatePerformance(candidateCycleId) {
  const normalizedCandidateCycleId = normalizeUuid(candidateCycleId);

  if (!isValidUuid(normalizedCandidateCycleId)) {
    throw new Error("A valid candidate performance cycle is required.");
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_FINALIZATION_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(
      "finalize_and_lock_candidate_performance",
      {
        p_candidate_cycle_id: normalizedCandidateCycleId,
      },
    );

    if (error) {
      throw new Error(SAFE_FINALIZATION_ERROR);
    }

    const row = getSingleRow(data, SAFE_FINALIZATION_ERROR);

    if (
      !isValidUuid(row.candidate_cycle_id) ||
      row.candidate_cycle_id.toLowerCase() !== normalizedCandidateCycleId ||
      row.result_status !== "LOCKED" ||
      typeof row.final_score !== "number" ||
      !Number.isFinite(row.final_score) ||
      typeof row.performance_band !== "string" ||
      !row.performance_band.trim() ||
      typeof row.finalized_at !== "string" ||
      !row.finalized_at ||
      typeof row.locked_at !== "string" ||
      !row.locked_at
    ) {
      throw new Error(SAFE_FINALIZATION_ERROR);
    }

    return {
      candidateCycleId: row.candidate_cycle_id,
      resultStatus: row.result_status,
      finalScore: row.final_score,
      performanceBand: row.performance_band,
      finalizedAt: row.finalized_at,
      lockedAt: row.locked_at,
    };
  } catch {
    throw new Error(SAFE_FINALIZATION_ERROR);
  }
}
