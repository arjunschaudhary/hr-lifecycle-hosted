import { supabase } from "./supabaseClient";

const toCount = (value) => Number(value ?? 0);

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
        department
      )
    `
    )
    .eq("candidate_form_completed", true)
    .eq("hr_form_completed", false)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return (data || []).map((row) => ({
    exitCaseId: row.exit_case_id,
    candidateId: row.candidate_id,
    lifecycleId: row.lifecycle_id,
    mid: row.mid || "—",
    candidateName: row.master_candidates?.full_name || "Unknown Candidate",
    podName: row.pod_name_snapshot || row.master_candidates?.department || "—",
    exitType: row.exit_type || "—",
    exitDate: row.exit_date || "—",
    overallStatus: row.overall_status || "HR_PENDING",
    candidateFormCompleted: Boolean(row.candidate_form_completed),
    hrFormCompleted: Boolean(row.hr_form_completed),
    createdAt: row.created_at,
  }));
}
