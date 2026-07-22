import { supabase } from "./supabaseClient";

function emptyToNull(value) {
  const normalizedValue = String(value || "").trim();
  return normalizedValue || null;
}

export async function submitCandidateForm(formData) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const email = formData.email?.trim().toLowerCase();

  if (!email) {
    throw new Error("Email is required.");
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

  const { data: candidate, error } = await supabase
    .rpc("submit_candidate_application", {
      p_application: {
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
      },
    })
    .single();

  if (error) {
    if (error.code === "23505") {
      throw new Error("Candidate with this email already exists.");
    }

    throw error;
  }

  return candidate;
}
