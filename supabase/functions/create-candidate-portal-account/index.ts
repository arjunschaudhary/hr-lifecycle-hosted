import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  GmailProviderError,
  isGmailProviderError,
  sendEmailWithGmail,
} from "../_shared/gmailProvider.ts";
import { buildCandidatePortalInvitationEmailTemplate } from "../_shared/candidatePortalInvitationEmailTemplate.ts";

const APPROVED_STAFF_ROLES = [
  "HR_SITE_CONNECT",
  "HR_SITE_CONNECT_LEAD",
  "HR_LEAD",
  "ADMIN",
] as const;

const ALLOWED_OUTCOMES = new Set([
  "ACTIVATED",
  "REACTIVATED",
  "REPAIRED",
  "ALREADY_ACTIVE",
]);

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type CandidateRecord = {
  candidate_id: string;
  full_name: string | null;
  email: string | null;
};

type LifecycleRecord = {
  lifecycle_status: string | null;
};

type CandidateMapping = {
  user_id: string;
  account_status: string;
};

type FinalizationRow = {
  outcome: string;
  candidate_id: string;
  user_id: string;
  email: string;
};

type ErrorDetails = {
  code?: string;
  message: string;
  status?: number;
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

function isFinalizationRow(value: unknown): value is FinalizationRow {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.outcome === "string" &&
    typeof value.candidate_id === "string" &&
    typeof value.user_id === "string" &&
    typeof value.email === "string"
  );
}

function nonBlank(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function buildCandidatePortalSetupUrl(
  redirectUrl: string,
  tokenHash: string,
  verificationType: string,
): string {
  let setupUrl: URL;

  try {
    setupUrl = new URL(redirectUrl);
  } catch {
    throw new HttpError(
      500,
      "Candidate portal invitation redirect is not configured.",
    );
  }

  if (
    !["https:", "http:"].includes(setupUrl.protocol) ||
    setupUrl.username ||
    setupUrl.password
  ) {
    throw new HttpError(
      500,
      "Candidate portal invitation redirect is not configured.",
    );
  }

  const query = new URLSearchParams({
    token_hash: tokenHash,
    type: verificationType,
  });

  setupUrl.search = query.toString();
  setupUrl.hash = "";

  return setupUrl.toString();
}

function extractKeyValue(rawValue: string | undefined): string | undefined {
  const raw = nonBlank(rawValue);

  if (!raw) {
    return undefined;
  }

  try {
    const parsed: unknown = JSON.parse(raw);

    if (typeof parsed === "string") {
      return nonBlank(parsed);
    }

    if (isRecord(parsed)) {
      const defaultValue = parsed.default;

      if (typeof defaultValue === "string" && nonBlank(defaultValue)) {
        return defaultValue.trim();
      }

      for (const value of Object.values(parsed)) {
        if (typeof value === "string" && nonBlank(value)) {
          return value.trim();
        }
      }
    }

    return undefined;
  } catch {
    return raw;
  }
}

function getApiKey(preferredName: string, legacyName: string): string | undefined {
  return (
    extractKeyValue(Deno.env.get(preferredName)) ??
    nonBlank(Deno.env.get(legacyName))
  );
}

function getConfiguration(): {
  supabaseUrl: string;
  publishableKey: string;
  secretKey: string;
} {
  const supabaseUrl = nonBlank(Deno.env.get("SUPABASE_URL"));
  const publishableKey = getApiKey(
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_ANON_KEY",
  );
  const secretKey = getApiKey(
    "SUPABASE_SECRET_KEYS",
    "SUPABASE_SERVICE_ROLE_KEY",
  );

  if (!supabaseUrl || !publishableKey || !secretKey) {
    throw new HttpError(
      500,
      "Candidate portal account service is not configured.",
    );
  }

  return { supabaseUrl, publishableKey, secretKey };
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

function isExistingAuthUserError(error: unknown): boolean {
  const message = getErrorDetails(error).message.toLowerCase();

  return [
    "already registered",
    "already exists",
    "user already",
    "email address has already been registered",
  ].some((indicator) => message.includes(indicator));
}

function logServerError(
  operation: string,
  error: unknown,
  context: { candidateId?: string; actorUserId?: string } = {},
): void {
  const details = getErrorDetails(error);

  console.error("create-candidate-portal-account error", {
    operation,
    candidate_id: context.candidateId,
    actor_user_id: context.actorUserId,
    error_code: details.code,
    error_message: details.message.slice(0, 300),
  });
}

function createCallerClient(
  supabaseUrl: string,
  publishableKey: string,
  accessToken: string,
): SupabaseClient {
  return createClient(supabaseUrl, publishableKey, {
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
  secretKey: string,
): SupabaseClient {
  return createClient(supabaseUrl, secretKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

async function requireAuthorizedStaff(callerClient: SupabaseClient): Promise<void> {
  const activeResult = await callerClient.rpc("current_user_is_active");

  if (activeResult.error) {
    throw activeResult.error;
  }

  if (activeResult.data !== true) {
    throw new HttpError(403, "Active staff authorization is required.");
  }

  const roleResult = await callerClient.rpc("current_user_has_any_role", {
    p_role_slugs: [...APPROVED_STAFF_ROLES],
  });

  if (roleResult.error) {
    throw roleResult.error;
  }

  if (roleResult.data !== true) {
    throw new HttpError(403, "An approved staff role is required.");
  }
}

async function findAuthUserIdByEmail(
  adminClient: SupabaseClient,
  email: string,
): Promise<string | null> {
  const result = await adminClient.rpc("find_auth_user_id_by_email", {
    p_email: email,
  });

  if (result.error) {
    throw result.error;
  }

  return typeof result.data === "string" ? result.data : null;
}

function classifyError(error: unknown): HttpError {
  if (error instanceof HttpError) {
    return error;
  }

  const details = getErrorDetails(error);
  const message = details.message.toLowerCase();

  if (
    message.includes("candidate does not exist") ||
    message.includes("candidate lifecycle record does not exist")
  ) {
    return new HttpError(404, "Candidate or lifecycle record was not found.");
  }

  if (message.includes("supabase auth user does not exist")) {
    return new HttpError(409, "The candidate account mapping is not usable.");
  }

  if (
    details.code === "42501" ||
    message.includes("not an active authorized staff user")
  ) {
    return new HttpError(403, "Staff authorization was not granted.");
  }

  if (
    details.code === "22023" ||
    message.includes("must not be blank") ||
    message.includes("required")
  ) {
    return new HttpError(400, "The candidate account activation data is invalid.");
  }

  if (
    details.code === "P0001" ||
    details.code === "23505" ||
    message.includes("must be active") ||
    message.includes("does not match") ||
    message.includes("different user") ||
    message.includes("different candidate") ||
    message.includes("conflict")
  ) {
    return new HttpError(409, "Candidate portal account activation conflict.");
  }

  return new HttpError(500, "Unable to activate the candidate portal account.");
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
    !requestKeys.includes("candidate_id") ||
    typeof requestBody.candidate_id !== "string"
  ) {
    return jsonResponse(
      { error: "Request body must contain only candidate_id." },
      400,
    );
  }

  const candidateId = requestBody.candidate_id.trim();

  if (!UUID_PATTERN.test(candidateId)) {
    return jsonResponse({ error: "candidate_id must be a valid UUID." }, 400);
  }

  const accessToken = extractBearerToken(request);

  if (!accessToken) {
    return jsonResponse({ error: "A valid Bearer token is required." }, 401);
  }

  let adminClient: SupabaseClient | null = null;
  let newlyInvitedUserId: string | null = null;
  let preserveInvitedUser = false;
  let gmailInvitationDelivered = false;
  let actorUserId: string | undefined;

  try {
    const { supabaseUrl, publishableKey, secretKey } = getConfiguration();
    const callerClient = createCallerClient(
      supabaseUrl,
      publishableKey,
      accessToken,
    );

    const authResult = await callerClient.auth.getUser(accessToken);

    if (authResult.error || !authResult.data.user?.id) {
      return jsonResponse({ error: "Authentication could not be validated." }, 401);
    }

    actorUserId = authResult.data.user.id;
    await requireAuthorizedStaff(callerClient);

    adminClient = createAdminClient(supabaseUrl, secretKey);

    const candidateResult = await adminClient
      .from("master_candidates")
      .select("candidate_id,full_name,email")
      .eq("candidate_id", candidateId)
      .maybeSingle();

    if (candidateResult.error) {
      throw candidateResult.error;
    }

    const candidate = candidateResult.data as CandidateRecord | null;

    if (!candidate) {
      return jsonResponse({ error: "Candidate was not found." }, 404);
    }

    const candidateName =
      typeof candidate.full_name === "string" ? candidate.full_name.trim() : "";
    const candidateEmail =
      typeof candidate.email === "string"
        ? candidate.email.trim().toLowerCase()
        : "";

    if (!candidateName || !candidateEmail) {
      return jsonResponse({ error: "Candidate profile is incomplete." }, 409);
    }

    const lifecycleResult = await adminClient
      .from("hr_lifecycle")
      .select("lifecycle_status")
      .eq("candidate_id", candidateId)
      .maybeSingle();

    if (lifecycleResult.error) {
      throw lifecycleResult.error;
    }

    const lifecycle = lifecycleResult.data as LifecycleRecord | null;

    if (!lifecycle) {
      return jsonResponse({ error: "Candidate lifecycle was not found." }, 404);
    }

    if (lifecycle.lifecycle_status !== "ACTIVE") {
      return jsonResponse(
        { error: "Candidate lifecycle status must be ACTIVE." },
        409,
      );
    }

    const mappingResult = await adminClient
      .from("candidate_user_accounts")
      .select("user_id,account_status")
      .eq("candidate_id", candidateId)
      .maybeSingle();

    if (mappingResult.error) {
      throw mappingResult.error;
    }

    const mapping = mappingResult.data as CandidateMapping | null;
    let selectedUserId: string | null = null;
    let invitationSent = false;

    if (mapping) {
      selectedUserId = mapping.user_id;

      const mappedAuthUser = await adminClient.auth.admin.getUserById(
        selectedUserId,
      );

      if (mappedAuthUser.error || !mappedAuthUser.data.user) {
        return jsonResponse(
          { error: "Candidate account mapping is not usable." },
          409,
        );
      }
    } else {
      selectedUserId = await findAuthUserIdByEmail(
        adminClient,
        candidateEmail,
      );

      if (!selectedUserId) {
        const redirectUrl = nonBlank(
          Deno.env.get("CANDIDATE_PORTAL_REDIRECT_URL"),
        );

        if (!redirectUrl) {
          throw new HttpError(
            500,
            "Candidate portal invitation redirect is not configured.",
          );
        }

        const invitation = await adminClient.auth.admin.generateLink({
          type: "invite",
          email: candidateEmail,
          options: {
            data: {
              candidate_id: candidateId,
              full_name: candidateName,
            },
            redirectTo: redirectUrl,
          },
        });

        if (invitation.error) {
          if (!isExistingAuthUserError(invitation.error)) {
            logServerError("generate_candidate_invitation_link", invitation.error, {
              candidateId,
              actorUserId,
            });
            throw new HttpError(
              500,
              "Unable to create the candidate Auth account.",
            );
          }

          selectedUserId = await findAuthUserIdByEmail(
            adminClient,
            candidateEmail,
          );

          if (!selectedUserId) {
            logServerError(
              "find_auth_user_after_generate_link_conflict",
              new Error(
                "No Auth user ID was found after an existing-user error.",
              ),
              { candidateId, actorUserId },
            );
            throw new HttpError(
              500,
              "Unable to resolve the candidate Auth account.",
            );
          }
        } else {
          const generatedUserId = invitation.data.user?.id ?? null;
          const tokenHash =
            invitation.data.properties?.hashed_token?.trim() ?? "";
          const verificationType =
            invitation.data.properties?.verification_type ?? "";

          if (generatedUserId && UUID_PATTERN.test(generatedUserId)) {
            newlyInvitedUserId = generatedUserId;
          }

          if (
            !newlyInvitedUserId ||
            !tokenHash ||
            verificationType !== "invite"
          ) {
            logServerError(
              "generate_candidate_invitation_link_invalid_response",
              new Error(
                "generateLink returned no usable user ID or invite token.",
              ),
              { candidateId, actorUserId },
            );
            throw new HttpError(
              500,
              "Unable to create the candidate invitation.",
            );
          }

          selectedUserId = newlyInvitedUserId;
          const invitationLink = buildCandidatePortalSetupUrl(
            redirectUrl,
            tokenHash,
            verificationType,
          );

          let invitationTemplate: ReturnType<
            typeof buildCandidatePortalInvitationEmailTemplate
          >;

          try {
            invitationTemplate =
              buildCandidatePortalInvitationEmailTemplate({
                candidateName,
                invitationLink,
              });
          } catch (error) {
            logServerError(
              "build_candidate_portal_invitation_template",
              error,
              { candidateId, actorUserId },
            );
            throw new HttpError(
              500,
              "Unable to prepare the candidate portal invitation.",
            );
          }

          try {
            await sendEmailWithGmail(
              candidateEmail,
              invitationTemplate,
            );
            gmailInvitationDelivered = true;
            preserveInvitedUser = true;
            invitationSent = true;
          } catch (error) {
            if (
              error instanceof GmailProviderError &&
              error.deliveryOutcome === "UNKNOWN"
            ) {
              preserveInvitedUser = true;
              logServerError(
                "gmail_candidate_invitation_unknown_outcome",
                error,
                { candidateId, actorUserId },
              );
              throw new HttpError(
                502,
                "Candidate portal invitation delivery outcome is unknown. Check the Gmail Sent folder before retrying.",
              );
            }

            if (isGmailProviderError(error)) {
              logServerError(
                "gmail_candidate_invitation_definite_failure",
                error,
                { candidateId, actorUserId },
              );

              const publicMessage =
                error.stage === "CONFIGURATION"
                  ? "Candidate portal invitation delivery is not configured."
                  : error.retryable
                    ? "The email provider is temporarily unavailable."
                    : "The email provider rejected the candidate portal invitation.";

              throw new HttpError(error.httpStatus, publicMessage);
            }

            preserveInvitedUser = true;
            logServerError(
              "gmail_candidate_invitation_unclassified_failure",
              error,
              { candidateId, actorUserId },
            );
            throw new HttpError(
              502,
              "Candidate portal invitation delivery outcome is unknown. Check the Gmail Sent folder before retrying.",
            );
          }
        }
      }
    }

    if (!selectedUserId || !actorUserId) {
      throw new HttpError(500, "Unable to select the candidate Auth account.");
    }

    const finalizationResult = await adminClient.rpc(
      "finalize_candidate_portal_account",
      {
        p_candidate_id: candidateId,
        p_user_id: selectedUserId,
        p_actor_user_id: actorUserId,
      },
    );

    if (finalizationResult.error) {
      throw finalizationResult.error;
    }

    if (
      !Array.isArray(finalizationResult.data) ||
      finalizationResult.data.length !== 1 ||
      !isFinalizationRow(finalizationResult.data[0])
    ) {
      throw new HttpError(
        500,
        "Candidate portal account finalization returned an invalid result.",
      );
    }

    const finalization = finalizationResult.data[0];

    if (!ALLOWED_OUTCOMES.has(finalization.outcome)) {
      throw new HttpError(
        500,
        "Candidate portal account finalization returned an invalid outcome.",
      );
    }

    newlyInvitedUserId = null;

    return jsonResponse({
      success: true,
      outcome: finalization.outcome,
      candidate_id: finalization.candidate_id,
      user_id: finalization.user_id,
      email: finalization.email,
      invitation_sent: invitationSent,
    });
  } catch (error) {
    let compensationFailed = false;

    if (gmailInvitationDelivered) {
      logServerError(
        "candidate_portal_finalization_failed_after_gmail_delivery",
        error,
        {
          candidateId,
          actorUserId,
        },
      );

      return jsonResponse(
        {
          error:
            "Invitation email was sent, but portal account finalization is pending. Retry the action.",
        },
        500,
      );
    }

    if (
      newlyInvitedUserId &&
      adminClient &&
      !preserveInvitedUser &&
      !gmailInvitationDelivered
    ) {
      const compensation = await adminClient.auth.admin.deleteUser(
        newlyInvitedUserId,
      );

      if (compensation.error) {
        compensationFailed = true;
        logServerError("delete_invited_auth_user_compensation", compensation.error, {
          candidateId,
          actorUserId,
        });
      }
    }

    if (!(error instanceof HttpError)) {
      logServerError("create_candidate_portal_account", error, {
        candidateId,
        actorUserId,
      });
    }

    if (compensationFailed) {
      return jsonResponse(
        { error: "Candidate portal account activation could not be completed." },
        500,
      );
    }

    const publicError = classifyError(error);
    return jsonResponse({ error: publicError.publicMessage }, publicError.status);
  }
}

Deno.serve(handleRequest);
