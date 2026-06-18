import { supabase } from "./supabaseClient";
import { fetchActiveInterns } from "./activeInternsService";

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

  const sentRows = await fetchActiveInterns();
  const offerLetterSentRows = sentRows
    .filter((row) => row.lifecycle_status === "OFFER_LETTER_SENT")
    .map((row) => ({
      ...row,
      offer_status: row.offer_status || "OFFER_LETTER_SENT",
      sent_at: row.sent_at ?? row.offer_letter_sent_at,
    }));

  return [...(data ?? []), ...offerLetterSentRows];
}
