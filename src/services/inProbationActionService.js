import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SAFE_ACTION_ERROR =
  "Unable to mark the candidate in probation. Please try again.";
const JOB_STATUSES = new Set([
  "PENDING",
  "PROCESSING",
  "SUCCESS",
  "FAILED",
  "RETRY",
  "CANCELLED",
]);
const PERFORMANCE_OUTCOMES = new Set([
  "PERFORMANCE_ASSIGNED",
  "PERFORMANCE_PENDING_POD",
  "PERFORMANCE_PENDING_CYCLE",
  "PERFORMANCE_FAILED",
]);
const KNOWN_FUNCTION_MESSAGES = new Set([
  "A valid candidate ID is required.",
  "Your session is invalid or expired.",
  "You do not have permission to mark this candidate in probation.",
  "Candidate lifecycle record was not found.",
  "Candidate has multiple lifecycle records.",
  "Candidate probation start date is required.",
  "Candidate probation start date cannot be in the future.",
  "Candidate lifecycle status must be WELCOME_MAIL_SENT.",
  "Candidate lifecycle changed during processing.",
  "Performance-assignment job state is inconsistent.",
  "Unable to mark the candidate in probation.",
  "Unable to confirm the in-probation transition.",
  "In-probation automation is not configured.",
]);

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidUuid(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function getKnownMessage(value) {
  if (typeof value !== "string") {
    return null;
  }

  const message = value.trim();
  return KNOWN_FUNCTION_MESSAGES.has(message) ? message : null;
}

async function getSafeFunctionErrorMessage(error) {
  const context = isRecord(error) ? error.context : null;

  if (context instanceof Response) {
    try {
      const responseBody = await context.clone().json();
      const responseMessage = isRecord(responseBody)
        ? getKnownMessage(responseBody.error)
        : null;

      if (responseMessage) {
        return responseMessage;
      }
    } catch {
      // Use only allow-listed direct messages or the generic fallback.
    }
  }

  const directMessage = isRecord(error)
    ? getKnownMessage(error.message)
    : null;

  return directMessage ?? SAFE_ACTION_ERROR;
}

export async function markCandidateInProbation(candidateId) {
  const normalizedCandidateId =
    typeof candidateId === "string" ? candidateId.trim().toLowerCase() : "";

  if (!isValidUuid(normalizedCandidateId)) {
    throw new Error("A valid candidate ID is required.");
  }

  if (!supabase || typeof supabase.functions?.invoke !== "function") {
    throw new Error(SAFE_ACTION_ERROR);
  }

  let result;

  try {
    result = await supabase.functions.invoke(
      "mark-candidate-in-probation",
      {
        body: {
          candidateId: normalizedCandidateId,
        },
      },
    );
  } catch {
    throw new Error(SAFE_ACTION_ERROR);
  }

  if (result.error) {
    throw new Error(await getSafeFunctionErrorMessage(result.error));
  }

  const response = result.data;

  if (
    !isRecord(response) ||
    response.success !== true ||
    !isValidUuid(response.candidateId) ||
    response.candidateId.toLowerCase() !== normalizedCandidateId ||
    response.lifecycleStatus !== "IN_PROBATION" ||
    typeof response.transitionCompleted !== "boolean" ||
    !isValidUuid(response.jobId) ||
    typeof response.jobStatus !== "string" ||
    !JOB_STATUSES.has(response.jobStatus) ||
    typeof response.performanceOutcome !== "string" ||
    !PERFORMANCE_OUTCOMES.has(response.performanceOutcome) ||
    typeof response.performanceMessage !== "string" ||
    !response.performanceMessage.trim()
  ) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  if (
    response.cycleId !== undefined &&
    !isValidUuid(response.cycleId)
  ) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  if (
    response.assignmentId !== undefined &&
    !isValidUuid(response.assignmentId)
  ) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  if (
    response.eligibleDays !== undefined &&
    (!Number.isInteger(response.eligibleDays) ||
      response.eligibleDays < 0)
  ) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  return {
    success: true,
    candidateId: response.candidateId,
    lifecycleStatus: response.lifecycleStatus,
    transitionCompleted: response.transitionCompleted,
    jobId: response.jobId,
    jobStatus: response.jobStatus,
    performanceOutcome: response.performanceOutcome,
    performanceMessage: response.performanceMessage.trim(),
    cycleId: response.cycleId,
    assignmentId: response.assignmentId,
    eligibleDays: response.eligibleDays,
  };
}
