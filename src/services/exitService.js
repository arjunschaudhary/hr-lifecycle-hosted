/**
 * exitService.js
 * All Supabase interaction for the Candidate Exit Questionnaire.
 * No Supabase queries should live inside React components.
 */

import { supabase } from "./supabaseClient";

const EXIT_LOAD_ERROR = "Unable to load exit information. Please try again.";
const EXIT_SUBMIT_ERROR = "Unable to submit your feedback. Please try again.";

// ---------------------------------------------------------------------------
// Helper: guard against missing Supabase client
// ---------------------------------------------------------------------------
function assertClient() {
  if (!supabase || typeof supabase.from !== "function") {
    throw new Error(EXIT_LOAD_ERROR);
  }
}

// ---------------------------------------------------------------------------
// resolveCurrentCandidateId
// Tries current_candidate_id RPC first, falls back to candidate_user_accounts table query.
// ---------------------------------------------------------------------------
async function resolveCurrentCandidateId() {
  assertClient();

  // Method 1: Try RPC
  try {
    const { data: candidateId, error } = await supabase.rpc(
      "current_candidate_id"
    );
    if (!error && candidateId) {
      return candidateId;
    }
  } catch {
    // Ignore RPC failure and try fallback
  }

  // Method 2: Fallback via auth user session -> candidate_user_accounts
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    throw new Error(EXIT_LOAD_ERROR);
  }

  const { data: rows, error: tableError } = await supabase
    .from("candidate_user_accounts")
    .select("candidate_id")
    .eq("user_id", user.id)
    .eq("account_status", "ACTIVE")
    .limit(1);

  if (tableError || !rows || rows.length === 0) {
    throw new Error(EXIT_LOAD_ERROR);
  }

  return rows[0].candidate_id;
}

// ---------------------------------------------------------------------------
// getCandidateExitCase
// Returns the open exit case for the specified or currently authenticated candidate,
// or null if no active exit case exists.
// ---------------------------------------------------------------------------
export async function getCandidateExitCase(explicitCandidateId = null) {
  assertClient();

  const candidateId = explicitCandidateId || (await resolveCurrentCandidateId());

  if (!candidateId) {
    throw new Error(EXIT_LOAD_ERROR);
  }

  const { data: rows, error } = await supabase
    .from("exit_cases")
    .select(
      `
      exit_case_id,
      candidate_id,
      exit_date,
      exit_type,
      overall_status,
      candidate_form_completed,
      hr_form_completed,
      pod_name_snapshot,
      created_at
    `
    )
    .eq("candidate_id", candidateId)
    .order("created_at", { ascending: false })
    .limit(1);

  if (error) {
    throw new Error(EXIT_LOAD_ERROR);
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
export async function getCandidateExitData(explicitCandidateId = null) {
  assertClient();

  const candidateId = explicitCandidateId || (await resolveCurrentCandidateId());

  // Fetch exit case for resolved candidate
  const exitCase = await getCandidateExitCase(candidateId);

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

  // Check for an already-submitted feedback record
  const { data: existing, error: fbError } = await supabase
    .from("candidate_exit_feedback")
    .select("feedback_id, submitted_at")
    .eq("exit_case_id", exitCase.exit_case_id)
    .maybeSingle();

  if (fbError) {
    throw new Error(EXIT_LOAD_ERROR);
  }

  const profile = portalSummary.profile ?? {};
  const internship = portalSummary.internship ?? {};

  return {
    exitCase: {
      ...exitCase,
      alreadySubmitted: Boolean(existing?.submitted_at) || exitCase.candidate_form_completed,
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
// Inserts into candidate_exit_feedback, then updates exit_cases on success.
// Never updates exit_cases before the feedback is stored.
// ---------------------------------------------------------------------------
export async function submitCandidateExitFeedback({ exitCaseId, candidateId, formData }) {
  assertClient();

  if (!exitCaseId || !candidateId) {
    throw new Error(EXIT_SUBMIT_ERROR);
  }

  // Guard: prevent duplicate submission
  const { data: existing, error: dupError } = await supabase
    .from("candidate_exit_feedback")
    .select("feedback_id")
    .eq("exit_case_id", exitCaseId)
    .maybeSingle();

  if (dupError) {
    throw new Error(EXIT_SUBMIT_ERROR);
  }

  if (existing) {
    throw new Error("You have already submitted feedback for this exit case.");
  }

  // Build the feedback record from formData
  const feedbackRecord = {
    exit_case_id: exitCaseId,
    candidate_id: candidateId,

    // Basic exit info
    completed_full_duration:
      formData.completedFullDuration === "yes"
        ? true
        : formData.completedFullDuration === "no"
        ? false
        : null,
    primary_exit_reason: formData.primaryExitReason || null,
    other_exit_reasons:
      formData.otherExitReasons?.length > 0 ? formData.otherExitReasons : null,
    other_reason_text: formData.otherReasonText || null,
    preventable_exit: formData.preventableExit || null,
    wanted_extension: formData.wantedExtension || null,
    extension_reason: formData.extensionReason || null,

    // Learning
    overall_experience_rating: toIntOrNull(formData.overallExperienceRating),
    nps_score: toIntOrNull(formData.npsScore),
    expectation_match: formData.expectationMatch || null,
    learning_rating: toIntOrNull(formData.learningRating),
    meaningful_work: formData.meaningfulWork || null,
    missing_exposure:
      formData.missingExposure?.length > 0 ? formData.missingExposure : null,
    missing_exposure_other: formData.missingExposureOther || null,

    // Mentorship
    guidance_rating: toIntOrNull(formData.guidanceRating),
    feedback_frequency: formData.feedbackFrequency || null,
    psychological_safety_rating: toIntOrNull(formData.psychologicalSafetyRating),
    valued_contributor_rating: toIntOrNull(formData.valuedContributorRating),
    work_distribution_rating: toIntOrNull(formData.workDistributionRating),
    pod_culture_rating: toIntOrNull(formData.podCultureRating),

    // Safety
    safety_issue: formData.safetyIssue || null,
    safety_issue_details: formData.safetyIssueDetails || null,
    is_confidential: formData.safetyIssue === "yes",

    // HR Communication
    hr_communication_issues:
      formData.hrCommunicationIssues?.length > 0
        ? formData.hrCommunicationIssues
        : null,
    hr_communication_other: formData.hrCommunicationOther || null,

    // Final feedback
    improvement_suggestions:
      formData.improvementSuggestions?.length > 0
        ? formData.improvementSuggestions
        : null,
    improvement_other: formData.improvementOther || null,
    rejoin_interest: formData.rejoinInterest || null,

    submitted_at: new Date().toISOString(),
  };

  // STEP 1: Insert feedback record
  const { error: insertError } = await supabase
    .from("candidate_exit_feedback")
    .insert(feedbackRecord);

  if (insertError) {
    if (insertError.code === "23505") {
      throw new Error(
        "You have already submitted feedback for this exit case."
      );
    }
    throw new Error(EXIT_SUBMIT_ERROR);
  }

  // STEP 2: Insert handover items into exit_handover_items if provided
  const successorName =
    formData.briefedSomeone === "yes" ? formData.personName?.trim() || null : null;
  const repositoryLink = formData.repositoryLink?.trim() || null;
  const transferDocuments = formData.transferDocuments?.trim() || null;
  const accessToRevoke = formData.accessToRevoke?.trim() || null;
  const timeSensitiveNotes = formData.timeSensitiveNotes?.trim() || null;

  const validTasks = Array.isArray(formData.ongoingTasks)
    ? formData.ongoingTasks.filter((t) => t && t.taskName && t.taskName.trim().length > 0)
    : [];

  let handoverRecords = [];

  if (validTasks.length > 0) {
    handoverRecords = validTasks.map((t) => ({
      exit_case_id: exitCaseId,
      task_name: t.taskName.trim(),
      task_status: t.taskStatus || "IN_PROGRESS",
      next_steps: t.nextSteps?.trim() || null,
      successor_name: successorName,
      repository_link: repositoryLink,
      transfer_documents: transferDocuments,
      access_to_revoke: accessToRevoke,
      time_sensitive_notes: timeSensitiveNotes,
    }));
  } else if (
    successorName ||
    repositoryLink ||
    transferDocuments ||
    accessToRevoke ||
    timeSensitiveNotes
  ) {
    handoverRecords.push({
      exit_case_id: exitCaseId,
      task_name: "General Handover Notes",
      task_status: "COMPLETED",
      next_steps: null,
      successor_name: successorName,
      repository_link: repositoryLink,
      transfer_documents: transferDocuments,
      access_to_revoke: accessToRevoke,
      time_sensitive_notes: timeSensitiveNotes,
    });
  }

  if (handoverRecords.length > 0) {
    const { error: handoverError } = await supabase
      .from("exit_handover_items")
      .insert(handoverRecords);

    if (handoverError) {
      console.error(
        "[exitService] exit_handover_items insert failed:",
        handoverError
      );
      throw new Error(EXIT_SUBMIT_ERROR);
    }
  }

  // STEP 3: Update exit_cases only after successful inserts.
  // Transition overall_status to 'HR_PENDING' since Candidate form is now completed.
  const { error: updateError } = await supabase
    .from("exit_cases")
    .update({
      candidate_form_completed: true,
      overall_status: "HR_PENDING",
      updated_at: new Date().toISOString(),
    })
    .eq("exit_case_id", exitCaseId);

  if (updateError) {
    console.error(
      "[exitService] exit_cases update failed after feedback insert:",
      updateError
    );
  }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------
function toIntOrNull(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : null;
}
