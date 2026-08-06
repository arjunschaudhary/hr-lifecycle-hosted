/**
 * hrExitEvaluationService.js
 * All Supabase interaction for the HR Intern Exit Evaluation module.
 * No Supabase queries live inside React components.
 */

import { supabase } from "./supabaseClient";

const HR_EXIT_LOAD_ERROR = "Unable to load exit evaluation details. Please try again.";
const HR_EXIT_SUBMIT_ERROR = "Unable to submit HR evaluation. Please try again.";

function assertClient() {
  if (!supabase || typeof supabase.from !== "function") {
    throw new Error(HR_EXIT_LOAD_ERROR);
  }
}

/**
 * Fetch all exit cases requiring HR evaluation (candidate_form_completed = true AND hr_form_completed = false).
 */
export async function getPendingHRExitCases() {
  assertClient();

  const { data, error } = await supabase
    .from("exit_cases")
    .select(
      `
      exit_case_id,
      candidate_id,
      lifecycle_id,
      mid,
      pod_name_snapshot,
      exit_date,
      exit_type,
      overall_status,
      candidate_form_completed,
      hr_form_completed,
      created_at,
      master_candidates (
        full_name,
        email,
        department
      ),
      hr_lifecycle (
        probation_start_date,
        current_end_date,
        internship_duration_months
      )
    `
    )
    .eq("candidate_form_completed", true)
    .eq("hr_form_completed", false)
    .order("created_at", { ascending: false });

  if (error) {
    throw new Error(HR_EXIT_LOAD_ERROR);
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

  // 1. Fetch Exit Case details
  const { data: caseRows, error: caseError } = await supabase
    .from("exit_cases")
    .select(
      `
      exit_case_id,
      candidate_id,
      lifecycle_id,
      mid,
      pod_name_snapshot,
      exit_date,
      exit_type,
      overall_status,
      candidate_form_completed,
      hr_form_completed,
      created_at,
      master_candidates (
        full_name,
        email,
        phone,
        department,
        applied_role
      ),
      hr_lifecycle (
        probation_start_date,
        current_end_date,
        original_end_date,
        internship_duration_months
      )
    `
    )
    .eq("exit_case_id", exitCaseId)
    .limit(1);

  if (caseError || !caseRows || caseRows.length === 0) {
    throw new Error(HR_EXIT_LOAD_ERROR);
  }

  const exitCaseRaw = caseRows[0];

  // 2. Fetch Candidate's submitted exit feedback questionnaire
  const { data: candidateFeedback, error: feedbackError } = await supabase
    .from("candidate_exit_feedback")
    .select("*")
    .eq("exit_case_id", exitCaseId)
    .maybeSingle();

  if (feedbackError) {
    console.warn("[hrExitEvaluationService] Could not fetch candidate exit feedback:", feedbackError);
  }

  // 3. Fetch Existing HR evaluation record (if any)
  const { data: existingEvaluation, error: evalError } = await supabase
    .from("hr_exit_evaluations")
    .select("*")
    .eq("exit_case_id", exitCaseId)
    .maybeSingle();

  if (evalError) {
    console.warn("[hrExitEvaluationService] Could not check existing HR evaluation:", evalError);
  }

  // 4. Fetch Handover items for this exit case (if any)
  const { data: existingHandoverItems } = await supabase
    .from("exit_handover_items")
    .select("*")
    .eq("exit_case_id", exitCaseId);

  // 5. Get current authenticated user details for Reviewer info
  let reviewer = {
    id: null,
    name: "HR Evaluator",
    role: "HR Executive",
    email: "",
  };

  try {
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (user) {
      reviewer.id = user.id;
      reviewer.email = user.email || "";

      // Try fetching staff profile from public.users table
      const { data: userData } = await supabase
        .from("users")
        .select("id, name, email, roles(label)")
        .eq("id", user.id)
        .maybeSingle();

      if (userData) {
        reviewer.name = userData.name || user.user_metadata?.full_name || user.email;
        reviewer.role = userData.roles?.label || "HR Executive";
      } else {
        reviewer.name = user.user_metadata?.full_name || user.user_metadata?.name || user.email;
      }
    }
  } catch (err) {
    console.warn("[hrExitEvaluationService] Failed to load current user details:", err);
  }

  // 6. Fetch active staff users for "Verified By" selector
  let staffUsers = [];
  try {
    const { data: userRows } = await supabase
      .from("users")
      .select("id, name, email")
      .eq("status", "active")
      .order("name", { ascending: true });

    if (userRows && userRows.length > 0) {
      staffUsers = userRows.map((u) => ({ value: u.id, label: `${u.name} (${u.email})` }));
    }
  } catch (err) {
    console.warn("[hrExitEvaluationService] Could not load staff users:", err);
  }

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
 * Sequence:
 *  1. Guard against duplicate submission.
 *  2. Insert into hr_exit_evaluations table.
 *  3. Insert into exit_handover_items table (if handover items provided).
 *  4. Update exit_cases (hr_form_completed = true, overall_status = 'COMPLETED').
 */
export async function submitHRExitEvaluation({
  exitCaseId,
  reviewerId,
  formData,
  handoverItems = [],
}) {
  assertClient();

  if (!exitCaseId || !reviewerId) {
    throw new Error(HR_EXIT_SUBMIT_ERROR);
  }

  // 1. Guard against duplicate submission
  const { data: existing, error: dupCheckError } = await supabase
    .from("hr_exit_evaluations")
    .select("evaluation_id")
    .eq("exit_case_id", exitCaseId)
    .maybeSingle();

  if (dupCheckError) {
    throw new Error(HR_EXIT_SUBMIT_ERROR);
  }

  if (existing) {
    throw new Error("HR Evaluation has already been submitted for this exit case.");
  }

  // Build hr_exit_evaluations payload matching table columns exactly
  const evaluationPayload = {
    exit_case_id: exitCaseId,
    reviewer_id: reviewerId,

    // Performance Ratings
    skill_rating: toIntOrNull(formData.skillRating),
    communication_rating: toIntOrNull(formData.communicationRating),
    ownership_rating: toIntOrNull(formData.ownershipRating),
    reliability_rating: toIntOrNull(formData.reliabilityRating),
    collaboration_rating: toIntOrNull(formData.collaborationRating),
    adaptability_rating: toIntOrNull(formData.adaptabilityRating),
    timeliness_rating: toIntOrNull(formData.timelinessRating),
    independence_rating: toIntOrNull(formData.independenceRating),

    // Exit Context
    hr_primary_reason: formData.hrPrimaryReason || null,
    hr_other_reasons: formData.hrOtherReasons?.length > 0 ? formData.hrOtherReasons : null,
    hr_preventable: formData.hrPreventable || null,
    retention_attempt: formData.retentionAttempt === "yes",
    retention_notes: formData.retentionAttempt === "yes" ? formData.retentionNotes || null : null,
    extension_offer: formData.extensionOffer || null,
    lead_extension_recommendation: formData.leadExtensionRecommendation || null,
    rehire_eligibility: formData.rehireEligibility || null,

    internal_notes: formData.internalNotes || null,
    candidate_summary: formData.candidateSummary || null,

    // Knowledge Transfer
    handover_complete: formData.handoverComplete || null,
    handover_method: formData.handoverMethod?.length > 0 ? formData.handoverMethod : null,
    handover_gap: formData.handoverGap || null,
    verified_by: isValidUuid(formData.verifiedBy) ? formData.verifiedBy : reviewerId,

    submitted_at: new Date().toISOString(),
  };

  // STEP 2: Insert into hr_exit_evaluations
  const { error: evalInsertError } = await supabase
    .from("hr_exit_evaluations")
    .insert(evaluationPayload);

  if (evalInsertError) {
    if (evalInsertError.code === "23505") {
      throw new Error("HR Evaluation has already been submitted for this exit case.");
    }
    console.error("[hrExitEvaluationService] Insert evaluation error:", evalInsertError);
    throw new Error(HR_EXIT_SUBMIT_ERROR);
  }

  // STEP 3: Insert handover items if provided
  if (Array.isArray(handoverItems) && handoverItems.length > 0) {
    const handoverRecords = handoverItems
      .filter((item) => item && item.taskName?.trim())
      .map((item) => ({
        exit_case_id: exitCaseId,
        task_name: item.taskName.trim(),
        task_status: item.taskStatus || "COMPLETED",
        next_steps: item.nextSteps || null,
        successor_name: item.successorName || null,
        repository_link: item.repositoryLink || null,
        transfer_documents: item.transferDocuments || null,
        access_to_revoke: item.accessToRevoke || null,
        time_sensitive_notes: item.timeSensitiveNotes || null,
      }));

    if (handoverRecords.length > 0) {
      const { error: handoverError } = await supabase
        .from("exit_handover_items")
        .insert(handoverRecords);

      if (handoverError) {
        console.warn("[hrExitEvaluationService] Warning: Handover items insert failed:", handoverError);
      }
    }
  }

  // STEP 4: Update exit_cases only after inserts succeed
  const { error: caseUpdateError } = await supabase
    .from("exit_cases")
    .update({
      hr_form_completed: true,
      overall_status: "COMPLETED",
      exit_completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("exit_case_id", exitCaseId);

  if (caseUpdateError) {
    console.error("[hrExitEvaluationService] Failed updating exit_cases workflow status:", caseUpdateError);
  }
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
    candidateName: row.master_candidates?.full_name || "Unknown Candidate",
    candidateEmail: row.master_candidates?.email || "—",
    podName: row.pod_name_snapshot || row.master_candidates?.department || "—",
    exitType: row.exit_type || "—",
    exitDate: row.exit_date || "—",
    overallStatus: row.overall_status || "HR_PENDING",
    candidateFormCompleted: Boolean(row.candidate_form_completed),
    hrFormCompleted: Boolean(row.hr_form_completed),
    createdAt: row.created_at,
  };
}

function toIntOrNull(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : null;
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function isValidUuid(val) {
  return typeof val === "string" && UUID_REGEX.test(val);
}
