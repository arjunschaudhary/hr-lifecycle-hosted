import { supabase } from "./supabaseClient";

const roleCodeMap = {
  "business analyst intern": "BAI",
  "content intern": "CI",
  "data intern": "DAI",
  "design intern": "DSGI",
  "finance intern": "FI",
  "hr intern": "HRI",
  "marketing intern": "MI",
  "operation intern": "OPI",
  "operations intern": "OPI",
  "product intern": "PI",
  "qa intern": "QAI",
  "research intern": "RI",
  "software intern": "SWI",
  "support intern": "SUPI",
};

function getRoleCode(appliedRole) {
  const normalizedRole = String(appliedRole || "")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();

  return roleCodeMap[normalizedRole];
}

function getNameCode(fullName) {
  const words = String(fullName || "")
    .replace(/[^\w\s]/g, "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (words.length === 0) {
    return "";
  }

  if (words.length === 1) {
    return words[0].slice(0, 2).toUpperCase();
  }

  return words.map((word) => word[0]).join("").toUpperCase();
}

function getNextSerial(existingMids, roleCode) {
  const nextNumber =
    existingMids.reduce((maxSerial, mid) => {
      const match = String(mid).match(
        new RegExp(`^JCF-${roleCode}-[A-Z]+-(\\d{3})$`)
      );

      return match ? Math.max(maxSerial, Number(match[1])) : maxSerial;
    }, 0) + 1;

  return String(nextNumber).padStart(3, "0");
}

export async function updateCandidateLifecycleStatus({
  candidateId,
  fromStatus,
  toStatus,
  activityType,
  remarks = "",
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: toStatus,
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", fromStatus)
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    console.error("Error updating lifecycle status:", updateError);
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match the expected source status.");
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: activityType,
    from_status: fromStatus,
    to_status: toStatus,
    remarks,
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    console.error("Error inserting activity log:", logError);
    throw logError;
  }

  return true;
}

export async function generateCandidateMidAfterProbation({
  candidateId,
  fullName,
  appliedRole,
  existingMid,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: lifecycle, error: lifecycleError } = await supabase
    .from("hr_lifecycle")
    .select("mid,lifecycle_status")
    .eq("candidate_id", candidateId)
    .maybeSingle();

  if (lifecycleError) {
    throw lifecycleError;
  }

  if (!lifecycle || lifecycle.lifecycle_status !== "PROBATION_PASSED") {
    throw new Error("Candidate is not in PROBATION_PASSED status.");
  }

  let mid = lifecycle.mid || existingMid;

  if (!mid) {
    const roleCode = getRoleCode(appliedRole);

    if (!roleCode) {
      throw new Error("Role code not defined for this applied role.");
    }

    const nameCode = getNameCode(fullName);

    if (!nameCode) {
      throw new Error("Candidate name is required for MID generation.");
    }

    const { data: existingLifecycleRows, error: midsError } = await supabase
      .from("hr_lifecycle")
      .select("mid")
      .ilike("mid", `JCF-${roleCode}-%`);

    if (midsError) {
      throw midsError;
    }

    const existingMids = (existingLifecycleRows || [])
      .map((row) => row.mid)
      .filter(Boolean);
    const serial = getNextSerial(existingMids, roleCode);

    mid = `JCF-${roleCode}-${nameCode}-${serial}`;
  }

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: "MID_GENERATED",
      mid,
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", "PROBATION_PASSED")
    .select("candidate_id,mid")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match PROBATION_PASSED.");
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: "MID_GENERATED",
    from_status: "PROBATION_PASSED",
    to_status: "MID_GENERATED",
    remarks: "MID generated for candidate after probation passed",
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return { mid };
}
