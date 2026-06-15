export function canReviewCandidateForm(candidate) {
  if (!candidate) return false;

  return candidate.currentStatus === "HR_REVIEW_PENDING";
}

export function canApproveForProbation(candidate) {
  if (!candidate) return false;

  return candidate.currentStatus === "HR_REVIEW_PENDING";
}

export function canInitiateProbation(candidate) {
  if (!candidate) return false;

  return candidate.currentStatus === "HR_APPROVED_FOR_PROBATION";
}

export function canReviewProbation(probationAttempt) {
  if (!probationAttempt) return false;

  return [
    "IN_PROBATION",
    "PROBATION_REVIEW",
    "PROBATION_EXTENDED",
    "RECONSIDERATION",
  ].includes(probationAttempt.status);
}

export function canPassProbation(probationAttempt) {
  if (!probationAttempt) return false;

  return [
    "IN_PROBATION",
    "PROBATION_REVIEW",
    "PROBATION_EXTENDED",
    "RECONSIDERATION",
  ].includes(probationAttempt.status);
}

export function canRejectProbation(probationAttempt) {
  if (!probationAttempt) return false;

  return [
    "IN_PROBATION",
    "PROBATION_REVIEW",
    "PROBATION_EXTENDED",
    "RECONSIDERATION",
  ].includes(probationAttempt.status);
}

export function canExtendProbation(probationAttempt) {
  if (!probationAttempt) return false;

  return ["IN_PROBATION", "PROBATION_REVIEW"].includes(probationAttempt.status);
}

export function shouldStartOfferLetterProcess(probationAttempt) {
  if (!probationAttempt) return false;

  return probationAttempt.status === "PROBATION_PASSED";
}

export function canGenerateMID(probationAttempt, offer) {
  if (!probationAttempt) return false;

  return probationAttempt.status === "PROBATION_PASSED" && !offer?.mid;
}

export function canGenerateOfferLetter(offer) {
  if (!offer) return false;

  return ["MID_GENERATED", "OFFER_LETTER_GENERATED"].includes(
    offer.offerStatus
  );
}

export function canSendOfferLetter(offer) {
  if (!offer) return false;

  return offer.offerStatus === "OFFER_LETTER_GENERATED";
}

export function shouldActivateIntern(offer) {
  if (!offer) return false;

  return offer.offerStatus === "OFFER_LETTER_SENT";
}

export function isActiveIntern(candidate) {
  if (!candidate) return false;

  return candidate.currentStatus === "ACTIVE";
}

export function canSubmitSignedOffer(candidate, offer) {
  if (!candidate || !offer) return false;

  return (
    candidate.currentStatus === "ACTIVE" &&
    offer.offerStatus === "OFFER_LETTER_SENT"
  );
}

export function canVerifySignedOffer(signedOffer) {
  if (!signedOffer) return false;

  return ["SUBMITTED", "RESUBMISSION_REQUIRED"].includes(signedOffer.status);
}

export function canRejectSignedOffer(signedOffer) {
  if (!signedOffer) return false;

  return ["SUBMITTED", "RESUBMISSION_REQUIRED"].includes(signedOffer.status);
}

export function signedOfferHasMismatch(signedOffer) {
  if (!signedOffer) return false;

  return (
    signedOffer.emailMatchStatus === "MISMATCH" ||
    signedOffer.phoneMatchStatus === "MISMATCH"
  );
}

export function doesSignedOfferBlockActiveStatus() {
  return false;
}

export function getNextCandidateStatusAfterProbationPassed() {
  return "OFFER_LETTER_SENT";
}

export function getNextCandidateStatusAfterOfferLetterSent() {
  return "ACTIVE";
}