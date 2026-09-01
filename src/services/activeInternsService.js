import { supabase } from "./supabaseClient";

const ACTIVE_INTERNS_EXIT_LOAD_ERROR =
  "Unable to load active intern Exit status.";
const EXIT_INITIATION_ERROR =
  "Unable to initiate the Exit process. Please try again.";
const SAFE_EXIT_INITIATION_MESSAGES = new Set([
  "Candidate is required.",
  "A valid Exit type is required.",
  "Exit date is required.",
  "Candidate was not found.",
  "No lifecycle record was found for this candidate.",
  "Exit can only be initiated for a candidate in the Active Interns workflow.",
  "An Exit process has already been initiated for this candidate.",
  "Exit cannot be initiated because multiple candidate pods cover the exit date.",
]);

function getSafeExitInitiationMessage(error) {
  const message =
    error && typeof error.message === "string" ? error.message.trim() : "";

  return SAFE_EXIT_INITIATION_MESSAGES.has(message)
    ? message
    : EXIT_INITIATION_ERROR;
}

export async function fetchActiveInterns() {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const { data: interns, error: internsError } = await supabase
    .from("active_interns_view")
    .select("*")
    .order("full_name", { ascending: true });

  if (internsError) {
    throw internsError;
  }

  if (!interns || interns.length === 0) {
    return [];
  }

  const { data: exitCases, error: exitCasesError } = await supabase.rpc(
    "get_hr_open_exit_cases",
  );

  if (exitCasesError) {
    throw new Error(ACTIVE_INTERNS_EXIT_LOAD_ERROR);
  }

  const exitCasesMap = {};
  (exitCases || []).forEach((exitCase) => {
    if (!exitCasesMap[exitCase.candidate_id]) {
      exitCasesMap[exitCase.candidate_id] = exitCase;
    }
  });

  return interns.map((row) => {
    const ec = exitCasesMap[row.candidate_id];
    return {
      ...row,
      exit_case_id: ec?.exit_case_id || null,
      exit_case_status: ec?.overall_status || null,
      has_active_exit: Boolean(ec),
    };
  });
}

/**
 * Initiates an Exit process for an active intern through the secure RPC.
 */
export async function initiateExitForCandidate({
  candidateId,
  exitType,
  exitDate,
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  if (!candidateId) {
    throw new Error("Candidate ID is required.");
  }

  if (!exitType) {
    throw new Error("Exit Type is required.");
  }

  const effectiveExitDate =
    exitDate || new Date().toISOString().split("T")[0];
  const { data, error } = await supabase.rpc("initiate_candidate_exit", {
    p_candidate_id: candidateId,
    p_exit_type: exitType,
    p_exit_date: effectiveExitDate,
  });

  if (error) {
    throw new Error(getSafeExitInitiationMessage(error));
  }

  return data;
}
