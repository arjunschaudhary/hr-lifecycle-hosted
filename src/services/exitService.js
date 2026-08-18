/**
 * exitService.js
 * All Supabase interaction for the Candidate Exit Questionnaire.
 * No Supabase queries should live inside React components.
 */

import { supabase } from "./supabaseClient";

const EXIT_LOAD_ERROR = "Unable to load exit information. Please try again.";
const EXIT_SUBMIT_ERROR = "Unable to submit your feedback. Please try again.";
const SAFE_EXIT_LOAD_MESSAGES = new Set([
  "Candidate portal access is required.",
  "An active candidate account is required.",
]);
const SAFE_EXIT_SUBMIT_MESSAGES = new Set([
  "Candidate portal access is required.",
  "An active candidate account is required.",
  "No active exit case is available for this candidate.",
  "Exit feedback has already been submitted for this case.",
  "Exit feedback must be a valid object.",
  "Exit feedback is too large.",
  "One or more Exit feedback text fields are invalid.",
  "One or more Exit feedback selections are too long.",
  "One or more Exit feedback text responses are too long.",
  "One or more Exit handover fields are too long.",
  "One or more Exit feedback selections are invalid.",
  "Too many Exit feedback selections were provided.",
  "Exit handover tasks must be a valid list.",
  "Too many Exit handover tasks were provided.",
  "One or more Exit handover tasks are invalid.",
  "One or more Exit handover task fields are invalid.",
  "Each Exit handover task must include a task name.",
  "One or more Exit handover task fields are too long.",
  "Please indicate whether the full internship duration was completed.",
  "A primary Exit reason is required.",
  "Please specify the other Exit reason.",
  "Please specify the other exposure desired.",
  "Please specify the other HR communication issue.",
  "Please specify the other improvement suggestion.",
  "Please provide the name of the person who was briefed.",
  "All required Exit feedback ratings must be valid whole numbers.",
  "One or more Exit feedback ratings are invalid.",
  "Exit case state changed before feedback could be submitted.",
]);

// ---------------------------------------------------------------------------
// Helper: guard against missing Supabase client
// ---------------------------------------------------------------------------
function assertClient() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(EXIT_LOAD_ERROR);
  }
}

function getSafeRpcMessage(error, fallbackMessage, safeMessages) {
  const message =
    error && typeof error.message === "string" ? error.message.trim() : "";

  return safeMessages.has(message) ? message : fallbackMessage;
}

// ---------------------------------------------------------------------------
// getCandidateExitCase
// Returns the latest Exit case for the current authenticated candidate,
// including completed history, or null if no Exit case exists.
// ---------------------------------------------------------------------------
export async function getCandidateExitCase() {
  assertClient();

  const { data: rows, error } = await supabase.rpc(
    "get_current_candidate_exit_case",
  );

  if (error) {
    throw new Error(
      getSafeRpcMessage(error, EXIT_LOAD_ERROR, SAFE_EXIT_LOAD_MESSAGES),
    );
  }

  if (!rows || rows.length === 0) {
    return null;
  }

  return rows[0];
}

// ---------------------------------------------------------------------------
// getCandidateExitData
// Returns the exit case + the candidate's profile data needed for auto-fill.
// ---------------------------------------------------------------------------
export async function getCandidateExitData() {
  assertClient();

  const exitCase = await getCandidateExitCase();

  if (!exitCase) {
    return { exitCase: null, profile: null };
  }

  // Reuse the existing portal summary RPC to get candidate profile details
  let portalSummary = {};
  try {
    const { data, error } = await supabase.rpc(
      "get_current_candidate_portal_summary"
    );
    if (!error && data) {
      portalSummary = data;
    }
  } catch {
    // If portal summary RPC fails, safely proceed with exitCase details
  }

  const profile = portalSummary.profile ?? {};
  const internship = portalSummary.internship ?? {};

  return {
    exitCase: {
      ...exitCase,
      alreadySubmitted:
        Boolean(exitCase.already_submitted) || exitCase.candidate_form_completed,
    },
    profile: {
      fullName: profile.fullName ?? "",
      email: profile.email ?? "",
      phone: profile.phone ?? "",
      department: profile.department ?? "",
      internshipDurationMonths: internship.internshipDurationMonths ?? null,
      startDate: internship.startDate ?? null,
      currentEndDate: internship.currentEndDate ?? null,
      podName: exitCase.pod_name_snapshot ?? profile.department ?? "",
    },
  };
}

// ---------------------------------------------------------------------------
// submitCandidateExitFeedback
// Submits candidate feedback atomically. Candidate and Exit-case identity are
// resolved by the secure RPC from the current authenticated candidate.
// ---------------------------------------------------------------------------
export async function submitCandidateExitFeedback({ formData }) {
  assertClient();

  if (!formData || typeof formData !== "object") {
    throw new Error(EXIT_SUBMIT_ERROR);
  }

  const { data, error } = await supabase.rpc(
    "submit_current_candidate_exit_feedback",
    { p_feedback: { ...formData } },
  );

  if (error) {
    throw new Error(
      getSafeRpcMessage(error, EXIT_SUBMIT_ERROR, SAFE_EXIT_SUBMIT_MESSAGES),
    );
  }

  return data;
}
