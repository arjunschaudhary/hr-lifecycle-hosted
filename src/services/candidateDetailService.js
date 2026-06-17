import { supabase } from "./supabaseClient";

export async function fetchCandidateDetail(candidateId) {
  if (!candidateId) {
    throw new Error("Candidate ID is required.");
  }

  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("candidate_detail_view")
    .select("*")
    .eq("candidate_id", candidateId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data;
}
