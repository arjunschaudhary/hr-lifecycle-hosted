import { supabase } from "./supabaseClient";

const BUCKET_NAME = "candidate-signed-offers";
const SAFE_LOAD_ERROR = "Unable to load signed-offer review records.";
const SAFE_VIEW_ERROR = "Unable to view the signed-offer PDF.";
const SAFE_ACTION_ERROR =
  "Unable to complete the signed-offer review. Refresh the page and try again.";

const UUID_SOURCE =
  "[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const UUID_PATTERN = new RegExp(`^${UUID_SOURCE}$`, "i");
const OBJECT_PATH_PATTERN = new RegExp(
  "^candidate/" +
    UUID_SOURCE +
    "/signed-offers/" +
    UUID_SOURCE +
    "\\.pdf$",
  "i",
);

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const isNonEmptyValue = (value) => {
  if (typeof value === "string") {
    return value.trim().length > 0;
  }

  return value !== null && value !== undefined;
};

const mapReviewRecord = (row) => {
  if (
    !isRecord(row) ||
    !isValidUuid(row.verification_id) ||
    !isValidUuid(row.candidate_id) ||
    (row.file_id !== null && row.file_id !== undefined && !isValidUuid(row.file_id)) ||
    (row.object_path !== null && row.object_path !== undefined && typeof row.object_path !== "string")
  ) {
    throw new Error(SAFE_LOAD_ERROR);
  }

  return {
    verificationId: row.verification_id,
    candidateId: row.candidate_id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    appliedRole: row.applied_role,
    mid: row.mid,
    lifecycleStatus: row.lifecycle_status,
    signedOfferStatus: row.signed_offer_status,
    signedOfferSubmittedAt: row.signed_offer_submitted_at,
    verifiedAt: row.verified_at,
    emailMatchStatus: row.email_match_status,
    phoneMatchStatus: row.phone_match_status,
    verificationNotes: row.verification_notes,
    fileId: row.file_id ?? null,
    objectPath: row.object_path ?? null,
    originalFilename: row.original_filename ?? null,
    mimeType: row.mime_type ?? null,
    fileSizeBytes: row.file_size_bytes ?? null,
    fileStatus: row.file_status ?? null,
    uploadedAt: row.uploaded_at ?? null,
  };
};

export async function fetchSignedOfferReviewQueue() {
  if (!supabase || typeof supabase.rpc !== "function") {
    throw new Error(SAFE_LOAD_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc("get_signed_offer_review_queue");

    if (error || !Array.isArray(data)) {
      throw new Error(SAFE_LOAD_ERROR);
    }

    return data.map(mapReviewRecord);
  } catch {
    throw new Error(SAFE_LOAD_ERROR);
  }
}

export async function getSignedOfferViewUrl({ objectPath } = {}) {
  if (
    typeof objectPath !== "string" ||
    !OBJECT_PATH_PATTERN.test(objectPath) ||
    !supabase?.storage ||
    typeof supabase.storage.from !== "function"
  ) {
    throw new Error(SAFE_VIEW_ERROR);
  }

  try {
    const storageBucket = supabase.storage.from(BUCKET_NAME);
    const { data, error } = await storageBucket.createSignedUrl(objectPath, 60);

    if (error || !data?.signedUrl) {
      throw new Error(SAFE_VIEW_ERROR);
    }

    return data.signedUrl;
  } catch {
    throw new Error(SAFE_VIEW_ERROR);
  }
}

export async function reviewSignedOffer({
  verificationId,
  targetStatus,
  verificationNotes,
} = {}) {
  const notes = typeof verificationNotes === "string" ? verificationNotes.trim() : "";

  if (
    !supabase ||
    typeof supabase.rpc !== "function" ||
    !isValidUuid(verificationId) ||
    !["SIGNED_OFFER_VERIFIED", "MISMATCH_REVIEW"].includes(targetStatus) ||
    notes.length > 2000 ||
    (targetStatus === "MISMATCH_REVIEW" && !notes)
  ) {
    throw new Error(SAFE_ACTION_ERROR);
  }

  try {
    const { data, error } = await supabase.rpc("review_candidate_signed_offer", {
      p_verification_id: verificationId,
      p_target_status: targetStatus,
      p_verification_notes: notes,
    });

    const expectedFileStatus =
      targetStatus === "SIGNED_OFFER_VERIFIED" ? "VERIFIED" : "MISMATCH_REVIEW";

    if (
      error ||
      !isRecord(data) ||
      !isValidUuid(data.verificationId) ||
      data.verificationId !== verificationId ||
      !isValidUuid(data.candidateId) ||
      !isValidUuid(data.fileId) ||
      data.signedOfferStatus !== targetStatus ||
      data.lifecycleStatus !== targetStatus ||
      data.fileStatus !== expectedFileStatus ||
      !isNonEmptyValue(data.reviewedAt)
    ) {
      throw new Error(SAFE_ACTION_ERROR);
    }

    return data;
  } catch {
    throw new Error(SAFE_ACTION_ERROR);
  }
}
