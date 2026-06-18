import { supabase } from "./supabaseClient";

export async function updateCandidateLifecycleStatus({
  candidateId,
  fromStatus,
  toStatus,
  activityType,
  remarks = "",
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: toStatus,
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", fromStatus)
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    console.error("Error updating lifecycle status:", updateError);
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match the expected source status.");
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: activityType,
    from_status: fromStatus,
    to_status: toStatus,
    remarks,
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    console.error("Error inserting activity log:", logError);
    throw logError;
  }

  return true;
}
