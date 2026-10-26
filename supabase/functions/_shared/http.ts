// Shared HTTP helpers for edge functions.

const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

/** CORS headers: only origins listed in ALLOWED_ORIGINS (comma-separated) are echoed back. */
export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const ok = allowed.length === 0 || allowed.includes(origin);
  return {
    "Access-Control-Allow-Origin": ok ? origin || "*" : allowed[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

/** The public site URL used in Stripe redirects and email links. */
export function appUrl(req: Request): string {
  const origin = req.headers.get("origin") ?? "";
  if (origin && allowed.includes(origin)) return origin;
  const fallback = Deno.env.get("APP_URL");
  if (!fallback) throw new Error("APP_URL is not set");
  return fallback.replace(/\/$/, "");
}
