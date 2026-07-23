import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ALLOWED_OUTCOMES = new Set([
  "ACTIVATED",
  "REACTIVATED",
  "REPAIRED",
  "ALREADY_ACTIVE",
]);

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidUuid(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

async function getFunctionErrorMessage(error) {
  const context = isRecord(error) ? error.context : null;

  if (context instanceof Response) {
    try {
      const responseBody = await context.clone().json();

      if (
        isRecord(responseBody) &&
        typeof responseBody.error === "string" &&
        responseBody.error.trim()
      ) {
        return responseBody.error.trim();
      }
    } catch {
      // Fall through to the generic safe message.
    }
  }

  return "Unable to create the candidate portal account.";
}

export async function createCandidatePortalAccount({ candidateId }) {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
  const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

  if (!supabase || !supabaseUrl || !supabaseAnonKey) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const normalizedCandidateId =
    typeof candidateId === "string" ? candidateId.trim() : "";

  if (!isValidUuid(normalizedCandidateId)) {
    throw new Error("A valid candidate ID is required.");
  }

  let result;

  try {
    result = await supabase.functions.invoke(
      "create-candidate-portal-account",
      {
        body: {
          candidate_id: normalizedCandidateId,
        },
      },
    );
  } catch {
    throw new Error("Unable to create the candidate portal account.");
  }

  if (result.error) {
    throw new Error(await getFunctionErrorMessage(result.error));
  }

  const response = result.data;

  if (
    !isRecord(response) ||
    response.success !== true ||
    typeof response.outcome !== "string" ||
    !ALLOWED_OUTCOMES.has(response.outcome) ||
    !isValidUuid(response.candidate_id) ||
    response.candidate_id !== normalizedCandidateId ||
    !isValidUuid(response.user_id) ||
    typeof response.email !== "string" ||
    !response.email.trim() ||
    typeof response.invitation_sent !== "boolean"
  ) {
    throw new Error("Candidate portal account service returned an invalid response.");
  }

  return {
    success: true,
    outcome: response.outcome,
    candidate_id: response.candidate_id,
    user_id: response.user_id,
    email: response.email,
    invitation_sent: response.invitation_sent,
  };
}
