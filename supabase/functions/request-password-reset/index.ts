import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  isGmailProviderError,
  sendEmailWithGmail,
} from "../_shared/gmailProvider.ts";
import { buildPasswordResetEmailTemplate } from "../_shared/passwordResetEmailTemplate.ts";
import {
  getCorsHeaders,
  isCorsOriginAllowed,
} from "../_shared/cors.ts";

const EMAIL_PATTERN = /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/;
const EMAIL_MAX_LENGTH = 254;
const MAX_REQUEST_BODY_BYTES = 1024;
const THROTTLE_WINDOW_SECONDS = 300;
const GENERIC_SUCCESS_BODY = Object.freeze({ success: true });

type Configuration = {
  supabaseUrl: string;
  secretKey: string;
  redirectUrl: string;
  throttleSecret: string;
};

type ErrorDetails = {
  code?: string;
  status?: number;
  message: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonBlank(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  return normalized ? normalized : undefined;
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
  } catch {
    return raw;
  }

  return undefined;
}

function validateConfiguredUrl(value: string | undefined): string {
  const configuredValue = nonBlank(value);

  if (!configuredValue) {
    throw new Error("Password reset redirect is not configured.");
  }

  const url = new URL(configuredValue);

  if (
    !["https:", "http:"].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  ) {
    throw new Error("Password reset redirect is invalid.");
  }

  return url.toString();
}

function getConfiguration(): Configuration {
  const supabaseUrl = nonBlank(Deno.env.get("SUPABASE_URL"));
  const secretKey =
    extractKeyValue(Deno.env.get("SUPABASE_SECRET_KEYS")) ??
    nonBlank(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const throttleSecret = nonBlank(
    Deno.env.get("PASSWORD_RESET_THROTTLE_SECRET"),
  );

  if (
    !supabaseUrl ||
    !secretKey ||
    !throttleSecret ||
    throttleSecret.length < 32 ||
    /[\r\n]/.test(throttleSecret)
  ) {
    throw new Error("Password reset service configuration is incomplete.");
  }

  return {
    supabaseUrl,
    secretKey,
    redirectUrl: validateConfiguredUrl(
      Deno.env.get("PASSWORD_RESET_REDIRECT_URL"),
    ),
    throttleSecret,
  };
}

function createAdminClient(configuration: Configuration): SupabaseClient {
  return createClient(configuration.supabaseUrl, configuration.secretKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
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
      "Cache-Control": "no-store",
    },
  });
}

function normalizeEmail(value: string): string | null {
  const normalized = value.trim().toLowerCase();

  if (
    !normalized ||
    normalized.length > EMAIL_MAX_LENGTH ||
    /[\r\n]/.test(normalized) ||
    !EMAIL_PATTERN.test(normalized)
  ) {
    return null;
  }

  return normalized;
}

async function createRequestKey(
  email: string,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(email),
  );

  return Array.from(new Uint8Array(signature), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function getErrorDetails(error: unknown): ErrorDetails {
  if (isRecord(error)) {
    return {
      code: typeof error.code === "string" ? error.code : undefined,
      status: typeof error.status === "number" ? error.status : undefined,
      message:
        typeof error.message === "string" ? error.message : "Unknown error",
    };
  }

  if (error instanceof Error) {
    return { message: error.message };
  }

  return { message: "Unknown error" };
}

function isMissingAuthUserError(error: unknown): boolean {
  const details = getErrorDetails(error);
  const message = details.message.toLowerCase();

  return (
    details.code === "user_not_found" ||
    details.status === 404 ||
    message.includes("user not found") ||
    message.includes("no user")
  );
}

function logServerFailure(operation: string, error: unknown): void {
  const details = getErrorDetails(error);

  console.error("request-password-reset failure", {
    operation,
    error_code: details.code,
    error_status: details.status,
    error_type: error instanceof Error ? error.name : typeof error,
  });
}

function extractRecoveryActionLink(
  value: unknown,
  supabaseUrl: string,
  expectedRedirectUrl: string,
): string | null {
  if (!isRecord(value) || !isRecord(value.properties)) {
    return null;
  }

  const actionLinkValue = value.properties.action_link;
  const redirectValue = value.properties.redirect_to;
  const verificationType = value.properties.verification_type;

  if (
    typeof actionLinkValue !== "string" ||
    typeof redirectValue !== "string" ||
    verificationType !== "recovery"
  ) {
    return null;
  }

  try {
    const actionUrl = new URL(actionLinkValue);
    const authOrigin = new URL(supabaseUrl).origin;
    const redirectUrl = new URL(redirectValue).toString();

    if (
      actionUrl.origin !== authOrigin ||
      !actionUrl.pathname.endsWith("/auth/v1/verify") ||
      actionUrl.username ||
      actionUrl.password ||
      actionUrl.searchParams.get("type") !== "recovery" ||
      !actionUrl.searchParams.get("token") ||
      redirectUrl !== expectedRedirectUrl
    ) {
      return null;
    }

    return actionUrl.toString();
  } catch {
    return null;
  }
}

async function handleRequest(request: Request): Promise<Response> {
  const jsonResponse = (
    body: Record<string, unknown>,
    status = 200,
  ) => createJsonResponse(request, body, status);

  if (!isCorsOriginAllowed(request)) {
    return jsonResponse({ error: "Origin is not allowed." }, 403);
  }

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: getCorsHeaders(request),
    });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Only POST requests are supported." }, 405);
  }

  const contentType = request.headers.get("content-type") ?? "";

  if (!contentType.toLowerCase().startsWith("application/json")) {
    return jsonResponse({ error: "Request body must be JSON." }, 415);
  }

  let rawBody: string;

  try {
    rawBody = await request.text();
  } catch {
    return jsonResponse({ error: "Request body could not be read." }, 400);
  }

  if (!rawBody || new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BODY_BYTES) {
    return jsonResponse({ error: "Request body is invalid." }, 400);
  }

  let requestBody: unknown;

  try {
    requestBody = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  if (!isRecord(requestBody)) {
    return jsonResponse({ error: "Request body must be an object." }, 400);
  }

  const requestKeys = Object.keys(requestBody);

  if (
    requestKeys.length !== 1 ||
    requestKeys[0] !== "email" ||
    typeof requestBody.email !== "string"
  ) {
    return jsonResponse(
      { error: "Request body must contain only email." },
      400,
    );
  }

  const email = normalizeEmail(requestBody.email);

  if (!email) {
    return jsonResponse({ error: "A valid email address is required." }, 400);
  }

  let configuration: Configuration;

  try {
    configuration = getConfiguration();
  } catch (error) {
    logServerFailure("configuration", error);
    return jsonResponse(
      { error: "Password reset service is temporarily unavailable." },
      503,
    );
  }

  const adminClient = createAdminClient(configuration);
  let requestKey: string;

  try {
    requestKey = await createRequestKey(email, configuration.throttleSecret);
  } catch (error) {
    logServerFailure("create_request_key", error);
    return jsonResponse(
      { error: "Password reset service is temporarily unavailable." },
      503,
    );
  }

  const throttleResult = await adminClient.rpc(
    "claim_password_reset_request_slot",
    {
      p_request_key: requestKey,
      p_window_seconds: THROTTLE_WINDOW_SECONDS,
    },
  );

  if (throttleResult.error || typeof throttleResult.data !== "boolean") {
    logServerFailure(
      "claim_password_reset_request_slot",
      throttleResult.error ?? new Error("Throttle RPC returned invalid data."),
    );
    return jsonResponse(
      { error: "Password reset service is temporarily unavailable." },
      503,
    );
  }

  if (!throttleResult.data) {
    return jsonResponse(GENERIC_SUCCESS_BODY);
  }

  let linkResult: Awaited<
    ReturnType<typeof adminClient.auth.admin.generateLink>
  >;

  try {
    linkResult = await adminClient.auth.admin.generateLink({
      type: "recovery",
      email,
      options: {
        redirectTo: configuration.redirectUrl,
      },
    });
  } catch (error) {
    logServerFailure("generate_recovery_link", error);
    return jsonResponse(GENERIC_SUCCESS_BODY);
  }

  if (linkResult.error) {
    if (!isMissingAuthUserError(linkResult.error)) {
      logServerFailure("generate_recovery_link", linkResult.error);
    }

    return jsonResponse(GENERIC_SUCCESS_BODY);
  }

  const recoveryLink = extractRecoveryActionLink(
    linkResult.data,
    configuration.supabaseUrl,
    configuration.redirectUrl,
  );

  if (!recoveryLink) {
    logServerFailure(
      "validate_recovery_link",
      new Error("Supabase returned an invalid recovery link."),
    );
    return jsonResponse(GENERIC_SUCCESS_BODY);
  }

  try {
    const template = buildPasswordResetEmailTemplate({
      resetLink: recoveryLink,
    });
    await sendEmailWithGmail(email, template);
  } catch (error) {
    if (isGmailProviderError(error)) {
      console.error("request-password-reset Gmail failure", {
        operation: "send_recovery_email",
        stage: error.stage,
        delivery_outcome: error.deliveryOutcome,
        retryable: error.retryable,
        safe_failure: error.safeFailureMessage,
      });
    } else {
      logServerFailure("send_recovery_email", error);
    }

    return jsonResponse(GENERIC_SUCCESS_BODY);
  }

  return jsonResponse(GENERIC_SUCCESS_BODY);
}

Deno.serve(handleRequest);
