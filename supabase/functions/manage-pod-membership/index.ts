import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const APPROVED_ROLES = [
  "ADMIN",
  "HR_LEAD",
  "HR_SITE_CONNECT_LEAD",
] as const;

const OPERATIONS = new Set([
  "CREATE_POD",
  "UPDATE_POD",
  "ASSIGN_CANDIDATE",
  "ASSIGN_LEAD",
  "ASSIGN_HR_REVIEWER",
  "END_MEMBERSHIP",
]);

const SAFE_DATABASE_MESSAGES = new Set([
  "Pod Management access is not permitted.",
  "Pod code already exists.",
  "Pod code is invalid.",
  "Pod name is invalid.",
  "Pod description is too long.",
  "Pod was not found.",
  "Pod update values are required.",
  "Pod cannot be deactivated while active memberships remain.",
  "Candidate, pod, and effective date are required.",
  "Candidate or pod was not found.",
  "Candidates cannot be assigned to an inactive pod.",
  "Candidate already has an active membership in this pod.",
  "Transfer date must be after the current membership start date.",
  "Candidate pod membership dates overlap an existing membership.",
  "Candidate, pod, lead type, and effective date are required.",
  "Lead type must be POD_LEAD or TECH_LEAD.",
  "Candidate was not found.",
  "Active pod was not found.",
  "Candidate portal user is not active.",
  "Candidate role is not active for the mapped portal user.",
  "An active HR Psyconnect user cannot be assigned as Project Manager.",
  "HR Psyconnect candidates cannot be assigned as Project Manager.",
  "Lead membership dates overlap an existing lead assignment in this pod.",
  "Required candidate portal account or active role was not found.",
  "HR Psyconnect reviewer assignment values are invalid.",
  "HR Psyconnect reviewers cannot be assigned to an inactive pod.",
  "HR Psyconnect reviewer was not found.",
  "Target user does not have active HR_SITE_CONNECT access.",
  "Pod already has an active HR Psyconnect reviewer. End the current membership before assigning another.",
  "HR Psyconnect reviewer membership dates overlap an existing assignment in this pod.",
  "Membership and end date are required.",
  "Pod membership is already inactive.",
  "Membership end date cannot be earlier than its start date.",
  "Pod membership was not found.",
]);

type JsonRecord = Record<string, unknown>;

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonBlank(value: unknown): string | null {
  return typeof value === "string" && value.trim()
    ? value.trim()
    : null;
}

function validUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value.trim());
}

function validDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}

function getCorsHeaders(): Record<string, string> {
  const configuredOrigin = nonBlank(Deno.env.get("ALLOWED_ORIGIN"));
  return {
    "Access-Control-Allow-Origin": configuredOrigin ?? "*",
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Vary": "Origin",
  };
}

function jsonResponse(body: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: getCorsHeaders(),
  });
}

function getBearerToken(request: Request): string | null {
  const authorization = request.headers.get("Authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

function getConfiguration() {
  const supabaseUrl = nonBlank(Deno.env.get("SUPABASE_URL"));
  const anonKey = nonBlank(Deno.env.get("SUPABASE_ANON_KEY"));
  const serviceRoleKey = nonBlank(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    throw new HttpError(500, "Pod Management is not configured.");
  }

  return { supabaseUrl, anonKey, serviceRoleKey };
}

function createCallerClient(
  supabaseUrl: string,
  anonKey: string,
  accessToken: string,
): SupabaseClient {
  return createClient(supabaseUrl, anonKey, {
    global: {
      headers: { Authorization: `Bearer ${accessToken}` },
    },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function createAdminClient(
  supabaseUrl: string,
  serviceRoleKey: string,
): SupabaseClient {
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function safeDatabaseMessage(error: unknown): string {
  if (isRecord(error) && typeof error.message === "string") {
    for (const safeMessage of SAFE_DATABASE_MESSAGES) {
      if (error.message.includes(safeMessage)) {
        return safeMessage;
      }
    }
  }
  return "Unable to complete the Pod Management operation.";
}

function logServerError(
  operation: string,
  context: {
    candidateId?: string;
    userId?: string;
    podId?: string;
    jobId?: string;
  } = {},
): void {
  console.error("manage-pod-membership error", {
    operation,
    candidate_id: context.candidateId,
    user_id: context.userId,
    pod_id: context.podId,
    job_id: context.jobId,
  });
}

function requireExactKeys(
  body: JsonRecord,
  expectedKeys: string[],
): void {
  const actualKeys = Object.keys(body).sort();
  const requiredKeys = [...expectedKeys].sort();
  if (
    actualKeys.length !== requiredKeys.length ||
    actualKeys.some((key, index) => key !== requiredKeys[index])
  ) {
    throw new HttpError(400, "Pod Management request fields are invalid.");
  }
}

function parseRequest(body: unknown): {
  operation: string;
  rpcName: string;
  rpcArgs: JsonRecord;
  candidateId?: string;
  userId?: string;
  podId?: string;
} {
  if (!isRecord(body) || !nonBlank(body.operation)) {
    throw new HttpError(400, "A valid Pod Management operation is required.");
  }

  const operation = String(body.operation).trim().toUpperCase();
  if (!OPERATIONS.has(operation)) {
    throw new HttpError(400, "Pod Management operation is not supported.");
  }

  if (operation === "CREATE_POD") {
    requireExactKeys(body, ["operation", "podCode", "podName", "description"]);
    const podCode = nonBlank(body.podCode);
    const podName = nonBlank(body.podName);
    if (!podCode || !podName || (body.description !== null &&
      typeof body.description !== "string")) {
      throw new HttpError(400, "Pod creation values are invalid.");
    }
    return {
      operation,
      rpcName: "create_pod",
      rpcArgs: {
        p_pod_code: podCode,
        p_pod_name: podName,
        p_description: body.description,
      },
    };
  }

  if (operation === "UPDATE_POD") {
    requireExactKeys(body, [
      "operation",
      "podId",
      "podName",
      "description",
      "isActive",
    ]);
    const podName = nonBlank(body.podName);
    if (
      !validUuid(body.podId) ||
      !podName ||
      (body.description !== null && typeof body.description !== "string") ||
      typeof body.isActive !== "boolean"
    ) {
      throw new HttpError(400, "Pod update values are invalid.");
    }
    const podId = body.podId.trim().toLowerCase();
    return {
      operation,
      rpcName: "update_pod",
      rpcArgs: {
        p_pod_id: podId,
        p_pod_name: podName,
        p_description: body.description,
        p_is_active: body.isActive,
      },
      podId,
    };
  }

  if (operation === "ASSIGN_CANDIDATE") {
    requireExactKeys(body, [
      "operation",
      "candidateId",
      "podId",
      "effectiveFrom",
    ]);
    if (
      !validUuid(body.candidateId) ||
      !validUuid(body.podId) ||
      !validDate(body.effectiveFrom)
    ) {
      throw new HttpError(400, "Candidate pod assignment values are invalid.");
    }
    const candidateId = body.candidateId.trim().toLowerCase();
    const podId = body.podId.trim().toLowerCase();
    return {
      operation,
      rpcName: "assign_candidate_to_pod",
      rpcArgs: {
        p_candidate_id: candidateId,
        p_pod_id: podId,
        p_effective_from: body.effectiveFrom,
      },
      candidateId,
      podId,
    };
  }

  if (operation === "ASSIGN_LEAD") {
    requireExactKeys(body, [
      "operation",
      "candidateId",
      "podId",
      "leadType",
      "effectiveFrom",
    ]);
    const leadType = nonBlank(body.leadType)?.toUpperCase();
    if (
      !validUuid(body.candidateId) ||
      !validUuid(body.podId) ||
      !validDate(body.effectiveFrom) ||
      (leadType !== "POD_LEAD" && leadType !== "TECH_LEAD")
    ) {
      throw new HttpError(400, "Lead assignment values are invalid.");
    }
    const candidateId = body.candidateId.trim().toLowerCase();
    const podId = body.podId.trim().toLowerCase();
    return {
      operation,
      rpcName: "assign_candidate_lead_to_pod",
      rpcArgs: {
        p_candidate_id: candidateId,
        p_pod_id: podId,
        p_lead_type: leadType,
        p_effective_from: body.effectiveFrom,
      },
      candidateId,
      podId,
    };
  }

  if (operation === "ASSIGN_HR_REVIEWER") {
    requireExactKeys(body, [
      "operation",
      "userId",
      "podId",
      "effectiveFrom",
    ]);
    if (
      !validUuid(body.userId) ||
      !validUuid(body.podId) ||
      !validDate(body.effectiveFrom)
    ) {
      throw new HttpError(
        400,
        "HR Psyconnect reviewer assignment values are invalid.",
      );
    }
    const userId = body.userId.trim().toLowerCase();
    const podId = body.podId.trim().toLowerCase();
    return {
      operation,
      rpcName: "assign_hr_site_connect_to_pod",
      rpcArgs: {
        p_user_id: userId,
        p_pod_id: podId,
        p_effective_from: body.effectiveFrom,
      },
      userId,
      podId,
    };
  }

  requireExactKeys(body, ["operation", "membershipId", "effectiveTo"]);
  if (!validUuid(body.membershipId) || !validDate(body.effectiveTo)) {
    throw new HttpError(400, "Membership end values are invalid.");
  }
  return {
    operation,
    rpcName: "end_pod_membership",
    rpcArgs: {
      p_membership_id: body.membershipId.trim().toLowerCase(),
      p_effective_to: body.effectiveTo,
    },
  };
}

function isSuccessfulRpcResult(value: unknown): value is JsonRecord {
  return isRecord(value) && value.success === true;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders() });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const accessToken = getBearerToken(request);
  if (!accessToken) {
    return jsonResponse({ error: "A valid Bearer token is required." }, 401);
  }

  let requestContext:
    | ReturnType<typeof parseRequest>
    | undefined;

  try {
    const { supabaseUrl, anonKey, serviceRoleKey } = getConfiguration();
    const callerClient = createCallerClient(supabaseUrl, anonKey, accessToken);
    const adminClient = createAdminClient(supabaseUrl, serviceRoleKey);

    const userResult = await callerClient.auth.getUser(accessToken);
    if (userResult.error || !userResult.data.user) {
      throw new HttpError(401, "Authentication is required.");
    }

    const [activeResult, roleResult] = await Promise.all([
      callerClient.rpc("current_user_is_active"),
      callerClient.rpc("current_user_has_any_role", {
        p_role_slugs: APPROVED_ROLES,
      }),
    ]);

    if (
      activeResult.error ||
      roleResult.error ||
      activeResult.data !== true ||
      roleResult.data !== true
    ) {
      throw new HttpError(403, "Pod Management access is not permitted.");
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      throw new HttpError(400, "A valid JSON request body is required.");
    }

    requestContext = parseRequest(body);
    const operationResult = await callerClient.rpc(
      requestContext.rpcName,
      requestContext.rpcArgs,
    );

    if (operationResult.error) {
      logServerError("pod_operation", {
        candidateId: requestContext.candidateId,
        userId: requestContext.userId,
        podId: requestContext.podId,
      });
      throw new HttpError(400, safeDatabaseMessage(operationResult.error));
    }
    if (!isSuccessfulRpcResult(operationResult.data)) {
      logServerError("invalid_pod_operation_response", {
        candidateId: requestContext.candidateId,
        userId: requestContext.userId,
        podId: requestContext.podId,
      });
      throw new HttpError(
        500,
        "Unable to confirm the Pod Management operation.",
      );
    }

    let performanceRetry: JsonRecord = {
      attempted: false,
      success: false,
      message: "No performance-assignment retry was requested.",
    };

    if (
      requestContext.operation === "ASSIGN_CANDIDATE" &&
      operationResult.data.performanceRetryAllowed === true &&
      validUuid(operationResult.data.performanceJobId) &&
      (operationResult.data.performanceJobStatus === "PENDING" ||
        operationResult.data.performanceJobStatus === "RETRY")
    ) {
      const jobId = operationResult.data.performanceJobId
        .trim()
        .toLowerCase();
      const processorResult = await adminClient.rpc(
        "process_performance_cycle_assignment_job",
        { p_job_id: jobId },
      );

      if (
        processorResult.error ||
        !isSuccessfulRpcResult(processorResult.data)
      ) {
        logServerError("performance_assignment_retry", {
          candidateId: requestContext.candidateId,
          userId: requestContext.userId,
          podId: requestContext.podId,
          jobId,
        });
        performanceRetry = {
          attempted: true,
          success: false,
          jobId,
          message:
            "Pod assignment succeeded, but performance assignment could not be retried.",
        };
      } else {
        performanceRetry = {
          attempted: true,
          success: processorResult.data.jobStatus === "SUCCESS",
          jobId,
          jobStatus: processorResult.data.jobStatus,
          performanceOutcome: processorResult.data.performanceOutcome,
          message: typeof processorResult.data.message === "string"
            ? processorResult.data.message
            : "Performance-assignment retry completed.",
        };
      }
    } else if (requestContext.operation === "ASSIGN_CANDIDATE") {
      performanceRetry = {
        attempted: false,
        success: false,
        jobId: operationResult.data.performanceJobId ?? null,
        jobStatus: operationResult.data.performanceJobStatus ?? null,
        message: typeof operationResult.data.performanceMessage === "string"
          ? operationResult.data.performanceMessage
          : "No eligible performance-assignment retry exists.",
      };
    }

    return jsonResponse({
      success: true,
      operation: requestContext.operation,
      podOperation: operationResult.data,
      performanceRetry,
    });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    logServerError("unexpected_request_failure", {
      candidateId: requestContext?.candidateId,
      userId: requestContext?.userId,
      podId: requestContext?.podId,
    });
    return jsonResponse(
      { error: "Unable to complete the Pod Management operation." },
      500,
    );
  }
});
