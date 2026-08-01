import { supabase } from "./supabaseClient";

function requireCandidateId(candidateId) {
  const normalizedCandidateId =
    typeof candidateId === "string" ? candidateId.trim() : "";

  if (!normalizedCandidateId) {
    throw new Error("Candidate ID is required.");
  }

  return normalizedCandidateId;
}

function requireSupabaseConfiguration() {
  if (
    !supabase ||
    !import.meta.env.VITE_SUPABASE_URL ||
    !import.meta.env.VITE_SUPABASE_ANON_KEY
  ) {
    throw new Error("Supabase environment variables are not configured.");
  }
}

async function updateHrPsyconnectAccess(rpcName, candidateId) {
  requireSupabaseConfiguration();
  const normalizedCandidateId = requireCandidateId(candidateId);
  const { data, error } = await supabase.rpc(rpcName, {
    p_candidate_id: normalizedCandidateId,
  });

  if (error) {
    throw error;
  }

  return data;
}

export async function grantHrPsyconnectAccess(candidateId) {
  return updateHrPsyconnectAccess(
    "grant_hr_psyconnect_access",
    candidateId,
  );
}

export async function revokeHrPsyconnectAccess(candidateId) {
  return updateHrPsyconnectAccess(
    "revoke_hr_psyconnect_access",
    candidateId,
  );
}
