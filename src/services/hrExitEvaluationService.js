/**
 * hrExitEvaluationService.js
 * All Supabase interaction for the HR Intern Exit Evaluation module.
 * No Supabase queries live inside React components.
 */

import { supabase } from "./supabaseClient";

const HR_EXIT_LOAD_ERROR = "Unable to load exit evaluation details. Please try again.";
const HR_EXIT_SUBMIT_ERROR = "Unable to submit HR evaluation. Please try again.";
const SAFE_HR_EXIT_LOAD_MESSAGES = new Set([
  "Authorized HR access is required.",
  "Exit case is required.",
  "Exit case was not found.",
]);
const SAFE_HR_EXIT_SUBMIT_MESSAGES = new Set([
  "Exit case is required.",
  "HR Exit evaluation must be a valid object.",
  "HR Exit evaluation is too large.",
  "This Exit case is not eligible for HR evaluation.",
  "HR evaluation has already been submitted for this Exit case.",
  "One or more HR Exit evaluation text fields are invalid.",
  "One or more HR Exit evaluation selections are too long.",
  "One or more HR Exit evaluation text responses are too long.",
  "One or more HR Exit evaluation selections are invalid.",
  "Too many HR Exit evaluation selections were provided.",
  "HR Exit handover items must be a valid list.",
  "Too many HR Exit handover items were provided.",
  "One or more HR Exit handover items are invalid.",
  "One or more HR Exit handover item fields are invalid.",
  "Each HR Exit handover item must include a task name.",
  "One or more HR Exit handover item fields are too long.",
  "A primary HR Exit reason is required.",
  "Rehire eligibility is required.",
  "Retention attempt selection is invalid.",
  "Retention notes are required when retention was attempted.",
  "All HR performance ratings must be valid whole numbers between 1 and 5.",
  "Selected verifier is invalid.",
  "Selected verifier is not an active user.",
  "All HR performance ratings must be between 1 and 5.",
  "Exit case state changed before the HR evaluation could be submitted.",
]);

function assertClient() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(HR_EXIT_LOAD_ERROR);
  }
}

function getSafeRpcMessage(error, fallbackMessage, safeMessages) {
  const message =
    error && typeof error.message === "string" ? error.message.trim() : "";

  return safeMessages.has(message) ? message : fallbackMessage;
}

/**
 * Fetch all exit cases requiring HR evaluation (candidate_form_completed = true AND hr_form_completed = false).
 */
export async function getPendingHRExitCases() {
  assertClient();

  const { data, error } = await supabase.rpc("get_hr_exit_queue");

  if (error) {
    throw new Error(
      getSafeRpcMessage(error, HR_EXIT_LOAD_ERROR, SAFE_HR_EXIT_LOAD_MESSAGES),
    );
  }

  return (data || []).map(mapExitCaseRow);
}

/**
 * Fetch exit evaluation context for a given exitCaseId (or first pending case if no ID specified).
 */
export async function getHRExitEvaluationData(explicitExitCaseId = null) {
  assertClient();

  let exitCaseId = explicitExitCaseId;

  // If no exitCaseId provided, attempt to fetch the latest pending exit case
  if (!exitCaseId) {
    const pendingCases = await getPendingHRExitCases();
    if (pendingCases && pendingCases.length > 0) {
      exitCaseId = pendingCases[0].exitCaseId;
    } else {
      return { exitCase: null, profile: null, candidateFeedback: null, existingEvaluation: null, reviewer: null, staffUsers: [] };
    }
  }

  const { data, error } = await supabase.rpc("get_hr_exit_case", {
    p_exit_case_id: exitCaseId,
  });

  if (error || !data?.exitCase) {
    throw new Error(
      getSafeRpcMessage(error, HR_EXIT_LOAD_ERROR, SAFE_HR_EXIT_LOAD_MESSAGES),
    );
  }

  const exitCaseRaw = data.exitCase;
  const candidateFeedback = data.candidateFeedback || null;
  const existingEvaluation = data.existingEvaluation || null;
  const existingHandoverItems = data.existingHandoverItems || [];
  const reviewer = data.reviewer || {
    id: null,
    name: "HR Evaluator",
    role: "HR Executive",
    email: "",
  };
  const staffUsers = data.staffUsers || [];

  const candidateProfile = exitCaseRaw.master_candidates || {};
  const lifecycleInfo = exitCaseRaw.hr_lifecycle || {};

  const mappedExitCase = mapExitCaseRow(exitCaseRaw);
  mappedExitCase.alreadySubmitted = Boolean(existingEvaluation) || exitCaseRaw.hr_form_completed;

  return {
    exitCase: mappedExitCase,
    profile: {
      fullName: candidateProfile.full_name || "—",
      email: candidateProfile.email || "—",
      phone: candidateProfile.phone || "—",
      department: exitCaseRaw.pod_name_snapshot || candidateProfile.department || "—",
      mid: exitCaseRaw.mid || "—",
      startDate: lifecycleInfo.probation_start_date || null,
      endDate: lifecycleInfo.current_end_date || lifecycleInfo.original_end_date || null,
      internshipDurationMonths: lifecycleInfo.internship_duration_months || null,
    },
    candidateFeedback: candidateFeedback || null,
    existingEvaluation: existingEvaluation || null,
    existingHandoverItems: existingHandoverItems || [],
    reviewer,
    staffUsers,
  };
}

/**
 * Submit HR Exit Evaluation.
 * The secure RPC derives the reviewer from the authenticated application user
 * and performs the evaluation, handover, and workflow update atomically.
 */
export async function submitHRExitEvaluation({
  exitCaseId,
  formData,
  handoverItems = [],
}) {
  assertClient();

  if (!exitCaseId || !formData || typeof formData !== "object") {
    throw new Error(HR_EXIT_SUBMIT_ERROR);
  }

  const evaluationPayload = {
    ...formData,
    verifiedBy: isValidUuid(formData.verifiedBy)
      ? formData.verifiedBy
      : null,
    handoverItems: Array.isArray(handoverItems) ? handoverItems : [],
  };

  const { data, error } = await supabase.rpc("submit_hr_exit_evaluation", {
    p_exit_case_id: exitCaseId,
    p_evaluation: evaluationPayload,
  });

  if (error) {
    throw new Error(
      getSafeRpcMessage(
        error,
        HR_EXIT_SUBMIT_ERROR,
        SAFE_HR_EXIT_SUBMIT_MESSAGES,
      ),
    );
  }

  return data;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function mapExitCaseRow(row) {
  return {
    exitCaseId: row.exit_case_id,
    candidateId: row.candidate_id,
    lifecycleId: row.lifecycle_id,
    mid: row.mid || "—",
    candidateName:
      row.candidate_name ||
      row.master_candidates?.full_name ||
      "Unknown Candidate",
    candidateEmail:
      row.candidate_email || row.master_candidates?.email || "—",
    podName:
      row.pod_name_snapshot ||
      row.candidate_department ||
      row.master_candidates?.department ||
      "—",
    exitType: row.exit_type || "—",
    exitDate: row.exit_date || "—",
    overallStatus: row.overall_status || "HR_PENDING",
    candidateFormCompleted: Boolean(row.candidate_form_completed),
    hrFormCompleted: Boolean(row.hr_form_completed),
    createdAt: row.created_at,
  };
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function isValidUuid(val) {
  return typeof val === "string" && UUID_REGEX.test(val);
}
