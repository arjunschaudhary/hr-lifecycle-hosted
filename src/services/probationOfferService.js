import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MID_PATTERN = /^JCF-[A-Z0-9]{3}-[A-Z0-9_]{1,2}-[0-9]{5}$/;
const SAFE_ACTION_ERROR =
  "Unable to pass probation and prepare the offer. Please try again.";
const SAFE_AUTOMATION_INCOMPLETE_MESSAGE =
  "Offer automation has not completed yet.";
const SAFE_AUTOMATION_MANUAL_REVIEW_MESSAGE =
  "Offer email delivery requires manual verification before retrying.";
const MANUAL_REVIEW_MARKER =
  "Check the sender Sent folder before retrying";
const WORKER_SUCCESS_MESSAGE =
  "Offer letter generated, sent, and candidate activated.";
const OFFER_LETTER_NUMBER_PATTERN =
  /^OL-JCF-[A-Z0-9]{3}-[A-Z0-9_]{1,2}-[0-9]{5}$/;
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
const OFFER_AUTOMATION_FAILURE_KINDS = Object.freeze({
  INCOMPLETE: "INCOMPLETE",
  MANUAL_REVIEW: "MANUAL_REVIEW",
});

class OfferAutomationError extends Error {
  constructor(kind, message) {
    super(message);
    this.name = "OfferAutomationError";
    this.kind = kind;
  }
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidUuid(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function isManualReviewMessage(value) {
  return typeof value === "string" && value.includes(MANUAL_REVIEW_MARKER);
}

async function requiresManualReview(error) {
  const context = isRecord(error) ? error.context : null;

  if (context instanceof Response) {
    try {
      const responseBody = await context.clone().json();

      if (
        isRecord(responseBody) &&
        isManualReviewMessage(responseBody.error)
      ) {
        return true;
      }
    } catch {
      // Fall through to the safe direct-message check.
    }
  }

  return isRecord(error) && isManualReviewMessage(error.message);
}

function createOfferAutomationError(kind) {
  return new OfferAutomationError(
    kind,
    kind === OFFER_AUTOMATION_FAILURE_KINDS.MANUAL_REVIEW
      ? SAFE_AUTOMATION_MANUAL_REVIEW_MESSAGE
      : SAFE_AUTOMATION_INCOMPLETE_MESSAGE
  );
}

export function getOfferAutomationFailureKind(error) {
  return error instanceof OfferAutomationError
    ? error.kind
    : OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE;
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

export async function processQueuedOfferLetter(candidateId) {
  const normalizedCandidateId =
    typeof candidateId === "string" ? candidateId.trim().toLowerCase() : "";

  if (!isValidUuid(normalizedCandidateId)) {
    throw createOfferAutomationError(
      OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE
    );
  }

  if (!supabase || typeof supabase.functions?.invoke !== "function") {
    throw createOfferAutomationError(
      OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE
    );
  }

  let result;

  try {
    result = await supabase.functions.invoke("process-offer-letter", {
      body: {
        candidateId: normalizedCandidateId,
      },
    });
  } catch {
    throw createOfferAutomationError(
      OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE
    );
  }

  if (!isRecord(result)) {
    throw createOfferAutomationError(
      OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE
    );
  }

  if (result.error) {
    const failureKind = await requiresManualReview(result.error)
      ? OFFER_AUTOMATION_FAILURE_KINDS.MANUAL_REVIEW
      : OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE;

    throw createOfferAutomationError(failureKind);
  }

  const response = result.data;

  if (
    !isRecord(response) ||
    response.success !== true ||
    !isValidUuid(response.candidateId) ||
    response.candidateId.toLowerCase() !== normalizedCandidateId ||
    !isValidUuid(response.offerLetterId) ||
    typeof response.offerLetterNumber !== "string" ||
    !OFFER_LETTER_NUMBER_PATTERN.test(response.offerLetterNumber) ||
    !isValidUuid(response.jobId) ||
    response.jobStatus !== "SUCCESS" ||
    response.lifecycleStatus !== "ACTIVE" ||
    typeof response.alreadyCompleted !== "boolean" ||
    response.message !== WORKER_SUCCESS_MESSAGE
  ) {
    throw createOfferAutomationError(
      isRecord(response) && isManualReviewMessage(response.error)
        ? OFFER_AUTOMATION_FAILURE_KINDS.MANUAL_REVIEW
        : OFFER_AUTOMATION_FAILURE_KINDS.INCOMPLETE
    );
  }

  return {
    success: true,
    candidateId: response.candidateId,
    offerLetterId: response.offerLetterId,
    offerLetterNumber: response.offerLetterNumber,
    jobId: response.jobId,
    jobStatus: response.jobStatus,
    lifecycleStatus: response.lifecycleStatus,
    alreadyCompleted: response.alreadyCompleted,
  };
}
