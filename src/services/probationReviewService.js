import { supabase } from "./supabaseClient";

export async function fetchProbationReviewCandidates() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("probation_review_view")
    .select(
      [
        "candidate_id",
        "full_name",
        "email",
        "phone",
        "applied_role",
        "role_code",
        "source",
        "probation_status",
        "probation_start_date",
        "probation_end_date",
        "internship_duration_months",
        "original_end_date",
        "current_end_date",
        "probation_extension_count",
        "probation_review_notes",
        "hr_decision",
        "mid",
        "created_at",
      ].join(",")
    )
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data ?? [];
}
