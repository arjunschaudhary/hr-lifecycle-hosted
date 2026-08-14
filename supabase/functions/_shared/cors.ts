const ALLOW_HEADERS =
  "authorization, apikey, content-type, x-client-info";
const ALLOW_METHODS = "POST, OPTIONS";

function getAllowedOrigins(): Set<string> {
  const allowedOrigins = new Set(
    (Deno.env.get("ALLOWED_ORIGINS") ?? "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  );
  const legacyAllowedOrigin = Deno.env.get("ALLOWED_ORIGIN")?.trim();

  if (legacyAllowedOrigin) {
    allowedOrigins.add(legacyAllowedOrigin);
  }

  return allowedOrigins;
}

export function isCorsOriginAllowed(request: Request): boolean {
  const requestOrigin = request.headers.get("Origin");
  return requestOrigin !== null && getAllowedOrigins().has(requestOrigin);
}

export function getCorsHeaders(request: Request): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": ALLOW_HEADERS,
    "Access-Control-Allow-Methods": ALLOW_METHODS,
  };
  const requestOrigin = request.headers.get("Origin");

  if (requestOrigin !== null) {
    headers.Vary = "Origin";
  }

  if (isCorsOriginAllowed(request)) {
    headers["Access-Control-Allow-Origin"] = requestOrigin as string;
  }

  return headers;
}
