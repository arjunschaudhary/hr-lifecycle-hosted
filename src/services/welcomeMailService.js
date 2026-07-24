import { supabase } from "./supabaseClient";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const SAFE_FALLBACK_ERROR =
  "Unable to send the welcome email. Please try again.";

const KNOWN_FUNCTION_MESSAGES = new Set([
  "Welcome-email job is already being processed.",
  "Previous welcome-email attempt has an unknown delivery outcome. Check the sender Sent folder before retrying.",
  "Candidate lifecycle status must be HR_APPROVED_FOR_PROBATION.",
  "Welcome-email job is cancelled.",
  "Welcome email was sent, but workflow finalization is pending. Retry the action.",
  "Welcome-email delivery outcome is unknown. Check the sender Sent folder before retrying.",
  "Welcome email was accepted by the provider, but delivery confirmation could not be stored. Check the sender Sent folder before retrying.",
  "The email provider is temporarily unavailable.",
  "Welcome-email delivery is not configured.",
  "The email provider rejected the welcome-email request.",
]);

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidUuid(value) {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function getKnownMessage(value) {
  if (typeof value !== "string") {
    return null;
  }

  const message = value.trim();
  return KNOWN_FUNCTION_MESSAGES.has(message) ? message : null;
}

async function getSafeFunctionErrorMessage(error) {
  const context = isRecord(error) ? error.context : null;

  if (context instanceof Response) {
    try {
      const responseBody = await context.clone().json();
      const responseMessage = isRecord(responseBody)
        ? getKnownMessage(responseBody.error)
        : null;

      if (responseMessage) {
        return responseMessage;
      }
    } catch {
      // Fall through to the safe allow-listed and generic checks.
    }
  }

  const directMessage = isRecord(error)
    ? getKnownMessage(error.message)
    : null;

  return directMessage ?? SAFE_FALLBACK_ERROR;
}

export async function sendCandidateWelcomeEmail(candidateId) {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
  const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
  const normalizedCandidateId =
    typeof candidateId === "string" ? candidateId.trim().toLowerCase() : "";

  if (!isValidUuid(normalizedCandidateId)) {
    throw new Error("A valid candidate ID is required.");
  }

  if (!supabase || !supabaseUrl || !supabaseAnonKey) {
    throw new Error(SAFE_FALLBACK_ERROR);
  }

  let result;

  try {
    result = await supabase.functions.invoke("send-welcome-mail", {
      body: {
        candidateId: normalizedCandidateId,
      },
    });
  } catch {
    throw new Error(SAFE_FALLBACK_ERROR);
  }

  if (result.error) {
    throw new Error(await getSafeFunctionErrorMessage(result.error));
  }

  const response = result.data;

  if (
    !isRecord(response) ||
    response.success !== true ||
    !isValidUuid(response.candidateId) ||
    response.candidateId.toLowerCase() !== normalizedCandidateId ||
    response.jobStatus !== "SUCCESS" ||
    response.lifecycleStatus !== "WELCOME_MAIL_SENT" ||
    typeof response.alreadyCompleted !== "boolean" ||
    typeof response.message !== "string" ||
    !response.message.trim()
  ) {
    throw new Error(SAFE_FALLBACK_ERROR);
  }

  return {
    success: true,
    candidateId: response.candidateId,
    jobStatus: response.jobStatus,
    lifecycleStatus: response.lifecycleStatus,
    alreadyCompleted: response.alreadyCompleted,
    message: response.message.trim(),
  };
}
