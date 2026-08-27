import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";
import { getCorsHeaders } from "../_shared/cors.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function response(request: Request, body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...getCorsHeaders(request), "Content-Type": "application/json; charset=utf-8" },
  });
}

function bearerToken(request: Request): string | null {
  const match = request.headers.get("authorization")?.match(/^Bearer\s+([^\s]+)$/i);
  return match?.[1] ?? null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: getCorsHeaders(request) });
  if (request.method !== "POST") return response(request, { error: "Method not allowed." }, 405);

  const accessToken = bearerToken(request);
  const { requestIds } = await request.json().catch(() => ({}));
  if (!accessToken || !Array.isArray(requestIds) || requestIds.length === 0 || requestIds.length > 6
    || requestIds.some((id) => typeof id !== "string" || !UUID.test(id))
    || new Set(requestIds).size !== requestIds.length) {
    return response(request, { error: "Valid document request IDs are required." }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return response(request, { error: "Dispatch configuration is incomplete." }, 500);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userResult, error: userError } = await caller.auth.getUser(accessToken);
  if (userError || !userResult.user) return response(request, { error: "Authentication is required." }, 401);
  const { data: hasAccess, error: accessError } = await caller.rpc("current_user_has_role", { p_role_slug: "HR_SITE_CONNECT_LEAD" });
  if (accessError || hasAccess !== true) return response(request, { error: "HR Site Connect Lead access is required." }, 403);

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: requests, error: requestsError } = await admin
    .from("exit_document_requests")
    .select("request_id,job_id")
    .in("request_id", requestIds);
  if (requestsError || !requests || requests.length !== requestIds.length || requests.some((item) => !item.job_id)) {
    return response(request, { error: "Document requests could not be resolved for dispatch." }, 409);
  }

  const jobIds = requests.map((item) => item.job_id as string);
  const { data: jobs, error: jobsError } = await admin
    .from("automation_jobs")
    .select("job_id")
    .eq("job_type", "EXIT_DOCUMENT")
    .in("job_id", jobIds)
    .in("job_status", ["PENDING", "RETRY"]);
  if (jobsError) return response(request, { error: "Document jobs could not be resolved for dispatch." }, 500);

  const dispatches = await Promise.all((jobs ?? []).map(async ({ job_id }) => {
    try {
      const workerResponse = await fetch(`${url}/functions/v1/process-exit-document`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceKey}`,
          apikey: serviceKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ jobId: job_id }),
      });
      return { jobId: job_id, accepted: workerResponse.ok || workerResponse.status === 202 };
    } catch {
      return { jobId: job_id, accepted: false };
    }
  }));

  return response(request, {
    queued: requestIds.length,
    dispatched: dispatches.filter((dispatch) => dispatch.accepted).length,
    dispatchPending: dispatches.filter((dispatch) => !dispatch.accepted).length,
  }, 202);
});
