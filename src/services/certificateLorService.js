import { supabase } from "./supabaseClient";

const LOAD_ERROR = "Unable to load Certificate & LOR exit cases.";
const ELIGIBILITY_ERROR = "Unable to load document eligibility.";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const toStringArray = (value) =>
  Array.isArray(value) && value.every((item) => typeof item === "string")
    ? value
    : [];

function mapEligibility(row, exitCaseId) {
  if (!isRecord(row) || !isValidUuid(row.candidate_id)) {
    throw new Error(ELIGIBILITY_ERROR);
  }

  return {
    exitCaseId,
    eligible: row.eligible === true,
    reason: typeof row.reason === "string" ? row.reason : "UNKNOWN",
    dateMatches: row.date_matches === true,
    warningRequired: row.warning_required === true,
    exitDate: row.exit_date || null,
    currentEndDate: row.current_end_date || null,
    candidateId: row.candidate_id,
    candidateName: typeof row.candidate_name === "string" ? row.candidate_name : "—",
    candidateEmail: typeof row.candidate_email === "string" ? row.candidate_email : "—",
    appliedRole: typeof row.applied_role === "string" ? row.applied_role : "—",
    isPodLead: row.is_pod_lead === true,
    allowedVariants: toStringArray(row.allowed_variants),
    allowedCertificateVariants: toStringArray(row.allowed_certificate_variants),
    allowedLorVariants: toStringArray(row.allowed_lor_variants),
    certificateStatus: "NOT_REQUESTED",
    lorStatus: "NOT_REQUESTED",
  };
}

async function fetchExitDocumentEligibility(exitCaseId) {
  const { data, error } = await supabase.rpc("get_exit_document_eligibility", {
    p_exit_case_id: exitCaseId,
  });

  if (error || !Array.isArray(data) || data.length !== 1) {
    throw new Error(ELIGIBILITY_ERROR);
  }

  return mapEligibility(data[0], exitCaseId);
}

async function fetchRequestStatuses(exitCaseIds) {
  const { data, error } = await supabase.rpc(
    "get_hr_exit_document_request_statuses",
    { p_exit_case_ids: exitCaseIds },
  );

  if (error || !Array.isArray(data)) {
    throw new Error(LOAD_ERROR);
  }

  return new Map(
    data
      .filter((row) => isRecord(row) && isValidUuid(row.exit_case_id))
      .map((row) => [
        row.exit_case_id,
        {
          certificateStatus:
            typeof row.certificate_status === "string"
              ? row.certificate_status
              : "NOT_REQUESTED",
          lorStatus:
            typeof row.lor_status === "string" ? row.lor_status : "NOT_REQUESTED",
        },
      ]),
  );
}

/**
 * Loads existing Exit cases through the established secure Exit analytics RPC,
 * then resolves authoritative issuance eligibility per case through the Phase 1
 * RPC. React never derives eligibility or allowed variants.
 */
export async function fetchCertificateLorExitCases() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(LOAD_ERROR);
  }

  const { data, error } = await supabase.rpc("get_exit_analytics", {
    p_filters: {},
  });

  const exitCases = data?.exitCases;
  if (error || !Array.isArray(exitCases)) {
    throw new Error(LOAD_ERROR);
  }

  const caseIds = exitCases
    .map((exitCase) => exitCase?.exit_case_id)
    .filter(isValidUuid);

  const [results, requestStatuses] = await Promise.all([
    Promise.allSettled(
      caseIds.map((exitCaseId) => fetchExitDocumentEligibility(exitCaseId)),
    ),
    fetchRequestStatuses(caseIds),
  ]);

  const unavailableCases = results.filter((result) => result.status === "rejected");
  if (unavailableCases.length > 0) {
    throw new Error(ELIGIBILITY_ERROR);
  }

  return results
    .map((result) => ({
      ...result.value,
      ...(requestStatuses.get(result.value.exitCaseId) || {}),
    }))
    .sort((a, b) => String(b.exitDate || "").localeCompare(String(a.exitDate || "")));
}

/**
 * Creates durable document requests and queues one idempotent automation job
 * per variant. The secure RPC independently validates the mismatch override;
 * this client flag is never treated as authoritative.
 */
export async function requestExitDocuments({
  exitCaseId,
  documentVariants,
  allowDateMismatch = false,
}) {
  if (!isValidUuid(exitCaseId) || !Array.isArray(documentVariants) || documentVariants.length === 0) {
    throw new Error("Select at least one document.");
  }

  const { data, error } = await supabase.rpc("request_exit_documents", {
    p_exit_case_id: exitCaseId,
    p_document_variants: documentVariants,
    p_allow_date_mismatch: allowDateMismatch === true,
  });

  if (error || !Array.isArray(data)) {
    const message = typeof error?.message === "string" ? error.message.trim() : "";
    if (message === "Exit date does not match the current internship end date. Explicit HR confirmation is required.") {
      throw new Error(message);
    }
    throw new Error("Unable to create document requests.");
  }

  let processingStarted = false;
  try {
    const dispatch = await supabase.functions.invoke("dispatch-exit-document-jobs", {
      body: { requestIds: data.map((request) => request.request_id) },
    });
    processingStarted = !dispatch.error && dispatch.data?.dispatched > 0;
  } catch {
    // The durable jobs remain queued and can be dispatched again on a retry.
  }

  return {
    requestCount: data.length,
    message: processingStarted
      ? "Document requests queued and processing has started."
      : "Document requests queued. Processing will start when the worker is available.",
  };
}
