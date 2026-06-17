import { supabase } from "./supabaseClient";

export async function fetchSignedOfferVerifications() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("signed_offer_verification_view")
    .select("*")
    .order("signed_offer_submitted_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data ?? [];
}
