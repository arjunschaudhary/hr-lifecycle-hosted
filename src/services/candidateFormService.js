import { supabase } from "./supabaseClient";

function emptyToNull(value) {
  const normalizedValue = String(value || "").trim();
  return normalizedValue || null;
}

export async function submitCandidateForm(formData) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const email = formData.email?.trim().toLowerCase();

  if (!email) {
    throw new Error("Email is required.");
  }

  const { data: existingCandidate, error: duplicateError } = await supabase
    .from("master_candidates")
    .select("candidate_id, email")
    .eq("email", email)
    .maybeSingle();

  if (duplicateError) {
    throw duplicateError;
  }

  if (existingCandidate) {
    throw new Error("Candidate with this email already exists.");
  }

  const fullName =
    formData.full_name?.trim() ||
    `${formData.first_name || ""} ${formData.last_name || ""}`.trim();

  if (!fullName) {
    throw new Error("Full name is required.");
  }

  const nameParts = fullName.split(/\s+/).filter(Boolean);
  const firstName = emptyToNull(formData.first_name) || nameParts[0] || null;
  const lastName =
    emptyToNull(formData.last_name) ||
    (nameParts.length > 1 ? nameParts.slice(1).join(" ") : null);

  const { data: candidate, error: candidateError } = await supabase
    .from("master_candidates")
    .insert({
      first_name: firstName,
      last_name: lastName,
      full_name: fullName,
      email,
      phone: emptyToNull(formData.phone),
      alternate_phone: emptyToNull(formData.alternate_phone),
      address: emptyToNull(formData.address),
      city: emptyToNull(formData.city),
      state: emptyToNull(formData.state),
      applied_role: emptyToNull(formData.applied_role),
      role_code: emptyToNull(formData.role_code),
      department: emptyToNull(formData.department),
      qualification: emptyToNull(formData.qualification),
      college_name: emptyToNull(formData.college_name),
      source: emptyToNull(formData.source) || "Candidate Form",
      referral_name: emptyToNull(formData.referral_name),
      availability_status: emptyToNull(formData.availability_status),
      notes: emptyToNull(formData.notes),
      submitted_at: now,
      created_at: now,
      updated_at: now,
    })
    .select()
    .single();

  if (candidateError) {
    throw candidateError;
  }

  const { error: lifecycleError } = await supabase.from("hr_lifecycle").insert({
    candidate_id: candidate.candidate_id,
    lifecycle_status: "HR_REVIEW_PENDING",
    created_at: now,
    updated_at: now,
  });

  if (lifecycleError) {
    throw lifecycleError;
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidate.candidate_id,
    activity_type: "CANDIDATE_FORM_SUBMITTED",
    from_status: null,
    to_status: "HR_REVIEW_PENDING",
    remarks: "Candidate form submitted and moved to HR review pending",
    activity_status: "SUCCESS",
    performed_by: "Candidate",
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return candidate;
}
