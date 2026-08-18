import { supabase } from "./supabaseClient";

const toCount = (value) => Number(value ?? 0);
const EXIT_QUEUE_LOAD_ERROR = "Unable to load pending Exit evaluations.";

function mapDashboardCounts(row) {
  return {
    totalCandidates: toCount(row.total_candidates),
    hrReviewPending: toCount(row.hr_review_pending_count),
    inProbation: toCount(row.in_probation_count),
    probationReview: toCount(row.probation_review_count),
    probationPassed: toCount(row.probation_passed_count),
    probationRejected: toCount(row.probation_rejected_count),
    probationExtended: toCount(row.probation_extended_count),
    offerLetterProcess: toCount(row.offer_letter_process_count),
    activeInterns: toCount(row.active_intern_count),
    signedOfferSubmitted: toCount(row.signed_offer_submitted_count),
    signedOfferVerified: toCount(row.signed_offer_verified_count),
    mismatchReview: toCount(row.mismatch_review_count),
  };
}

export async function fetchDashboardCounts() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("hr_dashboard_view")
    .select(
      [
        "total_candidates",
        "hr_review_pending_count",
        "in_probation_count",
        "probation_review_count",
        "probation_passed_count",
        "probation_rejected_count",
        "probation_extended_count",
        "offer_letter_process_count",
        "active_intern_count",
        "signed_offer_submitted_count",
        "signed_offer_verified_count",
        "mismatch_review_count",
      ].join(",")
    )
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data ? mapDashboardCounts(data) : null;
}

export async function fetchPendingExitCases() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase.rpc("get_hr_exit_queue");

  if (error) {
    throw new Error(EXIT_QUEUE_LOAD_ERROR);
  }

  return (data || []).map((row) => ({
    exitCaseId: row.exit_case_id,
    candidateId: row.candidate_id,
    lifecycleId: row.lifecycle_id,
    mid: row.mid || "—",
    candidateName: row.candidate_name || "Unknown Candidate",
    podName:
      row.pod_name_snapshot || row.candidate_department || "—",
    exitType: row.exit_type || "—",
    exitDate: row.exit_date || "—",
    overallStatus: row.overall_status || "HR_PENDING",
    candidateFormCompleted: Boolean(row.candidate_form_completed),
    hrFormCompleted: Boolean(row.hr_form_completed),
    createdAt: row.created_at,
  }));
}
