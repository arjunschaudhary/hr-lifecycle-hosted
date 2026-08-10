import { supabase } from "./supabaseClient";

const BUCKET_NAME = "candidate-signed-offers";
const MAX_FILE_SIZE_BYTES = 10485760;
const REQUIRED_MIME_TYPE = "application/pdf";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const STORAGE_UPLOAD_ERROR =
  "Unable to upload the signed offer. Please try again.";
const FINALIZATION_ERROR =
  "Unable to complete the signed-offer submission. Please try again.";
const CLEANUP_ERROR =
  "Unable to complete the signed-offer submission or clean up the uploaded file. Please contact HR before trying again.";

const isRecord = (value) =>
  value !== null && typeof value === "object" && !Array.isArray(value);

const isValidUuid = (value) =>
  typeof value === "string" && UUID_PATTERN.test(value);

const hasNonEmptyValue = (value) => {
  if (typeof value === "string") {
    return value.trim().length > 0;
  }

  return value !== null && value !== undefined;
};

const getSecureUploadUuid = () => {
  if (
    typeof globalThis.crypto?.randomUUID !== "function"
  ) {
    throw new Error("Unable to prepare the signed-offer upload. Please try again.");
  }

  const uploadUuid = globalThis.crypto.randomUUID();

  if (!isValidUuid(uploadUuid)) {
    throw new Error("Unable to prepare the signed-offer upload. Please try again.");
  }

  return uploadUuid;
};

const validateFile = (file) => {
  if (typeof File === "undefined" || !(file instanceof File)) {
    throw new Error("Please select a PDF file.");
  }

  const originalFilename = typeof file.name === "string" ? file.name.trim() : "";

  if (
    !originalFilename ||
    originalFilename.length > 255 ||
    !originalFilename.toLowerCase().endsWith(".pdf") ||
    originalFilename.includes("/") ||
    originalFilename.includes("\\") ||
    originalFilename.includes("..")
  ) {
    throw new Error("Please select a valid PDF file.");
  }

  if (
    !Number.isFinite(file.size) ||
    file.size <= 0 ||
    file.size > MAX_FILE_SIZE_BYTES
  ) {
    throw new Error("PDF files must be greater than 0 bytes and no larger than 10 MB.");
  }

  if (file.type !== REQUIRED_MIME_TYPE) {
    throw new Error("Please select a PDF file.");
  }

  return originalFilename;
};

const isValidFinalizationResponse = (value, candidateId, objectPath) =>
  isRecord(value) &&
  isValidUuid(value.fileId) &&
  isValidUuid(value.candidateId) &&
  value.candidateId.toLowerCase() === candidateId.toLowerCase() &&
  isValidUuid(value.verificationId) &&
  value.objectPath === objectPath &&
  value.signedOfferStatus === "SIGNED_OFFER_SUBMITTED" &&
  value.lifecycleStatus === "SIGNED_OFFER_SUBMITTED" &&
  hasNonEmptyValue(value.submittedAt);

// Shared helper: upload a PDF file to the candidate-signed-offers bucket.
// Returns { storageBucket, objectPath, originalFilename }.

const uploadSignedOfferFile = async (candidateId, file) => {
  const normalizedCandidateId = candidateId.trim().toLowerCase();
  const originalFilename = validateFile(file);
  const uploadUuid = getSecureUploadUuid();
  const objectPath = `candidate/${normalizedCandidateId}/signed-offers/${uploadUuid}.pdf`;

  let storageBucket;

  try {
    storageBucket = supabase.storage.from(BUCKET_NAME);
  } catch {
    throw new Error(STORAGE_UPLOAD_ERROR);
  }

  if (
    !storageBucket ||
    typeof storageBucket.upload !== "function" ||
    typeof storageBucket.remove !== "function"
  ) {
    throw new Error(STORAGE_UPLOAD_ERROR);
  }

  let uploadResult;

  try {
    uploadResult = await storageBucket.upload(objectPath, file, {
      upsert: false,
      contentType: REQUIRED_MIME_TYPE,
    });
  } catch (storageException) {
    console.error("[SignedOffer upload] Storage.upload() threw:", storageException, "| path:", objectPath);
    throw new Error(STORAGE_UPLOAD_ERROR);
  }

  if (!isRecord(uploadResult) || uploadResult.error) {
    console.error("[SignedOffer upload] Storage.upload() returned error:", uploadResult?.error, "| path:", objectPath);
    throw new Error(STORAGE_UPLOAD_ERROR);
  }

  return { storageBucket, objectPath, originalFilename, normalizedCandidateId };
};

const removeUploadedObject = async (storageBucket, objectPath) => {
  try {
    const cleanupResult = await storageBucket.remove([objectPath]);
    return isRecord(cleanupResult) && !cleanupResult.error;
  } catch {
    return false;
  }
};

const throwFinalizationError = async (storageBucket, objectPath) => {
  const cleanupSucceeded = await removeUploadedObject(storageBucket, objectPath);

  throw new Error(cleanupSucceeded ? FINALIZATION_ERROR : CLEANUP_ERROR);
};

export async function submitCurrentCandidateSignedOffer({ candidateId, file } = {}) {
  if (
    !supabase ||
    typeof supabase.rpc !== "function" ||
    !supabase.storage ||
    typeof supabase.storage.from !== "function"
  ) {
    throw new Error("Signed-offer upload is not available. Please try again.");
  }

  if (typeof candidateId !== "string" || !isValidUuid(candidateId.trim())) {
    throw new Error("Candidate reference is invalid.");
  }

  const { storageBucket, objectPath, originalFilename, normalizedCandidateId } =
    await uploadSignedOfferFile(candidateId, file);

  let rpcResult;

  try {
    rpcResult = await supabase.rpc("finalize_current_candidate_signed_offer", {
      p_object_path: objectPath,
      p_original_filename: originalFilename,
    });
  } catch {
    await throwFinalizationError(storageBucket, objectPath);
  }

  if (
    !isRecord(rpcResult) ||
    rpcResult.error ||
    !isValidFinalizationResponse(rpcResult.data, normalizedCandidateId, objectPath)
  ) {
    await throwFinalizationError(storageBucket, objectPath);
  }

  return rpcResult.data;
}

export async function resubmitCurrentCandidateSignedOffer({ candidateId, file } = {}) {
  if (
    !supabase ||
    typeof supabase.rpc !== "function" ||
    !supabase.storage ||
    typeof supabase.storage.from !== "function"
  ) {
    throw new Error("Signed-offer re-upload is not available. Please try again.");
  }

  if (typeof candidateId !== "string" || !isValidUuid(candidateId.trim())) {
    throw new Error("Candidate reference is invalid.");
  }

  // ── DIAGNOSTIC: log session + eligibility before touching Storage ──────────
  // Remove this block once the root cause is confirmed.
  try {
    const { data: authUser, error: authError } = await supabase.auth.getUser();
    console.group("[SignedOffer resubmit] Pre-upload diagnostic");
    console.log("1. supabase.auth.getUser():", authError ?? authUser?.user);

    const normalizedIdForDiag = candidateId.trim().toLowerCase();
    const diagUuid = typeof globalThis.crypto?.randomUUID === "function"
      ? globalThis.crypto.randomUUID()
      : "uuid-unavailable";
    const diagPath = `candidate/${normalizedIdForDiag}/signed-offers/${diagUuid}.pdf`;
    console.log("2. Object path that will be uploaded:", diagPath);
    console.log("   candidateId passed in (normalised):", normalizedIdForDiag);

    const { data: diagData, error: diagError } = await supabase.rpc(
      "debug_signed_offer_resubmit_eligibility",
    );
    if (diagError) {
      console.warn("3. debug_signed_offer_resubmit_eligibility() RPC error:", diagError);
    } else {
      console.log("3. debug_signed_offer_resubmit_eligibility():", diagData);
      if (diagData && !diagData.uploadAllowed) {
        console.warn("   ⚠️  uploadAllowed = false — failing conditions:");
        if (!diagData.userIsActive)    console.warn("      ✗ current_user_is_active() = false");
        if (!diagData.isCandidate)     console.warn("      ✗ current_user_has_role(CANDIDATE) = false");
        if (!diagData.candidateId)     console.warn("      ✗ current_candidate_id() = null");
        if (diagData.case1 && !diagData.case1.passes) {
          console.warn("      ✗ Case 1 (first-time) fails:");
          if (!diagData.case1.lifecycleOk)      console.warn("          lifecycle != ACTIVE");
          if (!diagData.case1.noActiveFile)      console.warn("          active file already exists");
          if (!diagData.case1.noActiveSov)       console.warn("          active verification already exists");
          if (!diagData.case1.noStorageObjects)  console.warn("          storage objects already in path");
        }
        if (diagData.case2 && !diagData.case2.passes) {
          console.warn("      ✗ Case 2 (re-upload) fails:");
          if (!diagData.case2.lifecycleOk)           console.warn("          lifecycle != MISMATCH_REVIEW (actual:", diagData.lifecycleStatus, ")");
          if (!diagData.case2.mismatchFileExists)     console.warn("          no MISMATCH_REVIEW file found");
          if (!diagData.case2.noSubmittedOrVerified)  console.warn("          SUBMITTED or VERIFIED file still exists");
          if (!diagData.case2.mismatchSovExists)      console.warn("          no MISMATCH_REVIEW verification found");
        }
      } else if (diagData?.uploadAllowed) {
        console.log("   ✓ uploadAllowed = true — Storage upload should succeed.");
        console.log("   Confirm the path above matches candidate/" + diagData.candidateId + "/signed-offers/<uuid>.pdf");
      }
    }
    console.groupEnd();
  } catch (diagEx) {
    console.warn("[SignedOffer resubmit] Diagnostic failed (non-blocking):", diagEx);
  }
  // ── END DIAGNOSTIC ──────────────────────────────────────────────────────────

  const { storageBucket, objectPath, originalFilename, normalizedCandidateId } =
    await uploadSignedOfferFile(candidateId, file);

  let rpcResult;

  try {
    rpcResult = await supabase.rpc("resubmit_current_candidate_signed_offer", {
      p_object_path: objectPath,
      p_original_filename: originalFilename,
    });
  } catch {
    await throwFinalizationError(storageBucket, objectPath);
  }

  if (
    !isRecord(rpcResult) ||
    rpcResult.error ||
    !isValidFinalizationResponse(rpcResult.data, normalizedCandidateId, objectPath)
  ) {
    await throwFinalizationError(storageBucket, objectPath);
  }

  return rpcResult.data;
}
