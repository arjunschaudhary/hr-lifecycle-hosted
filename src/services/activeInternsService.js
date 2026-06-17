import { supabase } from "./supabaseClient";

export async function fetchActiveInterns() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("active_interns_view")
    .select("*")
    .order("full_name", { ascending: true });

  if (error) {
    throw error;
  }

  return data ?? [];
}