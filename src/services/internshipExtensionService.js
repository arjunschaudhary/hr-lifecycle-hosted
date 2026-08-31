import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function normalizeSearch(value) {
  return String(value || "").trim().toLowerCase();
}

function filterBySearch(candidates, searchTerm) {
  const normalizedSearch = normalizeSearch(searchTerm);

  if (!normalizedSearch) {
    return candidates;
  }

  return candidates.filter((candidate) =>
    [
      candidate.full_name,
      candidate.email,
      candidate.phone,
      candidate.mid,
      candidate.applied_role,
    ]
      .filter(Boolean)
      .some((value) =>
        String(value).toLowerCase().includes(normalizedSearch)
      )
  );
}

export async function fetchExtensionCandidates(searchTerm = "") {
  if (!supabase) {
    throw new Error("Supabase is not configured.");
  }

  const { data, error } = await supabase.rpc(
    "get_internship_extension_candidates",
  );

  if (error) {
    throw error;
  }

  return filterBySearch(data || [], searchTerm);
}

export async function extendInternship({
  candidateId,
  extensionMonths,
  reason,
}) {
  if (!supabase) {
    throw new Error("Supabase is not configured.");
  }

  const months = Number(extensionMonths);
  const trimmedReason = String(reason || "").trim();

  if (!UUID_PATTERN.test(String(candidateId || ""))) {
    throw new Error("Candidate is required.");
  }

  if (!Number.isInteger(months) || months < 1 || months > 6) {
    throw new Error("Extension months must be between 1 and 6.");
  }

  if (!trimmedReason) {
    throw new Error("Extension reason is required.");
  }

  const { data, error } = await supabase.rpc("extend_candidate_internship", {
    p_candidate_id: candidateId,
    p_extension_months: months,
    p_reason: trimmedReason,
  });

  if (
    error ||
    !data ||
    data.candidateId !== candidateId ||
    typeof data.allocatedLeaveDays !== "number" ||
    typeof data.currentEndDate !== "string" ||
    typeof data.totalExtensionMonths !== "number" ||
    typeof data.totalInternshipDurationDays !== "number"
  ) {
    throw new Error("Unable to extend the internship.");
  }

  return data;
}
