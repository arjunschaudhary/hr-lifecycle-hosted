import { supabase } from "./supabaseClient";

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

  // Fetch exit cases for active candidates to determine exit initiation status
  const candidateIds = interns.map((i) => i.candidate_id).filter(Boolean);
  let exitCasesMap = {};

  if (candidateIds.length > 0) {
    const { data: exitCases } = await supabase
      .from("exit_cases")
      .select("exit_case_id, candidate_id, overall_status, candidate_form_completed, hr_form_completed")
      .in("candidate_id", candidateIds)
      .order("created_at", { ascending: false });

    if (exitCases) {
      exitCases.forEach((ec) => {
        if (!exitCasesMap[ec.candidate_id]) {
          exitCasesMap[ec.candidate_id] = ec;
        }
      });
    }
  }

  return interns.map((row) => {
    const ec = exitCasesMap[row.candidate_id];
    return {
      ...row,
      exit_case_id: ec?.exit_case_id || null,
      exit_case_status: ec?.overall_status || null,
      has_active_exit: Boolean(ec && ec.overall_status !== "COMPLETED"),
    };
  });
}

/**
 * Initiates an exit process for an active intern.
 * Inserts a record into exit_cases with overall_status = 'INITIATED'.
 */
export async function initiateExitForCandidate({
  candidateId,
  exitType,
  exitDate,
  notes,
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

  // 1. Verify no active exit case already exists
  const { data: existingCases, error: checkError } = await supabase
    .from("exit_cases")
    .select("exit_case_id, overall_status")
    .eq("candidate_id", candidateId)
    .order("created_at", { ascending: false });

  if (checkError) {
    throw checkError;
  }

  const activeCase = (existingCases || []).find(
    (c) => c.overall_status !== "COMPLETED"
  );

  if (activeCase) {
    throw new Error("An exit process has already been initiated for this intern.");
  }

  // 2. Fetch candidate's hr_lifecycle details
  const { data: lifecycleRows, error: lcError } = await supabase
    .from("hr_lifecycle")
    .select("lifecycle_id, mid, lifecycle_status, updated_at")
    .eq("candidate_id", candidateId)
    .order("updated_at", { ascending: false })
    .limit(1);

  if (lcError) {
    throw lcError;
  }

  if (!lifecycleRows || lifecycleRows.length === 0) {
    throw new Error("No lifecycle record found for this candidate.");
  }

  const lifecycle = lifecycleRows[0];

  // Fetch candidate profile for department/pod_name_snapshot
  const { data: candidateRows } = await supabase
    .from("master_candidates")
    .select("department")
    .eq("candidate_id", candidateId)
    .limit(1);

  const podNameSnapshot = candidateRows?.[0]?.department || null;

  // Get authenticated HR user for initiated_by
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const initiatedBy = user?.id || null;

  // 3. Insert new exit_case record
  const payload = {
    candidate_id: candidateId,
    lifecycle_id: lifecycle.lifecycle_id,
    pod_id: null,
    initiated_by: initiatedBy,
    mid: lifecycle.mid || null,
    pod_name_snapshot: podNameSnapshot,
    exit_date: exitDate || new Date().toISOString().split("T")[0],
    exit_type: exitType,
    overall_status: "INITIATED",
    candidate_form_completed: false,
    hr_form_completed: false,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  const { data: insertedData, error: insertError } = await supabase
    .from("exit_cases")
    .insert(payload)
    .select()
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      throw new Error("An exit process has already been initiated for this intern.");
    }
    throw insertError;
  }

  return insertedData;
}