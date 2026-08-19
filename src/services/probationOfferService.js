import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MID_PATTERN = /^JCF-[A-Z0-9]{3}-[A-Z0-9_]{1,2}-[0-9]{5}$/;
const SAFE_ACTION_ERROR =
  "Unable to pass probation and prepare the offer. Please try again.";
const JOB_STATUSES = new Set([
  "PENDING",
  "PROCESSING",
  "SUCCESS",
  "FAILED",
  "RETRY",
  "CANCELLED",
]);
const PREVIOUS_LIFECYCLE_STATUSES = new Set([
  "PROBATION_REVIEW",
  "PROBATION_PASSED",
]);

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidUuid(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export async function passProbationAndPrepareOffer(candidateId) {
  const normalizedCandidateId =
    typeof candidateId === "string" ? candidateId.trim().toLowerCase() : "";

  if (!isValidUuid(normalizedCandidateId)) {
    throw new Error("A valid candidate ID is required.");
  }

  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_ACTION_ERROR);
  }

  let result;

  try {
    result = await supabase.rpc("pass_probation_and_prepare_offer", {
      p_candidate_id: normalizedCandidateId,
    });
  } catch {
    throw new Error(SAFE_ACTION_ERROR);
  }

  if (!isRecord(result) || result.error) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  const response = result.data;

  if (
    !isRecord(response) ||
    !isValidUuid(response.candidateId) ||
    response.candidateId.toLowerCase() !== normalizedCandidateId ||
    response.lifecycleStatus !== "MID_GENERATED" ||
    typeof response.mid !== "string" ||
    !MID_PATTERN.test(response.mid) ||
    response.offerLetterNumber !== `OL-${response.mid}` ||
    !isValidUuid(response.jobId) ||
    typeof response.jobStatus !== "string" ||
    !JOB_STATUSES.has(response.jobStatus) ||
    typeof response.alreadyPrepared !== "boolean" ||
    (response.previousLifecycleStatus !== undefined &&
      !PREVIOUS_LIFECYCLE_STATUSES.has(response.previousLifecycleStatus))
  ) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  return {
    candidateId: response.candidateId,
    lifecycleStatus: response.lifecycleStatus,
    mid: response.mid,
    offerLetterNumber: response.offerLetterNumber,
    jobId: response.jobId,
    jobStatus: response.jobStatus,
    alreadyPrepared: response.alreadyPrepared,
    ...(response.previousLifecycleStatus !== undefined
      ? { previousLifecycleStatus: response.previousLifecycleStatus }
      : {}),
  };
}
