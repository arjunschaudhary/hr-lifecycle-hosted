import { supabase } from "./supabaseClient";

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const PORTAL_SUMMARY_ERROR = "Unable to load your candidate portal summary.";

export async function fetchCurrentCandidatePortalSummary() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(PORTAL_SUMMARY_ERROR);
  }

  let result;

  try {
    result = await supabase.rpc("get_current_candidate_portal_summary");
  } catch {
    throw new Error(PORTAL_SUMMARY_ERROR);
  }

  if (result.error || !isRecord(result.data)) {
    throw new Error(PORTAL_SUMMARY_ERROR);
  }

  const { profile, internship, leave, signedOffer } = result.data;

  if (
    !isRecord(profile) ||
    !isRecord(internship) ||
    !isRecord(leave) ||
    !isRecord(signedOffer) ||
    !isValidUuid(profile.candidateId) ||
    typeof leave.available !== "boolean" ||
    typeof signedOffer.canSubmit !== "boolean"
  ) {
    throw new Error(PORTAL_SUMMARY_ERROR);
  }

  return result.data;
}
