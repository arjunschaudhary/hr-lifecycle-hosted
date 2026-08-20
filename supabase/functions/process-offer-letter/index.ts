import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  GmailProviderError,
  isGmailProviderError,
  sendEmailWithGmailAttachment,
} from "../_shared/gmailProvider.ts";
import {
  createGoogleWorkspaceProvider,
  isGoogleWorkspaceProviderError,
} from "../_shared/googleWorkspaceProvider.ts";
import {
  buildOfferLetterTemplate,
  type OfferLetterTemplate,
  type OfferLetterTemplateInput,
} from "../_shared/offerLetterTemplate.ts";
import { getCorsHeaders } from "../_shared/cors.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FILE_ID_PATTERN = /^[A-Za-z0-9_-]{10,255}$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MID_PATTERN = /^JCF-[A-Z0-9]{3}-[A-Z0-9_]{1,2}-[0-9]{5}$/;
const JOB_STATUSES = new Set([
  "PENDING",
  "PROCESSING",
  "SUCCESS",
  "FAILED",
  "RETRY",
  "CANCELLED",
]);
const UNKNOWN_DELIVERY_MESSAGE =
  "Offer-email delivery outcome is unknown. Check the sender Sent folder before retrying.";
const FINALIZATION_PENDING_MESSAGE =
  "Offer email was accepted, but workflow finalization is pending. Retry the worker.";

type ErrorDetails = {
  code?: string;
  message: string;
  status?: number;
};

type OfferLetterClaim = OfferLetterTemplateInput & {
  jobId: string;
  candidateId: string;
  offerLetterId: string;
  jobStatus: string;
  attemptCount: number;
  shouldProcessExternal: boolean;
  needsFinalization: boolean;
  alreadyCompleted: boolean;
  googleDocFileId: string | null;
  googlePdfFileId: string | null;
  documentsPreparedAt: string | null;
  emailAttemptedAt: string | null;
  gmailMessageId: string | null;
};

type DocumentRecordResult = {
  jobId: string;
  candidateId: string;
  offerLetterId: string;
  lifecycleStatus: "MID_GENERATED" | "OFFER_LETTER_GENERATED" | "ACTIVE";
  googleDocFileId: string;
  googlePdfFileId: string | null;
  documentsPreparedAt: string | null;
  documentsReady: boolean;
};

type FinalizationResult = {
  jobId: string;
  candidateId: string;
  offerLetterId: string;
  jobStatus: "SUCCESS";
  lifecycleStatus: "ACTIVE";
  offerStatus: "OFFER_LETTER_SENT";
  providerAcceptedAt: string;
  completedAt: string;
};

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
    this.name = "HttpError";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonBlank(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function isNullableText(value: unknown): value is string | null {
  return value === null || (typeof value === "string" && value.trim() !== "");
}

function isNullableFileId(value: unknown): value is string | null {
  return value === null ||
    (typeof value === "string" && FILE_ID_PATTERN.test(value));
}

function isNullableTimestamp(value: unknown): value is string | null {
  return value === null ||
    (typeof value === "string" && !Number.isNaN(Date.parse(value)));
}

function createJsonResponse(
  request: Request,
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...getCorsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function extractBearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer\s+([^\s]+)$/i);
  return match?.[1] ?? null;
}

function getErrorDetails(error: unknown): ErrorDetails {
  if (error instanceof Error) {
    return { message: error.message };
  }

  if (isRecord(error)) {
    return {
      code: typeof error.code === "string" ? error.code : undefined,
      message: typeof error.message === "string"
        ? error.message
        : "Unknown error",
      status: typeof error.status === "number" ? error.status : undefined,
    };
  }

  return { message: "Unknown error" };
}

function logServerError(
  operation: string,
  error: unknown,
  context: { candidateId?: string; jobId?: string } = {},
): void {
  const details = getErrorDetails(error);
  const gmailError = isGmailProviderError(error) ? error : null;
  const workspaceError = isGoogleWorkspaceProviderError(error) ? error : null;

  console.error("process-offer-letter error", {
    operation,
    candidate_id: context.candidateId,
    job_id: context.jobId,
    error_code: details.code,
    error_status: details.status,
    error_type: error instanceof Error ? error.name : "UnknownError",
    provider_stage: gmailError?.stage ?? workspaceError?.stage,
    delivery_outcome: gmailError?.deliveryOutcome,
    retryable: gmailError?.retryable ?? workspaceError?.retryable,
  });
}

function getSupabaseConfiguration(): {
  supabaseUrl: string;
  anonKey: string;
  serviceRoleKey: string;
} {
  const supabaseUrl = nonBlank(Deno.env.get("SUPABASE_URL"));
  const anonKey = nonBlank(Deno.env.get("SUPABASE_ANON_KEY"));
  const serviceRoleKey = nonBlank(
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  );

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    throw new HttpError(500, "Offer-letter worker is not configured.");
  }

  return { supabaseUrl, anonKey, serviceRoleKey };
}

function createCallerClient(
  supabaseUrl: string,
  anonKey: string,
  accessToken: string,
): SupabaseClient {
  return createClient(supabaseUrl, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
  });
}

function createAdminClient(
  supabaseUrl: string,
  serviceRoleKey: string,
): SupabaseClient {
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

function parseOfferLetterClaim(
  value: unknown,
  requestedCandidateId: string,
): OfferLetterClaim | null {
  if (!isRecord(value)) {
    return null;
  }

  const duration = value.internshipDurationMonths;
  const claim: OfferLetterClaim = {
    jobId: typeof value.jobId === "string" ? value.jobId : "",
    candidateId: typeof value.candidateId === "string"
      ? value.candidateId
      : "",
    offerLetterId: typeof value.offerLetterId === "string"
      ? value.offerLetterId
      : "",
    jobStatus: typeof value.jobStatus === "string" ? value.jobStatus : "",
    attemptCount: typeof value.attemptCount === "number"
      ? value.attemptCount
      : -1,
    shouldProcessExternal: value.shouldProcessExternal === true,
    needsFinalization: value.needsFinalization === true,
    alreadyCompleted: value.alreadyCompleted === true,
    fullName: typeof value.fullName === "string" ? value.fullName : "",
    email: typeof value.email === "string" ? value.email : "",
    phone: isNullableText(value.phone) ? value.phone : null,
    address: isNullableText(value.address) ? value.address : null,
    appliedRole: typeof value.appliedRole === "string"
      ? value.appliedRole
      : "",
    roleCode: typeof value.roleCode === "string" ? value.roleCode : "",
    mid: typeof value.mid === "string" ? value.mid : "",
    offerLetterNumber: typeof value.offerLetterNumber === "string"
      ? value.offerLetterNumber
      : "",
    joiningDate: typeof value.joiningDate === "string"
      ? value.joiningDate
      : "",
    expectedEndDate: typeof value.expectedEndDate === "string"
      ? value.expectedEndDate
      : "",
    internshipDurationMonths: typeof duration === "number" ? duration : -1,
    offerDate: typeof value.offerDate === "string" ? value.offerDate : "",
    googleDocFileId: isNullableFileId(value.googleDocFileId)
      ? value.googleDocFileId
      : null,
    googlePdfFileId: isNullableFileId(value.googlePdfFileId)
      ? value.googlePdfFileId
      : null,
    documentsPreparedAt: isNullableTimestamp(value.documentsPreparedAt)
      ? value.documentsPreparedAt
      : null,
    emailAttemptedAt: isNullableTimestamp(value.emailAttemptedAt)
      ? value.emailAttemptedAt
      : null,
    gmailMessageId: isNullableText(value.gmailMessageId)
      ? value.gmailMessageId
      : null,
  };

  const validShape =
    typeof value.shouldProcessExternal === "boolean" &&
    typeof value.needsFinalization === "boolean" &&
    typeof value.alreadyCompleted === "boolean" &&
    isNullableText(value.phone) &&
    isNullableText(value.address) &&
    isNullableFileId(value.googleDocFileId) &&
    isNullableFileId(value.googlePdfFileId) &&
    isNullableTimestamp(value.documentsPreparedAt) &&
    isNullableTimestamp(value.emailAttemptedAt) &&
    isNullableText(value.gmailMessageId);
  const validCore =
    validShape &&
    UUID_PATTERN.test(claim.jobId) &&
    UUID_PATTERN.test(claim.candidateId) &&
    claim.candidateId.toLowerCase() === requestedCandidateId.toLowerCase() &&
    UUID_PATTERN.test(claim.offerLetterId) &&
    JOB_STATUSES.has(claim.jobStatus) &&
    Number.isInteger(claim.attemptCount) &&
    claim.attemptCount >= 0 &&
    claim.fullName.trim() !== "" &&
    claim.email.trim() !== "" &&
    claim.appliedRole.trim() !== "" &&
    /^[A-Z0-9]{3}$/.test(claim.roleCode) &&
    MID_PATTERN.test(claim.mid) &&
    claim.offerLetterNumber === `OL-${claim.mid}` &&
    DATE_PATTERN.test(claim.joiningDate) &&
    DATE_PATTERN.test(claim.expectedEndDate) &&
    DATE_PATTERN.test(claim.offerDate) &&
    Number.isInteger(claim.internshipDurationMonths) &&
    claim.internshipDurationMonths > 0 &&
    !(claim.googlePdfFileId && !claim.googleDocFileId) &&
    !(
      claim.documentsPreparedAt &&
      (!claim.googleDocFileId || !claim.googlePdfFileId)
    );

  if (!validCore) {
    return null;
  }

  const isCompleted =
    claim.alreadyCompleted &&
    !claim.shouldProcessExternal &&
    !claim.needsFinalization &&
    claim.jobStatus === "SUCCESS" &&
    Boolean(claim.documentsPreparedAt) &&
    Boolean(claim.emailAttemptedAt) &&
    Boolean(claim.gmailMessageId);
  const isFinalizationRecovery =
    !claim.alreadyCompleted &&
    !claim.shouldProcessExternal &&
    claim.needsFinalization &&
    claim.jobStatus === "PROCESSING" &&
    Boolean(claim.documentsPreparedAt) &&
    Boolean(claim.emailAttemptedAt) &&
    Boolean(claim.gmailMessageId);
  const isExternalProcessing =
    !claim.alreadyCompleted &&
    claim.shouldProcessExternal &&
    !claim.needsFinalization &&
    claim.jobStatus === "PROCESSING" &&
    !claim.gmailMessageId;

  return isCompleted || isFinalizationRecovery || isExternalProcessing
    ? claim
    : null;
}

function classifyClaimError(error: unknown): HttpError {
  const details = getErrorDetails(error);

  if (
    details.message.includes(
      "Previous offer-email attempt has an unknown delivery outcome.",
    )
  ) {
    return new HttpError(409, UNKNOWN_DELIVERY_MESSAGE);
  }

  if (details.message.includes("Offer-letter job is already being processed.")) {
    return new HttpError(409, "Offer-letter job is already being processed.");
  }

  if (details.message.includes("Offer-letter automation job is cancelled.")) {
    return new HttpError(422, "Offer-letter automation job is cancelled.");
  }

  if (details.message.includes("not eligible for offer preparation")) {
    return new HttpError(
      422,
      "Candidate lifecycle is not eligible for offer preparation.",
    );
  }

  if (details.status === 401 || details.code === "PGRST301") {
    return new HttpError(401, "Authentication could not be validated.");
  }

  if (details.code === "42501" || details.status === 403) {
    return new HttpError(403, "HR authorization was not granted.");
  }

  return new HttpError(500, "Unable to prepare the offer-letter job.");
}

function isDocumentRecordResult(
  value: unknown,
  claim: OfferLetterClaim,
  expectedDocFileId: string,
  expectedPdfFileId: string | null,
  expectedReady: boolean,
): value is DocumentRecordResult {
  return (
    isRecord(value) &&
    value.jobId === claim.jobId &&
    value.candidateId === claim.candidateId &&
    value.offerLetterId === claim.offerLetterId &&
    value.googleDocFileId === expectedDocFileId &&
    value.googlePdfFileId === expectedPdfFileId &&
    value.documentsReady === expectedReady &&
    isNullableTimestamp(value.documentsPreparedAt) &&
    typeof value.lifecycleStatus === "string" &&
    ["MID_GENERATED", "OFFER_LETTER_GENERATED", "ACTIVE"].includes(
      value.lifecycleStatus,
    ) &&
    (!expectedReady ||
      (
        value.lifecycleStatus === "OFFER_LETTER_GENERATED" &&
        typeof value.documentsPreparedAt === "string"
      ))
  );
}

function isProviderAcceptanceResult(
  value: unknown,
  claim: OfferLetterClaim,
): boolean {
  return (
    isRecord(value) &&
    value.jobId === claim.jobId &&
    value.candidateId === claim.candidateId &&
    value.providerAccepted === true &&
    value.jobStatus === "RETRY" &&
    typeof value.providerAcceptedAt === "string" &&
    !Number.isNaN(Date.parse(value.providerAcceptedAt))
  );
}

function isEmailSendStartResult(
  value: unknown,
  claim: OfferLetterClaim,
): boolean {
  return (
    isRecord(value) &&
    value.jobId === claim.jobId &&
    value.candidateId === claim.candidateId &&
    value.offerLetterId === claim.offerLetterId &&
    value.jobStatus === "PROCESSING" &&
    value.readyToSend === true &&
    typeof value.emailAttemptedAt === "string" &&
    !Number.isNaN(Date.parse(value.emailAttemptedAt))
  );
}

function isFinalizationResult(
  value: unknown,
  claim: OfferLetterClaim,
): value is FinalizationResult {
  return (
    isRecord(value) &&
    value.jobId === claim.jobId &&
    value.candidateId === claim.candidateId &&
    value.offerLetterId === claim.offerLetterId &&
    value.jobStatus === "SUCCESS" &&
    value.lifecycleStatus === "ACTIVE" &&
    value.offerStatus === "OFFER_LETTER_SENT" &&
    typeof value.providerAcceptedAt === "string" &&
    !Number.isNaN(Date.parse(value.providerAcceptedAt)) &&
    typeof value.completedAt === "string" &&
    !Number.isNaN(Date.parse(value.completedAt))
  );
}

async function recordJobFailureSafely(
  adminClient: SupabaseClient,
  claim: OfferLetterClaim,
  safeMessage: string,
  retryable: boolean,
): Promise<void> {
  try {
    const result = await adminClient.rpc("record_offer_letter_failure", {
      p_job_id: claim.jobId,
      p_claim_attempt_count: claim.attemptCount,
      p_error_message: safeMessage,
      p_retryable: retryable,
    });

    if (result.error) {
      logServerError("record_offer_letter_failure", result.error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
    }
  } catch (error) {
    logServerError("record_offer_letter_failure", error, {
      candidateId: claim.candidateId,
      jobId: claim.jobId,
    });
  }
}

async function recordDocuments(
  adminClient: SupabaseClient,
  claim: OfferLetterClaim,
  googleDocFileId: string,
  googlePdfFileId: string | null,
  documentsReady: boolean,
): Promise<DocumentRecordResult> {
  const result = await adminClient.rpc("record_offer_letter_documents", {
    p_job_id: claim.jobId,
    p_claim_attempt_count: claim.attemptCount,
    p_google_doc_file_id: googleDocFileId,
    p_google_pdf_file_id: googlePdfFileId,
    p_documents_ready: documentsReady,
  });

  if (
    result.error ||
    !isDocumentRecordResult(
      result.data,
      claim,
      googleDocFileId,
      googlePdfFileId,
      documentsReady,
    )
  ) {
    logServerError(
      "record_offer_letter_documents",
      result.error ?? new Error("Document persistence returned an invalid result."),
      { candidateId: claim.candidateId, jobId: claim.jobId },
    );
    throw new HttpError(
      500,
      "Offer documents were prepared, but their state could not be stored.",
    );
  }

  return result.data;
}

async function persistProviderAcceptance(
  adminClient: SupabaseClient,
  claim: OfferLetterClaim,
  messageId: string,
): Promise<void> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const result = await adminClient.rpc(
        "record_offer_letter_provider_acceptance",
        {
          p_job_id: claim.jobId,
          p_claim_attempt_count: claim.attemptCount,
          p_provider_message_id: messageId,
        },
      );

      if (
        !result.error &&
        isProviderAcceptanceResult(result.data, claim)
      ) {
        return;
      }

      lastError = result.error ??
        new Error("Provider acceptance returned an invalid result.");
    } catch (error) {
      lastError = error;
    }

    if (attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, attempt * 150));
    }
  }

  logServerError("record_offer_letter_provider_acceptance", lastError, {
    candidateId: claim.candidateId,
    jobId: claim.jobId,
  });
  throw new HttpError(
    500,
    "Offer email was accepted by Gmail, but acceptance could not be stored. Check the sender Sent folder before retrying.",
  );
}

async function beginEmailSend(
  adminClient: SupabaseClient,
  claim: OfferLetterClaim,
): Promise<void> {
  const result = await adminClient.rpc("begin_offer_letter_email_send", {
    p_job_id: claim.jobId,
    p_claim_attempt_count: claim.attemptCount,
  });

  if (result.error || !isEmailSendStartResult(result.data, claim)) {
    logServerError(
      "begin_offer_letter_email_send",
      result.error ?? new Error("Email send start returned an invalid result."),
      { candidateId: claim.candidateId, jobId: claim.jobId },
    );
    throw new HttpError(
      500,
      "Offer email could not be prepared for delivery.",
    );
  }
}

async function finalizeOfferLetter(
  adminClient: SupabaseClient,
  claim: OfferLetterClaim,
): Promise<FinalizationResult> {
  try {
    const result = await adminClient.rpc("finalize_offer_letter_success", {
      p_job_id: claim.jobId,
      p_claim_attempt_count: claim.attemptCount,
    });

    if (
      result.error ||
      !isFinalizationResult(result.data, claim)
    ) {
      logServerError(
        "finalize_offer_letter_success",
        result.error ?? new Error("Finalization returned an invalid result."),
        { candidateId: claim.candidateId, jobId: claim.jobId },
      );
      throw new HttpError(500, FINALIZATION_PENDING_MESSAGE);
    }

    return result.data;
  } catch (error) {
    if (!(error instanceof HttpError)) {
      logServerError("finalize_offer_letter_success", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
    }

    throw new HttpError(500, FINALIZATION_PENDING_MESSAGE);
  }
}

function successResponse(
  request: Request,
  claim: OfferLetterClaim,
  alreadyCompleted: boolean,
): Response {
  return createJsonResponse(request, {
    success: true,
    candidateId: claim.candidateId,
    offerLetterId: claim.offerLetterId,
    offerLetterNumber: claim.offerLetterNumber,
    jobId: claim.jobId,
    jobStatus: "SUCCESS",
    lifecycleStatus: "ACTIVE",
    alreadyCompleted,
    message: "Offer letter generated, sent, and candidate activated.",
  });
}

async function handleRequest(request: Request): Promise<Response> {
  const jsonResponse = (
    body: Record<string, unknown>,
    status = 200,
  ) => createJsonResponse(request, body, status);

  if (request.method === "OPTIONS") {
    return jsonResponse({ success: true });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Only POST requests are supported." }, 405);
  }

  let requestBody: unknown;

  try {
    requestBody = await request.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  if (!isRecord(requestBody)) {
    return jsonResponse({ error: "Request body must be an object." }, 400);
  }

  const requestKeys = Object.keys(requestBody);

  if (
    requestKeys.length !== 1 ||
    !requestKeys.includes("candidateId") ||
    typeof requestBody.candidateId !== "string"
  ) {
    return jsonResponse(
      { error: "Request body must contain only candidateId." },
      400,
    );
  }

  const candidateId = requestBody.candidateId.trim().toLowerCase();

  if (!UUID_PATTERN.test(candidateId)) {
    return jsonResponse({ error: "candidateId must be a valid UUID." }, 400);
  }

  const accessToken = extractBearerToken(request);

  if (!accessToken) {
    return jsonResponse({ error: "A valid Bearer token is required." }, 401);
  }

  let claim: OfferLetterClaim | null = null;

  try {
    const { supabaseUrl, anonKey, serviceRoleKey } =
      getSupabaseConfiguration();
    const callerClient = createCallerClient(
      supabaseUrl,
      anonKey,
      accessToken,
    );
    const adminClient = createAdminClient(supabaseUrl, serviceRoleKey);
    const claimResult = await callerClient.rpc("claim_offer_letter_job", {
      p_candidate_id: candidateId,
    });

    if (claimResult.error) {
      throw classifyClaimError(claimResult.error);
    }

    claim = parseOfferLetterClaim(claimResult.data, candidateId);

    if (!claim) {
      throw new HttpError(
        500,
        "Offer-letter job returned an invalid response.",
      );
    }

    if (claim.alreadyCompleted) {
      return successResponse(request, claim, true);
    }

    if (claim.needsFinalization) {
      await finalizeOfferLetter(adminClient, claim);
      return successResponse(request, claim, true);
    }

    let template: OfferLetterTemplate;

    try {
      template = buildOfferLetterTemplate(claim);
    } catch (error) {
      logServerError("build_offer_letter_template", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
      await recordJobFailureSafely(
        adminClient,
        claim,
        "Offer-letter template data was invalid.",
        false,
      );
      throw new HttpError(
        500,
        "Offer-letter generation could not be prepared.",
      );
    }

    let googleDocFileId = claim.googleDocFileId;
    let googlePdfFileId = claim.googlePdfFileId;
    let pdfBytes: Uint8Array | null = null;

    try {
      const workspaceProvider = await createGoogleWorkspaceProvider();

      if (claim.documentsPreparedAt) {
        if (!googleDocFileId || !googlePdfFileId) {
          throw new Error("Prepared offer documents are missing file IDs.");
        }

        const pdf = await workspaceProvider.ensureOfferPdf({
          fileId: googlePdfFileId,
          googleDocFileId,
          jobId: claim.jobId,
          fileName: template.pdfFileName,
        });
        pdfBytes = pdf.bytes;
      } else {
        const storedGoogleDocFileId = googleDocFileId;
        googleDocFileId = await workspaceProvider.ensureOfferDocument({
          fileId: googleDocFileId,
          jobId: claim.jobId,
          fileName: template.googleDocFileName,
          placeholders: template.placeholders,
        });

        if (!storedGoogleDocFileId) {
          await recordDocuments(
            adminClient,
            claim,
            googleDocFileId,
            googlePdfFileId,
            false,
          );
        }

        if (!googlePdfFileId) {
          googlePdfFileId = await workspaceProvider.reserveBinaryFileId();
          await recordDocuments(
            adminClient,
            claim,
            googleDocFileId,
            googlePdfFileId,
            false,
          );
        }

        const pdf = await workspaceProvider.ensureOfferPdf({
          fileId: googlePdfFileId,
          googleDocFileId,
          jobId: claim.jobId,
          fileName: template.pdfFileName,
        });
        pdfBytes = pdf.bytes;
        await recordDocuments(
          adminClient,
          claim,
          googleDocFileId,
          googlePdfFileId,
          true,
        );
      }
    } catch (error) {
      if (error instanceof HttpError) {
        throw error;
      }

      logServerError("prepare_offer_documents", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
      const retryable = isGoogleWorkspaceProviderError(error)
        ? error.retryable
        : true;
      const safeMessage = isGoogleWorkspaceProviderError(error)
        ? error.safeFailureMessage
        : "Offer-document generation failed before email delivery.";
      await recordJobFailureSafely(
        adminClient,
        claim,
        safeMessage,
        retryable,
      );
      throw new HttpError(
        isGoogleWorkspaceProviderError(error) ? error.httpStatus : 502,
        isGoogleWorkspaceProviderError(error)
          ? error.publicMessage
          : "Offer-document generation failed.",
      );
    }

    if (!pdfBytes) {
      await recordJobFailureSafely(
        adminClient,
        claim,
        "Generated offer PDF was unavailable before email delivery.",
        true,
      );
      throw new HttpError(500, "Offer PDF could not be prepared.");
    }

    try {
      await beginEmailSend(adminClient, claim);
    } catch (error) {
      if (error instanceof HttpError) {
        await recordJobFailureSafely(
          adminClient,
          claim,
          "Offer-email send state could not be prepared.",
          true,
        );
        throw error;
      }

      throw error;
    }

    let messageId: string;

    try {
      const gmailResult = await sendEmailWithGmailAttachment(
        claim.email,
        template.email,
        {
          filename: template.pdfFileName,
          contentType: "application/pdf",
          content: pdfBytes,
        },
      );
      messageId = gmailResult.messageId;
    } catch (error) {
      if (
        error instanceof GmailProviderError &&
        error.deliveryOutcome === "UNKNOWN"
      ) {
        logServerError("gmail_offer_send_unknown_outcome", error, {
          candidateId: claim.candidateId,
          jobId: claim.jobId,
        });
        throw new HttpError(502, UNKNOWN_DELIVERY_MESSAGE);
      }

      if (isGmailProviderError(error)) {
        logServerError("gmail_offer_send_definite_failure", error, {
          candidateId: claim.candidateId,
          jobId: claim.jobId,
        });
        await recordJobFailureSafely(
          adminClient,
          claim,
          error.safeFailureMessage,
          error.retryable,
        );
        throw new HttpError(error.httpStatus, error.publicMessage);
      }

      logServerError("gmail_offer_send_unclassified_failure", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
      throw new HttpError(502, UNKNOWN_DELIVERY_MESSAGE);
    }

    await persistProviderAcceptance(adminClient, claim, messageId);
    await finalizeOfferLetter(adminClient, claim);

    return successResponse(request, claim, false);
  } catch (error) {
    if (!(error instanceof HttpError)) {
      logServerError("process_offer_letter", error, {
        candidateId,
        jobId: claim?.jobId,
      });
    }

    const publicError = error instanceof HttpError
      ? error
      : new HttpError(500, "Offer-letter automation failed.");

    return jsonResponse({ error: publicError.publicMessage }, publicError.status);
  }
}

Deno.serve(handleRequest);
