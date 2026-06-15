export const candidateStatusGroups = {
  FORM_SUBMITTED: "Form Submitted",
  HR_REVIEW_PENDING: "HR Review Pending",
  HR_APPROVED_FOR_PROBATION: "HR Approved for Probation",
  PROBATION_INITIATED: "Probation Initiated",
  WELCOME_MAIL_SENT: "Welcome Mail Sent",
  IN_PROBATION: "In Probation",
  PROBATION_REVIEW: "Probation Review",
  PROBATION_PASSED: "Probation Passed",
  PROBATION_REJECTED: "Probation Rejected",
  PROBATION_EXTENDED: "Probation Extended",
  RECONSIDERATION: "Reconsideration",
  MID_GENERATED: "MID Generated",
  OFFER_LETTER_GENERATED: "Offer Letter Generated",
  OFFER_LETTER_SENT: "Offer Letter Sent",
  ACTIVE: "Active Intern",
  COMPLETED: "Completed",
  TERMINATED: "Terminated",
};

export const probationStatusGroups = {
  FORM_SUBMITTED: "Form Submitted",
  HR_REVIEW_PENDING: "HR Review Pending",
  HR_APPROVED_FOR_PROBATION: "HR Approved for Probation",
  PROBATION_INITIATED: "Probation Initiated",
  WELCOME_MAIL_SENT: "Welcome Mail Sent",
  IN_PROBATION: "In Probation",
  PROBATION_REVIEW: "Probation Review",
  PROBATION_PASSED: "Probation Passed",
  PROBATION_REJECTED: "Probation Rejected",
  PROBATION_EXTENDED: "Probation Extended",
  RECONSIDERATION: "Reconsideration",
};

export const offerStatusGroups = {
  NOT_STARTED: "Not Started",
  MID_GENERATED: "MID Generated",
  OFFER_LETTER_GENERATED: "Offer Letter Generated",
  OFFER_LETTER_SENT: "Offer Letter Sent",
  CANCELLED: "Cancelled",
};

export const signedOfferStatusGroups = {
  NOT_SUBMITTED: "Not Submitted",
  SUBMITTED: "Submitted",
  VERIFIED: "Verified",
  REJECTED: "Rejected",
  RESUBMISSION_REQUIRED: "Resubmission Required",
};

export const matchStatusGroups = {
  NOT_CHECKED: "Not Checked",
  MATCHED: "Matched",
  MISMATCH: "Mismatch",
  MISMATCH_REVIEW: "Mismatch Review",
};

export function getStatusLabel(status, statusGroup = {}) {
  return statusGroup[status] || status || "Unknown";
}

export function isProbationActive(status) {
  return [
    "PROBATION_INITIATED",
    "WELCOME_MAIL_SENT",
    "IN_PROBATION",
    "PROBATION_REVIEW",
    "PROBATION_EXTENDED",
    "RECONSIDERATION",
  ].includes(status);
}

export function isOfferLetterInProgress(status) {
  return ["MID_GENERATED", "OFFER_LETTER_GENERATED"].includes(status);
}

export function isOfferLetterSent(status) {
  return status === "OFFER_LETTER_SENT";
}

export function needsSignedOfferReview(status) {
  return ["SUBMITTED", "RESUBMISSION_REQUIRED"].includes(status);
}