import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HR_ROLE_SLUGS = [
  "HR_SITE_CONNECT",
  "HR_SITE_CONNECT_LEAD",
  "HR_LEAD",
  "ADMIN",
];
const JOB_STATUSES = new Set([
  "PENDING",
  "PROCESSING",
  "SUCCESS",
  "FAILED",
  "RETRY",
  "CANCELLED",
]);
const PERFORMANCE_OUTCOMES = new Set([
  "PERFORMANCE_ASSIGNED",
  "PERFORMANCE_PENDING_POD",
  "PERFORMANCE_PENDING_CYCLE",
  "PERFORMANCE_FAILED",
]);
const SAFE_TRANSITION_MESSAGES = new Set([
  "Candidate lifecycle record was not found.",
  "Candidate has multiple lifecycle records.",
  "Candidate probation start date is required.",
  "Candidate probation start date cannot be in the future.",
  "Candidate lifecycle status must be WELCOME_MAIL_SENT.",
  "Candidate lifecycle changed during processing.",
  "Performance-assignment job state is inconsistent.",
]);

type TransitionResult = {
  candidateId: string;
  lifecycleStatus: "IN_PROBATION";
  transitionCompleted: boolean;
  jobId: string;
  jobStatus: string;
};

type ProcessingResult = {
  candidateId: string;
  jobId: string;
  jobStatus: string;
  performanceOutcome: string;
  message: string;
  cycleId?: string;
  assignmentId?: string;
  eligibleDays?: number;
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

function getSafeRpcMessage(error: unknown): string | null {
  if (!isRecord(error) || typeof error.message !== "string") {
    return null;
  }

  const message = error.message.trim();
  return SAFE_TRANSITION_MESSAGES.has(message) ? message : null;
}

function logServerError(
  operation: string,
  context: { candidateId?: string; jobId?: string } = {},
): void {
  console.error("mark-candidate-in-probation error", {
    operation,
    candidate_id: context.candidateId,
    job_id: context.jobId,
  });
}

function getConfiguration(): {
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
    throw new HttpError(
      500,
      "In-probation automation is not configured.",
    );
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

function parseTransitionResult(
  value: unknown,
  candidateId: string,
): TransitionResult | null {
  if (
    !isRecord(value) ||
    value.success !== true ||
    typeof value.candidateId !== "string" ||
    value.candidateId.toLowerCase() !== candidateId ||
    value.lifecycleStatus !== "IN_PROBATION" ||
    typeof value.transitionCompleted !== "boolean" ||
    typeof value.jobId !== "string" ||
    !UUID_PATTERN.test(value.jobId) ||
    typeof value.jobStatus !== "string" ||
    !JOB_STATUSES.has(value.jobStatus)
  ) {
    return null;
  }

  return {
    candidateId: value.candidateId,
    lifecycleStatus: "IN_PROBATION",
    transitionCompleted: value.transitionCompleted,
    jobId: value.jobId,
    jobStatus: value.jobStatus,
  };
}

function parseProcessingResult(
  value: unknown,
  transition: TransitionResult,
): ProcessingResult | null {
  if (
    !isRecord(value) ||
    value.success !== true ||
    typeof value.candidateId !== "string" ||
    value.candidateId.toLowerCase() !== transition.candidateId.toLowerCase() ||
    value.jobId !== transition.jobId ||
    typeof value.jobStatus !== "string" ||
    !JOB_STATUSES.has(value.jobStatus) ||
    typeof value.performanceOutcome !== "string" ||
    !PERFORMANCE_OUTCOMES.has(value.performanceOutcome) ||
    typeof value.message !== "string" ||
    !value.message.trim()
  ) {
    return null;
  }

  const result: ProcessingResult = {
    candidateId: value.candidateId,
    jobId: value.jobId,
    jobStatus: value.jobStatus,
    performanceOutcome: value.performanceOutcome,
    message: value.message.trim(),
  };

  if (
    typeof value.cycleId === "string" &&
    UUID_PATTERN.test(value.cycleId)
  ) {
    result.cycleId = value.cycleId;
  }

  if (
    typeof value.assignmentId === "string" &&
    UUID_PATTERN.test(value.assignmentId)
  ) {
    result.assignmentId = value.assignmentId;
  }

  if (
    Number.isInteger(value.eligibleDays) &&
    Number(value.eligibleDays) >= 0
  ) {
    result.eligibleDays = Number(value.eligibleDays);
  }

  return result;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders() });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const accessToken = extractBearerToken(request);

  if (!accessToken) {
    return jsonResponse({ error: "A valid Bearer token is required." }, 401);
  }

  let candidateId = "";

  try {
    let requestBody: unknown;

    try {
      requestBody = await request.json();
    } catch {
      throw new HttpError(400, "A valid request body is required.");
    }

    if (
      !isRecord(requestBody) ||
      Object.keys(requestBody).length !== 1 ||
      typeof requestBody.candidateId !== "string"
    ) {
      throw new HttpError(400, "A valid candidate ID is required.");
    }

    candidateId = requestBody.candidateId.trim().toLowerCase();

    if (!UUID_PATTERN.test(candidateId)) {
      throw new HttpError(400, "A valid candidate ID is required.");
    }

    const { supabaseUrl, anonKey, serviceRoleKey } = getConfiguration();
    const callerClient = createCallerClient(
      supabaseUrl,
      anonKey,
      accessToken,
    );
    const adminClient = createAdminClient(supabaseUrl, serviceRoleKey);

    const userResult = await callerClient.auth.getUser(accessToken);

    if (userResult.error || !userResult.data.user) {
      throw new HttpError(401, "Your session is invalid or expired.");
    }

    const [activeUserResult, roleResult] = await Promise.all([
      callerClient.rpc("current_user_is_active"),
      callerClient.rpc("current_user_has_any_role", {
        p_role_slugs: HR_ROLE_SLUGS,
      }),
    ]);

    if (
      activeUserResult.error ||
      roleResult.error ||
      activeUserResult.data !== true ||
      roleResult.data !== true
    ) {
      throw new HttpError(
        403,
        "You do not have permission to mark this candidate in probation.",
      );
    }

    const transitionRpcResult = await callerClient.rpc(
      "mark_candidate_in_probation_and_enqueue_performance_assignment",
      {
        p_candidate_id: candidateId,
      },
    );

    if (transitionRpcResult.error) {
      throw new HttpError(
        transitionRpcResult.error.code === "42501" ? 403 : 400,
        getSafeRpcMessage(transitionRpcResult.error) ??
          "Unable to mark the candidate in probation.",
      );
    }

    const transition = parseTransitionResult(
      transitionRpcResult.data,
      candidateId,
    );

    if (!transition) {
      logServerError("invalid_transition_response", { candidateId });
      throw new HttpError(
        500,
        "Unable to confirm the in-probation transition.",
      );
    }

    const processingRpcResult = await adminClient.rpc(
      "process_performance_cycle_assignment_job",
      {
        p_job_id: transition.jobId,
      },
    );

    if (processingRpcResult.error) {
      logServerError("process_performance_assignment", {
        candidateId,
        jobId: transition.jobId,
      });

      return jsonResponse({
        success: true,
        candidateId: transition.candidateId,
        lifecycleStatus: transition.lifecycleStatus,
        transitionCompleted: transition.transitionCompleted,
        jobId: transition.jobId,
        jobStatus: transition.jobStatus,
        performanceOutcome: "PERFORMANCE_FAILED",
        performanceMessage:
          "Performance-cycle assignment could not be completed. The lifecycle transition remains successful.",
      });
    }

    const processing = parseProcessingResult(
      processingRpcResult.data,
      transition,
    );

    if (!processing) {
      logServerError("invalid_processing_response", {
        candidateId,
        jobId: transition.jobId,
      });

      return jsonResponse({
        success: true,
        candidateId: transition.candidateId,
        lifecycleStatus: transition.lifecycleStatus,
        transitionCompleted: transition.transitionCompleted,
        jobId: transition.jobId,
        jobStatus: transition.jobStatus,
        performanceOutcome: "PERFORMANCE_FAILED",
        performanceMessage:
          "Performance-cycle assignment could not be confirmed. The lifecycle transition remains successful.",
      });
    }

    return jsonResponse({
      success: true,
      candidateId: transition.candidateId,
      lifecycleStatus: transition.lifecycleStatus,
      transitionCompleted: transition.transitionCompleted,
      jobId: processing.jobId,
      jobStatus: processing.jobStatus,
      performanceOutcome: processing.performanceOutcome,
      performanceMessage: processing.message,
      ...(processing.cycleId
        ? { cycleId: processing.cycleId }
        : {}),
      ...(processing.assignmentId
        ? { assignmentId: processing.assignmentId }
        : {}),
      ...(processing.eligibleDays !== undefined
        ? { eligibleDays: processing.eligibleDays }
        : {}),
    });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.publicMessage }, error.status);
    }

    logServerError("unexpected_request_failure", {
      candidateId: candidateId || undefined,
    });
    return jsonResponse(
      { error: "Unable to mark the candidate in probation." },
      500,
    );
  }
});
