import { supabase } from "./supabaseClient";

const allowedUploadSourceStatuses = ["ACTIVE", "OFFER_LETTER_SENT"];

export async function submitSignedOfferUpload(formData) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const mid = formData.mid?.trim().toUpperCase();
  const email = formData.email?.trim().toLowerCase();
  const phone = formData.phone?.trim();

  if (!mid) {
    throw new Error("MID is required.");
  }

  if (!email) {
    throw new Error("Registered email is required.");
  }

  if (!phone) {
    throw new Error("Phone is required.");
  }

  const { data: lifecycle, error: lifecycleError } = await supabase
    .from("hr_lifecycle")
    .select("candidate_id, mid, lifecycle_status")
    .eq("mid", mid)
    .maybeSingle();

  if (lifecycleError) {
    throw lifecycleError;
  }

  if (!lifecycle) {
    throw new Error("No candidate found with this MID.");
  }

  if (!allowedUploadSourceStatuses.includes(lifecycle.lifecycle_status)) {
    throw new Error("Signed offer can only be submitted for active or offer-sent candidates.");
  }

  const { data: candidate, error: candidateError } = await supabase
    .from("master_candidates")
    .select("candidate_id, email, phone")
    .eq("candidate_id", lifecycle.candidate_id)
    .single();

  if (candidateError) {
    throw candidateError;
  }

  const emailMatchStatus =
    candidate.email?.trim().toLowerCase() === email ? "MATCHED" : "MISMATCH";

  const phoneMatchStatus =
    candidate.phone?.trim() === phone ? "MATCHED" : "MISMATCH";

  const nextLifecycleStatus =
    emailMatchStatus === "MATCHED" && phoneMatchStatus === "MATCHED"
      ? "SIGNED_OFFER_SUBMITTED"
      : "MISMATCH_REVIEW";

  const { data: existingVerification, error: existingError } = await supabase
    .from("signed_offer_verifications")
    .select("verification_id")
    .eq("candidate_id", lifecycle.candidate_id)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }

  const verificationPayload = {
    candidate_id: lifecycle.candidate_id,
    signed_offer_status: nextLifecycleStatus,
    signed_offer_submitted_at: now,
    email_match_status: emailMatchStatus,
    phone_match_status: phoneMatchStatus,
    verification_notes:
      nextLifecycleStatus === "SIGNED_OFFER_SUBMITTED"
        ? "Signed offer submitted with matching details"
        : "Signed offer submitted but requires mismatch review",
    updated_at: now,
  };

  if (existingVerification) {
    const { error: updateVerificationError } = await supabase
      .from("signed_offer_verifications")
      .update(verificationPayload)
      .eq("verification_id", existingVerification.verification_id);

    if (updateVerificationError) {
      throw updateVerificationError;
    }
  } else {
    const { error: insertVerificationError } = await supabase
      .from("signed_offer_verifications")
      .insert({
        ...verificationPayload,
        created_at: now,
      });

    if (insertVerificationError) {
      throw insertVerificationError;
    }
  }

  const { data: updatedLifecycle, error: lifecycleUpdateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: nextLifecycleStatus,
      updated_at: now,
    })
    .eq("candidate_id", lifecycle.candidate_id)
    .in("lifecycle_status", allowedUploadSourceStatuses)
    .select("candidate_id")
    .maybeSingle();

  if (lifecycleUpdateError) {
    throw lifecycleUpdateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match an allowed signed offer upload source status.");
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: lifecycle.candidate_id,
    activity_type: nextLifecycleStatus,
    from_status: lifecycle.lifecycle_status,
    to_status: nextLifecycleStatus,
    remarks:
      nextLifecycleStatus === "SIGNED_OFFER_SUBMITTED"
        ? "Signed offer submitted by intern"
        : "Signed offer submitted with mismatch and moved to review",
    activity_status: "SUCCESS",
    performed_by: "Intern",
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return {
    candidate_id: lifecycle.candidate_id,
    status: nextLifecycleStatus,
    email_match_status: emailMatchStatus,
    phone_match_status: phoneMatchStatus,
  };
}
