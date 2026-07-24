import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  GmailProviderError,
  isGmailProviderError,
  sendWelcomeEmailWithGmail,
} from "../_shared/gmailProvider.ts";
import {
  buildWelcomeEmailTemplate,
  type WelcomeEmailTemplate,
  type WelcomeEmailTemplateInput,
} from "../_shared/welcomeEmailTemplate.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ALLOWED_JOB_STATUSES = new Set([
  "PENDING",
  "PROCESSING",
  "SUCCESS",
  "FAILED",
  "RETRY",
  "CANCELLED",
]);
const UNKNOWN_DELIVERY_MESSAGE =
  "Welcome-email delivery outcome is unknown. Check the sender Sent folder before retrying.";
const FINALIZATION_PENDING_MESSAGE =
  "Welcome email was sent, but workflow finalization is pending. Retry the action.";

type ErrorDetails = {
  code?: string;
  message: string;
  status?: number;
};

type WelcomeMailClaim = WelcomeEmailTemplateInput & {
  jobId: string;
  candidateId: string;
  idempotencyKey: string;
  jobStatus: string;
  attemptCount: number;
  shouldSend: boolean;
  needsFinalization: boolean;
  email: string;
};

type WelcomeMailClaimEnvelope = {
  jobId: string;
  candidateId: string;
  jobStatus: string;
  shouldSend: boolean;
  needsFinalization: boolean;
};

type FinalizationResult = {
  jobId: string;
  candidateId: string;
  jobStatus: "SUCCESS";
  lifecycleStatus: "WELCOME_MAIL_SENT";
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

function getCorsHeaders(): Record<string, string> {
  const configuredOrigin = nonBlank(Deno.env.get("ALLOWED_ORIGIN"));
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json; charset=utf-8",
  };

  if (configuredOrigin) {
    headers["Access-Control-Allow-Origin"] = configuredOrigin;
    headers.Vary = "Origin";
  } else {
    // Production must configure ALLOWED_ORIGIN to the exact frontend origin.
    headers["Access-Control-Allow-Origin"] = "*";
  }

  return headers;
}

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: getCorsHeaders(),
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
      message:
        typeof error.message === "string" ? error.message : "Unknown error",
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
  const providerError = isGmailProviderError(error) ? error : null;

  console.error("send-welcome-mail error", {
    operation,
    candidate_id: context.candidateId,
    job_id: context.jobId,
    error_code: details.code,
    error_status: details.status,
    error_type: error instanceof Error ? error.name : "UnknownError",
    provider_stage: providerError?.stage,
    delivery_outcome: providerError?.deliveryOutcome,
    retryable: providerError?.retryable,
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
    throw new HttpError(500, "Welcome-email service is not configured.");
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

function isNullableString(value: unknown): value is string | null {
  return value === null || (typeof value === "string" && value.trim() !== "");
}

function parseWelcomeMailClaimEnvelope(
  value: unknown,
  requestedCandidateId: string,
): WelcomeMailClaimEnvelope | null {
  if (!isRecord(value)) {
    return null;
  }

  if (
    typeof value.jobId !== "string" ||
    !UUID_PATTERN.test(value.jobId) ||
    typeof value.candidateId !== "string" ||
    !UUID_PATTERN.test(value.candidateId) ||
    value.candidateId.toLowerCase() !== requestedCandidateId.toLowerCase() ||
    typeof value.jobStatus !== "string" ||
    !ALLOWED_JOB_STATUSES.has(value.jobStatus) ||
    typeof value.shouldSend !== "boolean" ||
    typeof value.needsFinalization !== "boolean"
  ) {
    return null;
  }

  return {
    jobId: value.jobId,
    candidateId: value.candidateId,
    jobStatus: value.jobStatus,
    shouldSend: value.shouldSend,
    needsFinalization: value.needsFinalization,
  };
}

function isKnownPreSendClaim(
  envelope: WelcomeMailClaimEnvelope,
): boolean {
  return (
    envelope.jobStatus === "PROCESSING" &&
    envelope.shouldSend &&
    !envelope.needsFinalization
  );
}

function isWelcomeMailClaim(
  value: unknown,
  requestedCandidateId: string,
): value is WelcomeMailClaim {
  if (!isRecord(value)) {
    return false;
  }

  const candidateId =
    typeof value.candidateId === "string" ? value.candidateId : "";
  const expectedIdempotencyKey = `WELCOME_MAIL:${requestedCandidateId}`;
  const duration = value.internshipDurationMonths;

  return (
    typeof value.jobId === "string" &&
    UUID_PATTERN.test(value.jobId) &&
    UUID_PATTERN.test(candidateId) &&
    candidateId.toLowerCase() === requestedCandidateId.toLowerCase() &&
    value.idempotencyKey === expectedIdempotencyKey &&
    typeof value.jobStatus === "string" &&
    ALLOWED_JOB_STATUSES.has(value.jobStatus) &&
    typeof value.attemptCount === "number" &&
    Number.isInteger(value.attemptCount) &&
    value.attemptCount >= 0 &&
    typeof value.shouldSend === "boolean" &&
    typeof value.needsFinalization === "boolean" &&
    typeof value.fullName === "string" &&
    value.fullName.trim() !== "" &&
    typeof value.email === "string" &&
    value.email.trim() !== "" &&
    typeof value.appliedRole === "string" &&
    value.appliedRole.trim() !== "" &&
    isNullableString(value.joiningDate) &&
    isNullableString(value.probationEndDate) &&
    (
      duration === null ||
      (typeof duration === "number" &&
        Number.isInteger(duration) &&
        duration > 0)
    ) &&
    isNullableString(value.expectedEndDate)
  );
}

function validateClaimCombination(claim: WelcomeMailClaim): void {
  const isCompleted =
    !claim.shouldSend &&
    !claim.needsFinalization &&
    claim.jobStatus === "SUCCESS";
  const isFinalizationRecovery =
    !claim.shouldSend &&
    claim.needsFinalization &&
    claim.jobStatus === "PROCESSING";
  const isNewSend =
    claim.shouldSend &&
    !claim.needsFinalization &&
    claim.jobStatus === "PROCESSING";

  if (!isCompleted && !isFinalizationRecovery && !isNewSend) {
    throw new HttpError(
      500,
      "Welcome-email job returned an invalid state.",
    );
  }
}

function classifyClaimError(error: unknown): HttpError {
  const details = getErrorDetails(error);

  if (
    details.message.includes(
      "Previous welcome-email attempt has an unknown delivery outcome. Check the sender Sent folder before retrying.",
    )
  ) {
    return new HttpError(
      409,
      "Previous welcome-email attempt has an unknown delivery outcome. Check the sender Sent folder before retrying.",
    );
  }

  if (
    details.message.includes(
      "Welcome-email job is already being processed.",
    )
  ) {
    return new HttpError(
      409,
      "Welcome-email job is already being processed.",
    );
  }

  if (
    details.message.includes(
      "Candidate lifecycle status must be HR_APPROVED_FOR_PROBATION.",
    )
  ) {
    return new HttpError(
      422,
      "Candidate lifecycle status must be HR_APPROVED_FOR_PROBATION.",
    );
  }

  if (details.message.includes("Welcome-email job is cancelled.")) {
    return new HttpError(422, "Welcome-email job is cancelled.");
  }

  if (
    details.status === 401 ||
    details.code === "PGRST301"
  ) {
    return new HttpError(401, "Authentication could not be validated.");
  }

  if (details.code === "42501" || details.status === 403) {
    return new HttpError(403, "Staff authorization was not granted.");
  }

  return new HttpError(500, "Unable to prepare the welcome-email job.");
}

function isProviderAcceptanceResult(
  value: unknown,
  jobId: string,
): boolean {
  return (
    isRecord(value) &&
    value.jobId === jobId &&
    value.providerAccepted === true &&
    typeof value.jobStatus === "string"
  );
}

function isFinalizationResult(
  value: unknown,
  jobId: string,
  candidateId: string,
): value is FinalizationResult {
  return (
    isRecord(value) &&
    value.jobId === jobId &&
    value.candidateId === candidateId &&
    value.jobStatus === "SUCCESS" &&
    value.lifecycleStatus === "WELCOME_MAIL_SENT" &&
    typeof value.providerAcceptedAt === "string" &&
    value.providerAcceptedAt.trim() !== "" &&
    typeof value.completedAt === "string" &&
    value.completedAt.trim() !== ""
  );
}

async function recordJobFailureSafely(
  adminClient: SupabaseClient,
  jobId: string,
  candidateId: string,
  safeMessage: string,
  retryable: boolean,
): Promise<void> {
  try {
    const result = await adminClient.rpc("record_welcome_mail_failure", {
      p_job_id: jobId,
      p_error_message: safeMessage,
      p_retryable: retryable,
    });

    if (result.error) {
      logServerError("record_welcome_mail_failure", result.error, {
        candidateId,
        jobId,
      });
    }
  } catch (error) {
    logServerError("record_welcome_mail_failure", error, {
      candidateId,
      jobId,
    });
  }
}

async function persistProviderAcceptance(
  adminClient: SupabaseClient,
  claim: WelcomeMailClaim,
  messageId: string,
): Promise<void> {
  let lastError: unknown;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const result = await adminClient.rpc(
        "record_welcome_mail_provider_acceptance",
        {
          p_job_id: claim.jobId,
          p_provider_message_id: messageId,
        },
      );

      if (
        !result.error &&
        isProviderAcceptanceResult(result.data, claim.jobId)
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

  logServerError("record_welcome_mail_provider_acceptance", lastError, {
    candidateId: claim.candidateId,
    jobId: claim.jobId,
  });

  throw new HttpError(
    500,
    "Welcome email was accepted by the provider, but delivery confirmation could not be stored. Check the sender Sent folder before retrying.",
  );
}

async function finalizeWelcomeMail(
  adminClient: SupabaseClient,
  claim: WelcomeMailClaim,
): Promise<FinalizationResult> {
  try {
    const result = await adminClient.rpc("finalize_welcome_mail_success", {
      p_job_id: claim.jobId,
    });

    if (
      result.error ||
      !isFinalizationResult(
        result.data,
        claim.jobId,
        claim.candidateId,
      )
    ) {
      logServerError(
        "finalize_welcome_mail_success",
        result.error ?? new Error("Finalization returned an invalid result."),
        {
          candidateId: claim.candidateId,
          jobId: claim.jobId,
        },
      );
      throw new HttpError(500, FINALIZATION_PENDING_MESSAGE);
    }

    return result.data;
  } catch (error) {
    if (!(error instanceof HttpError)) {
      logServerError("finalize_welcome_mail_success", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
    }

    throw new HttpError(500, FINALIZATION_PENDING_MESSAGE);
  }
}

function successResponse(
  candidateId: string,
  alreadyCompleted: boolean,
): Response {
  return jsonResponse({
    success: true,
    candidateId,
    jobStatus: "SUCCESS",
    lifecycleStatus: "WELCOME_MAIL_SENT",
    alreadyCompleted,
    message: "Welcome email sent successfully.",
  });
}

async function handleRequest(request: Request): Promise<Response> {
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

  const candidateId = requestBody.candidateId.trim();

  if (!UUID_PATTERN.test(candidateId)) {
    return jsonResponse({ error: "candidateId must be a valid UUID." }, 400);
  }

  const accessToken = extractBearerToken(request);

  if (!accessToken) {
    return jsonResponse({ error: "A valid Bearer token is required." }, 401);
  }

  let claim: WelcomeMailClaim | null = null;

  try {
    const { supabaseUrl, anonKey, serviceRoleKey } =
      getSupabaseConfiguration();
    const callerClient = createCallerClient(
      supabaseUrl,
      anonKey,
      accessToken,
    );
    const adminClient = createAdminClient(supabaseUrl, serviceRoleKey);
    const claimResult = await callerClient.rpc("claim_welcome_mail_job", {
      p_candidate_id: candidateId,
    });

    if (claimResult.error) {
      throw classifyClaimError(claimResult.error);
    }

    const claimEnvelope = parseWelcomeMailClaimEnvelope(
      claimResult.data,
      candidateId,
    );

    if (!claimEnvelope) {
      throw new HttpError(
        500,
        "Welcome-email job returned an invalid response.",
      );
    }

    if (!isWelcomeMailClaim(claimResult.data, candidateId)) {
      if (isKnownPreSendClaim(claimEnvelope)) {
        await recordJobFailureSafely(
          adminClient,
          claimEnvelope.jobId,
          claimEnvelope.candidateId,
          "Welcome-email claim data was invalid.",
          false,
        );
        throw new HttpError(
          500,
          "Welcome-email delivery could not be prepared.",
        );
      }

      throw new HttpError(
        500,
        "Welcome-email job returned an invalid response.",
      );
    }

    claim = claimResult.data;

    try {
      validateClaimCombination(claim);
    } catch (error) {
      if (isKnownPreSendClaim(claimEnvelope)) {
        await recordJobFailureSafely(
          adminClient,
          claimEnvelope.jobId,
          claimEnvelope.candidateId,
          "Welcome-email claim data was invalid.",
          false,
        );
        throw new HttpError(
          500,
          "Welcome-email delivery could not be prepared.",
        );
      }

      throw error;
    }

    if (!claim.shouldSend && !claim.needsFinalization) {
      return successResponse(claim.candidateId, true);
    }

    if (!claim.shouldSend && claim.needsFinalization) {
      await finalizeWelcomeMail(adminClient, claim);
      return successResponse(claim.candidateId, true);
    }

    let template: WelcomeEmailTemplate;

    try {
      template = buildWelcomeEmailTemplate({
        fullName: claim.fullName,
        appliedRole: claim.appliedRole,
        joiningDate: claim.joiningDate,
        probationEndDate: claim.probationEndDate,
        internshipDurationMonths: claim.internshipDurationMonths,
        expectedEndDate: claim.expectedEndDate,
      });
    } catch (error) {
      logServerError("build_welcome_email_template", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
      await recordJobFailureSafely(
        adminClient,
        claim.jobId,
        claim.candidateId,
        "Welcome-email template could not be prepared.",
        false,
      );
      throw new HttpError(
        500,
        "Welcome-email delivery could not be prepared.",
      );
    }

    let messageId: string;

    try {
      const gmailResult = await sendWelcomeEmailWithGmail(
        claim.email,
        template,
      );
      messageId = gmailResult.messageId;
    } catch (error) {
      if (
        error instanceof GmailProviderError &&
        error.deliveryOutcome === "UNKNOWN"
      ) {
        logServerError("gmail_send_unknown_outcome", error, {
          candidateId: claim.candidateId,
          jobId: claim.jobId,
        });
        throw new HttpError(502, UNKNOWN_DELIVERY_MESSAGE);
      }

      if (isGmailProviderError(error)) {
        logServerError("gmail_send_definite_failure", error, {
          candidateId: claim.candidateId,
          jobId: claim.jobId,
        });
        await recordJobFailureSafely(
          adminClient,
          claim.jobId,
          claim.candidateId,
          error.safeFailureMessage,
          error.retryable,
        );
        throw new HttpError(error.httpStatus, error.publicMessage);
      }

      logServerError("gmail_send_unclassified_failure", error, {
        candidateId: claim.candidateId,
        jobId: claim.jobId,
      });
      throw new HttpError(502, UNKNOWN_DELIVERY_MESSAGE);
    }

    await persistProviderAcceptance(adminClient, claim, messageId);
    await finalizeWelcomeMail(adminClient, claim);

    return successResponse(claim.candidateId, false);
  } catch (error) {
    if (!(error instanceof HttpError)) {
      logServerError("send_welcome_mail", error, {
        candidateId,
        jobId: claim?.jobId,
      });
    }

    const publicError =
      error instanceof HttpError
        ? error
        : new HttpError(500, "Unable to send the welcome email.");

    return jsonResponse(
      { error: publicError.publicMessage },
      publicError.status,
    );
  }
}

Deno.serve(handleRequest);
