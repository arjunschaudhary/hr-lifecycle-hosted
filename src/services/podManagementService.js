import { supabase } from "./supabaseClient";

const SAFE_READ_ERROR = "Unable to load Pod Management data.";
const SAFE_WRITE_ERROR = "Unable to complete the Pod Management operation.";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const POD_COLUMNS = [
  "pod_id",
  "pod_code",
  "pod_name",
  "description",
  "is_active",
  "active_candidate_count",
  "active_pod_lead_count",
  "active_tech_lead_count",
  "current_pod_leads",
  "current_tech_leads",
  "created_at",
  "updated_at",
];

const MEMBERSHIP_COLUMNS = [
  "membership_id",
  "pod_id",
  "candidate_id",
  "user_id",
  "member_name",
  "member_email",
  "membership_type",
  "effective_from",
  "effective_to",
  "is_active",
  "assigned_by",
  "assigned_by_name",
  "created_at",
  "updated_at",
];

const CANDIDATE_COLUMNS = [
  "candidate_id",
  "full_name",
  "email",
  "applied_role",
  "mid",
  "lifecycle_status",
  "active_pod_id",
  "active_pod_code",
  "portal_account_status",
];

const WAITING_COLUMNS = [
  "candidate_id",
  "full_name",
  "email",
  "lifecycle_status",
  "probation_start_date",
  "required_evaluation_start_date",
  "performance_job_id",
  "performance_job_status",
  "performance_job_error",
  "has_active_portal_account",
];

const HR_REVIEWER_COLUMNS = [
  "user_id",
  "full_name",
  "email",
  "active_pod_count",
  "active_pod_codes",
];

const WRITE_OPERATIONS = new Set([
  "CREATE_POD",
  "UPDATE_POD",
  "ASSIGN_CANDIDATE",
  "ASSIGN_LEAD",
  "ASSIGN_HR_REVIEWER",
  "END_MEMBERSHIP",
]);

const SAFE_FUNCTION_MESSAGES = new Set([
  "Pod Management is not configured.",
  "Authentication is required.",
  "Pod Management access is not permitted.",
  "Pod Management request fields are invalid.",
  "Pod Management operation is not supported.",
  "Pod creation values are invalid.",
  "Pod update values are invalid.",
  "Candidate pod assignment values are invalid.",
  "Lead assignment values are invalid.",
  "Membership end values are invalid.",
  "Pod code already exists.",
  "Pod code is invalid.",
  "Pod name is invalid.",
  "Pod description is too long.",
  "Pod was not found.",
  "Pod update values are required.",
  "Pod cannot be deactivated while active memberships remain.",
  "Candidate, pod, and effective date are required.",
  "Candidate or pod was not found.",
  "Candidates cannot be assigned to an inactive pod.",
  "Candidate already has an active membership in this pod.",
  "Transfer date must be after the current membership start date.",
  "Candidate pod membership dates overlap an existing membership.",
  "Candidate, pod, lead type, and effective date are required.",
  "Lead type must be POD_LEAD or TECH_LEAD.",
  "Candidate was not found.",
  "Active pod was not found.",
  "Candidate portal user is not active.",
  "Candidate role is not active for the mapped portal user.",
  "Lead membership dates overlap an existing lead assignment in this pod.",
  "Required candidate portal account or active role was not found.",
  "HR Psyconnect reviewer assignment values are invalid.",
  "HR Psyconnect reviewers cannot be assigned to an inactive pod.",
  "HR Psyconnect reviewer was not found.",
  "Target user does not have active HR_SITE_CONNECT access.",
  "Pod already has an active HR Psyconnect reviewer. End the current membership before assigning another.",
  "HR Psyconnect reviewer membership dates overlap an existing assignment in this pod.",
  "Membership and end date are required.",
  "Pod membership is already inactive.",
  "Membership end date cannot be earlier than its start date.",
  "Pod membership was not found.",
]);

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const isNonEmptyString = (value) =>
  typeof value === "string" && value.trim().length > 0;

const isNullableString = (value) =>
  value === null || typeof value === "string";

const isNullableUuid = (value) => value === null || isValidUuid(value);

const isNonNegativeInteger = (value) =>
  Number.isInteger(value) && value >= 0;

const hasCompleteShape = (row, columns) =>
  columns.every((column) =>
    Object.prototype.hasOwnProperty.call(row, column)
  );

function mapLeadSummary(value) {
  if (!Array.isArray(value)) {
    throw new Error(SAFE_READ_ERROR);
  }

  return value.map((lead) => {
    if (
      !isRecord(lead) ||
      !isValidUuid(lead.userId) ||
      !isNonEmptyString(lead.name)
    ) {
      throw new Error(SAFE_READ_ERROR);
    }

    return { userId: lead.userId, name: lead.name.trim() };
  });
}

function mapPod(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, POD_COLUMNS) ||
    !isValidUuid(row.pod_id) ||
    !isNonEmptyString(row.pod_code) ||
    !isNonEmptyString(row.pod_name) ||
    !isNullableString(row.description) ||
    typeof row.is_active !== "boolean" ||
    !isNonNegativeInteger(row.active_candidate_count) ||
    !isNonNegativeInteger(row.active_pod_lead_count) ||
    !isNonNegativeInteger(row.active_tech_lead_count) ||
    !isNullableString(row.created_at) ||
    !isNullableString(row.updated_at)
  ) {
    throw new Error(SAFE_READ_ERROR);
  }

  return {
    podId: row.pod_id,
    podCode: row.pod_code,
    podName: row.pod_name,
    description: row.description,
    isActive: row.is_active,
    activeCandidateCount: row.active_candidate_count,
    activePodLeadCount: row.active_pod_lead_count,
    activeTechLeadCount: row.active_tech_lead_count,
    currentPodLeads: mapLeadSummary(row.current_pod_leads),
    currentTechLeads: mapLeadSummary(row.current_tech_leads),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapMembership(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, MEMBERSHIP_COLUMNS) ||
    !isValidUuid(row.membership_id) ||
    !isValidUuid(row.pod_id) ||
    !isNullableUuid(row.candidate_id) ||
    !isNullableUuid(row.user_id) ||
    !isNonEmptyString(row.member_name) ||
    !isNullableString(row.member_email) ||
    !isNonEmptyString(row.membership_type) ||
    !isNonEmptyString(row.effective_from) ||
    !isNullableString(row.effective_to) ||
    typeof row.is_active !== "boolean" ||
    !isNullableUuid(row.assigned_by) ||
    !isNullableString(row.assigned_by_name) ||
    !isNullableString(row.created_at) ||
    !isNullableString(row.updated_at) ||
    (row.candidate_id === null && row.user_id === null) ||
    (row.candidate_id !== null && row.user_id !== null)
  ) {
    throw new Error(SAFE_READ_ERROR);
  }

  return {
    membershipId: row.membership_id,
    podId: row.pod_id,
    candidateId: row.candidate_id,
    userId: row.user_id,
    memberName: row.member_name,
    memberEmail: row.member_email,
    membershipType: row.membership_type,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    isActive: row.is_active,
    assignedBy: row.assigned_by,
    assignedByName: row.assigned_by_name,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapCandidate(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, CANDIDATE_COLUMNS) ||
    !isValidUuid(row.candidate_id) ||
    !isNonEmptyString(row.full_name) ||
    !isNonEmptyString(row.email) ||
    !isNullableString(row.applied_role) ||
    !isNullableString(row.mid) ||
    !isNullableString(row.lifecycle_status) ||
    !isNullableUuid(row.active_pod_id) ||
    !isNullableString(row.active_pod_code) ||
    !isNullableString(row.portal_account_status)
  ) {
    throw new Error(SAFE_READ_ERROR);
  }

  return {
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    appliedRole: row.applied_role,
    mid: row.mid,
    lifecycleStatus: row.lifecycle_status,
    activePodId: row.active_pod_id,
    activePodCode: row.active_pod_code,
    portalAccountStatus: row.portal_account_status,
  };
}

function mapWaitingCandidate(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, WAITING_COLUMNS) ||
    !isValidUuid(row.candidate_id) ||
    !isNonEmptyString(row.full_name) ||
    !isNonEmptyString(row.email) ||
    !isNonEmptyString(row.lifecycle_status) ||
    !isNullableString(row.probation_start_date) ||
    !isNullableString(row.required_evaluation_start_date) ||
    !isNullableUuid(row.performance_job_id) ||
    !isNullableString(row.performance_job_status) ||
    !isNullableString(row.performance_job_error) ||
    typeof row.has_active_portal_account !== "boolean"
  ) {
    throw new Error(SAFE_READ_ERROR);
  }

  return {
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    lifecycleStatus: row.lifecycle_status,
    probationStartDate: row.probation_start_date,
    requiredEvaluationStartDate: row.required_evaluation_start_date,
    performanceJobId: row.performance_job_id,
    performanceJobStatus: row.performance_job_status,
    performanceJobError: row.performance_job_error,
    hasActivePortalAccount: row.has_active_portal_account,
  };
}

function mapHrPsyconnectReviewer(row) {
  if (
    !isRecord(row) ||
    !hasCompleteShape(row, HR_REVIEWER_COLUMNS) ||
    !isValidUuid(row.user_id) ||
    !isNonEmptyString(row.full_name) ||
    !isNonEmptyString(row.email) ||
    !isNonNegativeInteger(row.active_pod_count) ||
    !Array.isArray(row.active_pod_codes) ||
    row.active_pod_codes.some((podCode) => !isNonEmptyString(podCode))
  ) {
    throw new Error(SAFE_READ_ERROR);
  }

  return {
    userId: row.user_id,
    fullName: row.full_name,
    email: row.email,
    activePodCount: row.active_pod_count,
    activePodCodes: row.active_pod_codes,
  };
}

async function callReadRpc(rpcName, args, mapper) {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_READ_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc(rpcName, args);
    if (error || !Array.isArray(data)) {
      throw new Error(SAFE_READ_ERROR);
    }
    return data.map(mapper);
  } catch {
    throw new Error(SAFE_READ_ERROR);
  }
}

export function fetchPodManagementPods() {
  return callReadRpc("get_pod_management_pods", undefined, mapPod);
}

export function fetchPodMemberships(podId) {
  if (!isValidUuid(podId)) {
    return Promise.reject(new Error("A valid pod ID is required."));
  }
  return callReadRpc(
    "get_pod_management_memberships",
    { p_pod_id: podId },
    mapMembership,
  );
}

export function searchPodCandidates(searchTerm = "") {
  const normalizedSearch = typeof searchTerm === "string"
    ? searchTerm.trim()
    : "";
  if (normalizedSearch.length > 150) {
    return Promise.reject(new Error("Candidate search is too long."));
  }
  return callReadRpc(
    "search_pod_management_candidates",
    { p_search_term: normalizedSearch },
    mapCandidate,
  );
}

export function fetchCandidatesWaitingForPod() {
  return callReadRpc(
    "get_candidates_waiting_for_pod",
    undefined,
    mapWaitingCandidate,
  );
}

export function searchPodHrPsyconnectReviewers(searchTerm = "") {
  const normalizedSearch = typeof searchTerm === "string"
    ? searchTerm.trim()
    : "";

  if (normalizedSearch.length > 150) {
    return Promise.reject(
      new Error("HR Psyconnect reviewer search is too long."),
    );
  }

  return callReadRpc(
    "search_pod_management_hr_reviewers",
    { p_search_term: normalizedSearch },
    mapHrPsyconnectReviewer,
  );
}

function getKnownFunctionMessage(value) {
  if (!isNonEmptyString(value)) {
    return null;
  }
  const message = value.trim();
  return SAFE_FUNCTION_MESSAGES.has(message) ? message : null;
}

async function getSafeFunctionError(error) {
  const context = isRecord(error) ? error.context : null;
  if (context instanceof Response) {
    try {
      const body = await context.clone().json();
      const message = isRecord(body) ? getKnownFunctionMessage(body.error) : null;
      if (message) {
        return message;
      }
    } catch {
      // Fall through to a generic safe error.
    }
  }
  return SAFE_WRITE_ERROR;
}

function validateWriteResponse(response, operation) {
  if (
    !isRecord(response) ||
    response.success !== true ||
    response.operation !== operation ||
    !isRecord(response.podOperation) ||
    response.podOperation.success !== true ||
    !isRecord(response.performanceRetry) ||
    typeof response.performanceRetry.attempted !== "boolean" ||
    typeof response.performanceRetry.success !== "boolean" ||
    !isNonEmptyString(response.performanceRetry.message)
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  const podOperation = response.podOperation;
  const retry = response.performanceRetry;

  if (
    typeof retry.attempted !== "boolean" ||
    typeof retry.success !== "boolean" ||
    !isNonEmptyString(retry.message) ||
    (retry.jobId !== undefined &&
      retry.jobId !== null &&
      !isValidUuid(retry.jobId)) ||
    (retry.jobStatus !== undefined &&
      retry.jobStatus !== null &&
      !isNonEmptyString(retry.jobStatus)) ||
    (retry.performanceOutcome !== undefined &&
      !isNonEmptyString(retry.performanceOutcome))
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  if (
    (operation === "CREATE_POD" || operation === "UPDATE_POD") &&
    (
      !isValidUuid(podOperation.podId) ||
      !isNonEmptyString(podOperation.podCode) ||
      !isNonEmptyString(podOperation.podName) ||
      typeof podOperation.isActive !== "boolean"
    )
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  if (
    operation === "ASSIGN_CANDIDATE" &&
    (
      !isValidUuid(podOperation.candidateId) ||
      !isValidUuid(podOperation.podId) ||
      !isValidUuid(podOperation.membershipId) ||
      !isNonEmptyString(podOperation.effectiveFrom) ||
      !isNullableUuid(podOperation.performanceJobId) ||
      !isNullableString(podOperation.performanceJobStatus) ||
      typeof podOperation.performanceRetryAllowed !== "boolean" ||
      !isNullableString(podOperation.requiredEvaluationStartDate) ||
      !isNonEmptyString(podOperation.performanceMessage)
    )
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  if (
    operation === "ASSIGN_LEAD" &&
    (
      !isValidUuid(podOperation.candidateId) ||
      !isValidUuid(podOperation.userId) ||
      !isValidUuid(podOperation.podId) ||
      !isValidUuid(podOperation.membershipId) ||
      !["POD_LEAD", "TECH_LEAD"].includes(podOperation.membershipType) ||
      !isNonEmptyString(podOperation.effectiveFrom) ||
      podOperation.candidateRolePreserved !== true
    )
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  if (
    operation === "ASSIGN_HR_REVIEWER" &&
    (
      podOperation.operation !== "ASSIGN_HR_REVIEWER" ||
      !isValidUuid(podOperation.userId) ||
      !isValidUuid(podOperation.podId) ||
      !isValidUuid(podOperation.membershipId) ||
      podOperation.membershipType !== "HR_SITE_CONNECT" ||
      !isNonEmptyString(podOperation.effectiveFrom) ||
      (podOperation.changed !== undefined &&
        typeof podOperation.changed !== "boolean")
    )
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  if (
    operation === "END_MEMBERSHIP" &&
    (
      !isValidUuid(podOperation.membershipId) ||
      !isValidUuid(podOperation.podId) ||
      !isNonEmptyString(podOperation.membershipType) ||
      !isNonEmptyString(podOperation.effectiveTo) ||
      podOperation.isActive !== false
    )
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  return {
    operation: response.operation,
    podOperation,
    performanceRetry: retry,
  };
}

export async function executePodManagementOperation(operation, fields) {
  if (
    !WRITE_OPERATIONS.has(operation) ||
    !isRecord(fields) ||
    !supabase ||
    typeof supabase.functions?.invoke !== "function"
  ) {
    throw new Error(SAFE_WRITE_ERROR);
  }

  let result;
  try {
    result = await supabase.functions.invoke("manage-pod-membership", {
      body: { operation, ...fields },
    });
  } catch {
    throw new Error(SAFE_WRITE_ERROR);
  }

  if (result.error) {
    throw new Error(await getSafeFunctionError(result.error));
  }

  return validateWriteResponse(result.data, operation);
}
