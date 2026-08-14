import { supabase } from "./supabaseClient";
import { LIFECYCLE_SUPPORTED_ROLE_CODES } from "../constants/roleOptions";

function parseDateOnly(dateValue) {
  const [year, month, day] = String(dateValue || "")
    .split("-")
    .map(Number);

  if (!year || !month || !day) {
    throw new Error("A valid probation start date is required.");
  }

  return new Date(Date.UTC(year, month - 1, day));
}

function addCalendarDays(dateValue, daysToAdd) {
  const date = parseDateOnly(dateValue);
  const millisecondsPerDay = 24 * 60 * 60 * 1000;

  return new Date(date.getTime() + daysToAdd * millisecondsPerDay)
    .toISOString()
    .split("T")[0];
}

function getInternshipDurationDays(durationMonths) {
  if (Number(durationMonths) === 4) return 120;
  if (Number(durationMonths) === 3) return 90;

  throw new Error("Internship duration must be 3 or 4 months.");
}
function getValidatedRoleCode(roleCode) {
  const normalizedRoleCode = String(roleCode || "").trim().toUpperCase();

  if (!normalizedRoleCode) {
    throw new Error("Role code is missing. MID generation cannot continue.");
  }

  const isKnownRoleCode =
    LIFECYCLE_SUPPORTED_ROLE_CODES.includes(normalizedRoleCode);

  if (!isKnownRoleCode) {
    throw new Error("Role code is not valid. MID generation cannot continue.");
  }

  return normalizedRoleCode;
}

function getNameCode(fullName) {
  const words = String(fullName || "")
    .replace(/[^\w\s]/g, "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (words.length === 0) return "";

  if (words.length === 1) {
    return words[0].slice(0, 2).toUpperCase();
  }

  return (
    words[0][0] +
    words[words.length - 1][0]
  ).toUpperCase();
}

function getYearCode() {
  return new Date().getFullYear().toString().slice(-2);
}

function getNextSerial(existingMids, roleCode, nameCode, yearCode) {
  const nextNumber =
    existingMids.reduce((maxSerial, mid) => {
      const match = String(mid).match(
        new RegExp(
          `^JCF-${roleCode}-${nameCode}-${yearCode}(\\d{3})$`
        )
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
  updateFields = {},
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const lifecycleUpdate = {
    lifecycle_status: toStatus,
    updated_at: now,
    ...updateFields,
  };

    const { data: updatedLifecycle, error: updateError } = await supabase
      .from("hr_lifecycle")
      .update(lifecycleUpdate)
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
export async function approveCandidateForProbation({
  candidateId,
  joiningDate,
  durationMonths,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();
  const durationDays = getInternshipDurationDays(durationMonths);
  const probationEndDate = addCalendarDays(joiningDate, 7);

  const endDate = addCalendarDays(
    joiningDate,
    durationDays - 1
  );

  const { data: updatedLifecycle, error: updateError } =
    await supabase
      .from("hr_lifecycle")
      .update({
        lifecycle_status: "HR_APPROVED_FOR_PROBATION",

        probation_start_date: joiningDate,

        probation_end_date: probationEndDate,

        internship_duration_months: Number(durationMonths),

        original_end_date: endDate,

        current_end_date: endDate,

        probation_extension_count: 0,

        updated_at: now,
      })
      .eq("candidate_id", candidateId)
      .eq("lifecycle_status", "HR_REVIEW_PENDING")
      .select("candidate_id")
      .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error(
      "Candidate lifecycle status did not match HR_REVIEW_PENDING."
    );
  }

  const { error: logError } = await supabase
    .from("hr_activity_logs")
    .insert({
      candidate_id: candidateId,

      activity_type: "HR_APPROVED_FOR_PROBATION",

      from_status: "HR_REVIEW_PENDING",

      to_status: "HR_APPROVED_FOR_PROBATION",

      remarks: `Candidate approved for probation (${durationMonths} month internship)`,

      activity_status: "SUCCESS",

      performed_by: performedBy,

      performed_at: now,
    });

  if (logError) {
    throw logError;
  }

  return true;
}

export async function extendCandidateProbation({
  candidateId,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: lifecycle, error: lifecycleError } = await supabase
    .from("hr_lifecycle")
    .select(
      "probation_end_date,lifecycle_status,probation_extension_count"
    )
    .eq("candidate_id", candidateId)
    .maybeSingle();

  if (lifecycleError) {
    throw lifecycleError;
  }

  if (!lifecycle || lifecycle.lifecycle_status !== "PROBATION_REVIEW") {
    throw new Error("Candidate is not in PROBATION_REVIEW status.");
  }

  if (Number(lifecycle.probation_extension_count) !== 0) {
    throw new Error("Probation may only be extended once.");
  }

  if (!lifecycle.probation_end_date) {
    throw new Error("Probation end date is required to extend probation.");
  }

  const probationEndDate = addCalendarDays(
    lifecycle.probation_end_date,
    7
  );

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: "PROBATION_EXTENDED",
      probation_end_date: probationEndDate,
      probation_extension_count: 1,
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", "PROBATION_REVIEW")
    .eq("probation_extension_count", 0)
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate probation extension was not allowed.");
  }

  const { error: logError } = await supabase
    .from("hr_activity_logs")
    .insert({
      candidate_id: candidateId,
      activity_type: "PROBATION_EXTENDED",
      from_status: "PROBATION_REVIEW",
      to_status: "PROBATION_EXTENDED",
      remarks: "Candidate probation extended by HR",
      activity_status: "SUCCESS",
      performed_by: performedBy,
      performed_at: now,
    });

  if (logError) {
    throw logError;
  }

  return true;
}

export async function generateCandidateMidAfterProbation({
  candidateId,
  fullName,
  roleCode,
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

  const { data: candidate, error: candidateError } = await supabase
    .from("master_candidates")
    .select("full_name,role_code")
    .eq("candidate_id", candidateId)
    .maybeSingle();

  if (candidateError) {
    throw candidateError;
  }

  let mid = lifecycle.mid || existingMid;

  if (!mid) {
    const validatedRoleCode = getValidatedRoleCode(
      candidate?.role_code || roleCode
    );

    const nameCode = getNameCode(candidate?.full_name || fullName);

    if (!nameCode) {
      throw new Error("Candidate name is required for MID generation.");
    }
    const yearCode = getYearCode();

    const { data: existingLifecycleRows, error: midsError } = await supabase
  .from("hr_lifecycle")
  .select("mid")
  .ilike(
    "mid",
    `JCF-${validatedRoleCode}-${nameCode}-${yearCode}%`
  );

    if (midsError) {
      throw midsError;
    }

    const existingMids = (existingLifecycleRows || [])
      .map((row) => row.mid)
      .filter(Boolean);
    const serial = getNextSerial(
  existingMids,
  validatedRoleCode,
  nameCode,
  yearCode
);

    mid = `JCF-${validatedRoleCode}-${nameCode}-${yearCode}${serial}`;
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

export async function generateOfferLetterRecordAfterMid({
  candidateId,
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

  if (!lifecycle || lifecycle.lifecycle_status !== "MID_GENERATED") {
    throw new Error("Candidate is not in MID_GENERATED status.");
  }

  const mid = lifecycle.mid || existingMid;

  if (!mid) {
    throw new Error("MID is required before generating offer letter record.");
  }

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: "OFFER_LETTER_GENERATED",
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", "MID_GENERATED")
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match MID_GENERATED.");
  }

  const offerLetterNumber = `OL-${mid}`;
  const { data: existingOffer, error: existingOfferError } = await supabase
    .from("hr_offer_letters")
    .select("offer_letter_id,offer_letter_number")
    .eq("candidate_id", candidateId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingOfferError) {
    throw existingOfferError;
  }

  if (existingOffer) {
    const { error: offerUpdateError } = await supabase
      .from("hr_offer_letters")
      .update({
        offer_status: "OFFER_LETTER_GENERATED",
        offer_letter_number: existingOffer.offer_letter_number || offerLetterNumber,
        generated_at: now,
        updated_at: now,
      })
      .eq("offer_letter_id", existingOffer.offer_letter_id);

    if (offerUpdateError) {
      throw offerUpdateError;
    }
  } else {
    const { error: offerInsertError } = await supabase
      .from("hr_offer_letters")
      .insert({
        candidate_id: candidateId,
        offer_status: "OFFER_LETTER_GENERATED",
        offer_letter_number: offerLetterNumber,
        generated_at: now,
        created_at: now,
        updated_at: now,
      });

    if (offerInsertError) {
      throw offerInsertError;
    }
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: "OFFER_LETTER_GENERATED",
    from_status: "MID_GENERATED",
    to_status: "OFFER_LETTER_GENERATED",
    remarks: "Offer letter record generated after MID generation",
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return { offerLetterNumber };
}

export async function markOfferLetterSent({
  candidateId,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: "OFFER_LETTER_SENT",
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", "OFFER_LETTER_GENERATED")
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match OFFER_LETTER_GENERATED.");
  }

  const { data: existingOffer, error: existingOfferError } = await supabase
    .from("hr_offer_letters")
    .select("offer_letter_id")
    .eq("candidate_id", candidateId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existingOfferError) {
    throw existingOfferError;
  }

  if (existingOffer) {
    const { error: offerUpdateError } = await supabase
      .from("hr_offer_letters")
      .update({
        offer_status: "OFFER_LETTER_SENT",
        sent_at: now,
        updated_at: now,
      })
      .eq("offer_letter_id", existingOffer.offer_letter_id);

    if (offerUpdateError) {
      throw offerUpdateError;
    }
  } else {
    const { error: offerInsertError } = await supabase
      .from("hr_offer_letters")
      .insert({
        candidate_id: candidateId,
        offer_status: "OFFER_LETTER_SENT",
        sent_at: now,
        created_at: now,
        updated_at: now,
      });

    if (offerInsertError) {
      throw offerInsertError;
    }
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: "OFFER_LETTER_SENT",
    from_status: "OFFER_LETTER_GENERATED",
    to_status: "OFFER_LETTER_SENT",
    remarks: "Offer letter marked as sent by HR",
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return true;
}

export async function markCandidateActiveAfterOfferSent({
  candidateId,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: "ACTIVE",
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", "OFFER_LETTER_SENT")
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match OFFER_LETTER_SENT.");
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: "ACTIVE",
    from_status: "OFFER_LETTER_SENT",
    to_status: "ACTIVE",
    remarks: "Candidate marked as active intern by HR",
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return true;
}

export async function markSignedOfferSubmitted({
  candidateId,
  performedBy = "HR",
}) {
  if (!supabase) {
    throw new Error("Supabase environment variables are not configured.");
  }

  const now = new Date().toISOString();

  const { data: updatedLifecycle, error: updateError } = await supabase
    .from("hr_lifecycle")
    .update({
      lifecycle_status: "SIGNED_OFFER_SUBMITTED",
      updated_at: now,
    })
    .eq("candidate_id", candidateId)
    .eq("lifecycle_status", "ACTIVE")
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match ACTIVE.");
  }

  const { data: existingVerification, error: existingVerificationError } =
    await supabase
      .from("signed_offer_verifications")
      .select("verification_id")
      .eq("candidate_id", candidateId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

  if (existingVerificationError) {
    throw existingVerificationError;
  }

  if (existingVerification) {
    const { error: verificationUpdateError } = await supabase
      .from("signed_offer_verifications")
      .update({
        signed_offer_status: "SIGNED_OFFER_SUBMITTED",
        signed_offer_submitted_at: now,
        updated_at: now,
      })
      .eq("verification_id", existingVerification.verification_id);

    if (verificationUpdateError) {
      throw verificationUpdateError;
    }
  } else {
    const { error: verificationInsertError } = await supabase
      .from("signed_offer_verifications")
      .insert({
        candidate_id: candidateId,
        signed_offer_status: "SIGNED_OFFER_SUBMITTED",
        signed_offer_submitted_at: now,
        created_at: now,
        updated_at: now,
      });

    if (verificationInsertError) {
      throw verificationInsertError;
    }
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: "SIGNED_OFFER_SUBMITTED",
    from_status: "ACTIVE",
    to_status: "SIGNED_OFFER_SUBMITTED",
    remarks: "Signed offer marked as submitted by HR",
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return true;
}

export async function decideSignedOfferVerification({
  candidateId,
  toStatus,
  activityType,
  remarks,
  verificationNotes,
  markAsMatched = false,
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
    .eq("lifecycle_status", "SIGNED_OFFER_SUBMITTED")
    .select("candidate_id")
    .maybeSingle();

  if (updateError) {
    throw updateError;
  }

  if (!updatedLifecycle) {
    throw new Error("Candidate lifecycle status did not match SIGNED_OFFER_SUBMITTED.");
  }

  const { data: existingVerification, error: existingVerificationError } =
    await supabase
      .from("signed_offer_verifications")
      .select("verification_id,email_match_status,phone_match_status")
      .eq("candidate_id", candidateId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

  if (existingVerificationError) {
    throw existingVerificationError;
  }

  const verificationValues = {
    signed_offer_status: toStatus,
    verification_notes: verificationNotes,
    updated_at: now,
  };

  if (toStatus === "SIGNED_OFFER_VERIFIED") {
    verificationValues.verified_at = now;
  }

  if (markAsMatched && !existingVerification?.email_match_status) {
    verificationValues.email_match_status = "MATCHED";
  }

  if (markAsMatched && !existingVerification?.phone_match_status) {
    verificationValues.phone_match_status = "MATCHED";
  }

  if (existingVerification) {
    const { error: verificationUpdateError } = await supabase
      .from("signed_offer_verifications")
      .update(verificationValues)
      .eq("verification_id", existingVerification.verification_id);

    if (verificationUpdateError) {
      throw verificationUpdateError;
    }
  } else {
    const { error: verificationInsertError } = await supabase
      .from("signed_offer_verifications")
      .insert({
        candidate_id: candidateId,
        signed_offer_submitted_at: now,
        created_at: now,
        ...verificationValues,
      });

    if (verificationInsertError) {
      throw verificationInsertError;
    }
  }

  const { error: logError } = await supabase.from("hr_activity_logs").insert({
    candidate_id: candidateId,
    activity_type: activityType,
    from_status: "SIGNED_OFFER_SUBMITTED",
    to_status: toStatus,
    remarks,
    activity_status: "SUCCESS",
    performed_by: performedBy,
    performed_at: now,
  });

  if (logError) {
    throw logError;
  }

  return true;
}
