import { supabase } from "./supabaseClient";

export async function fetchOfferLetterProcessCandidates() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("offer_letter_process_view")
    .select("*")
    .order("full_name", { ascending: true });

  if (error) {
    throw error;
  }

  return data ?? [];
}
