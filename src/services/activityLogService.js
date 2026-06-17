import { supabase } from "./supabaseClient";

export async function fetchActivityLogs() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data, error } = await supabase
    .from("activity_log_view")
    .select("*")
    .order("performed_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data ?? [];
}
