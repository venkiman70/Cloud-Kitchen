// notify-ready: the kitchen board calls this after marking an order Ready.
// Checks the caller is staff for that order's tenant, then emails the customer once.
//
// POST { orderId }   (Authorization: Bearer <staff user's access token>)

import { createClient } from "npm:@supabase/supabase-js@2.46.1";

// ---- inlined from _shared/http.ts ----
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

// ---- inlined from _shared/email.ts ----
// Transactional email through Resend. If RESEND_API_KEY is missing, emails are
// logged and skipped so local and staging setups still work.

export type Receipt = {
  orderNumber: string;
  publicToken: string;
  customerName?: string | null;
  customerEmail?: string | null;
  pickupAt: string;
  timezone: string;
  currency: string;
  brandName: string;
  tenantName: string;
  address?: string | null;
  pickupInstructions?: string | null;
  subtotalCents: number;
  taxCents: number;
  totalCents: number;
  items: { name: string; variant?: string | null; quantity: number; lineTotalCents: number }[];
};

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

export const money = (cents: number, currency = "usd") =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: currency.toUpperCase() }).format(cents / 100);

export const pickupText = (iso: string, timeZone: string) =>
  new Intl.DateTimeFormat("en-US", {
    timeZone, weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  }).format(new Date(iso));

function layout(r: Receipt, heading: string, intro: string, statusUrl: string): string {
  const rows = (r.items ?? []).map((i) =>
    `<tr><td style="padding:6px 0">${i.quantity} × ${esc(i.name)}${i.variant ? ` <span style="color:#666">(${esc(i.variant)})</span>` : ""}</td>
     <td style="padding:6px 0;text-align:right">${money(i.lineTotalCents, r.currency)}</td></tr>`
  ).join("");
  return `<!doctype html><html><body style="font-family:Arial,Helvetica,sans-serif;color:#1d2219;max-width:520px;margin:0 auto;padding:16px">
  <p style="font-size:13px;color:#666;margin:0">${esc(r.brandName)}</p>
  <h1 style="font-size:22px;margin:4px 0 12px">${esc(heading)}</h1>
  <p style="margin:0 0 12px">${esc(intro)}</p>
  <p style="margin:0 0 4px"><b>Order ${esc(r.orderNumber)}</b></p>
  <p style="margin:0 0 16px">Pickup: ${esc(pickupText(r.pickupAt, r.timezone))}${r.address ? `<br>${esc(r.address)}` : ""}</p>
  <table style="width:100%;border-collapse:collapse;font-size:14px">${rows}
    <tr><td style="padding:6px 0;border-top:1px solid #ddd">Subtotal</td><td style="padding:6px 0;border-top:1px solid #ddd;text-align:right">${money(r.subtotalCents, r.currency)}</td></tr>
    <tr><td style="padding:2px 0">Sales tax</td><td style="padding:2px 0;text-align:right">${money(r.taxCents, r.currency)}</td></tr>
    <tr><td style="padding:6px 0"><b>Total paid</b></td><td style="padding:6px 0;text-align:right"><b>${money(r.totalCents, r.currency)}</b></td></tr>
  </table>
  ${r.pickupInstructions ? `<p style="margin:16px 0 0;font-size:14px">${esc(r.pickupInstructions)}</p>` : ""}
  <p style="margin:20px 0"><a href="${esc(statusUrl)}" style="background:#2f6b3a;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">View order status</a></p>
  <p style="font-size:12px;color:#888">${esc(r.tenantName)}</p>
  </body></html>`;
}

async function send(to: string, subject: string, html: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("EMAIL_FROM") ?? "Orders <onboarding@resend.dev>";
  if (!key) {
    console.log(`[email skipped: no RESEND_API_KEY] to=${to} subject=${subject}`);
    return false;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject, html }),
  });
  if (!res.ok) console.error("Resend error", res.status, await res.text());
  return res.ok;
}

export function sendReceipt(r: Receipt, appUrl: string) {
  if (!r.customerEmail) return Promise.resolve(false);
  const first = (r.customerName ?? "").split(" ")[0];
  return send(r.customerEmail, `${r.brandName}: order ${r.orderNumber} confirmed`,
    layout(r, "Thanks for your order", `${first ? first + ", w" : "W"}e've got your order and will have it ready for pickup.`,
      `${appUrl}/order/${r.publicToken}`));
}

export function sendReady(r: Receipt, appUrl: string) {
  if (!r.customerEmail) return Promise.resolve(false);
  return send(r.customerEmail, `${r.brandName}: order ${r.orderNumber} is ready for pickup`,
    layout(r, "Your order is ready", "Your order is packed and ready for pickup.", `${appUrl}/order/${r.publicToken}`));
}

// ---- end inlined ----

const url = Deno.env.get("SUPABASE_URL")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  // Validate the staff member's session token (works with legacy anon keys and new publishable keys).
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData } = await service.auth.getUser(token);
  const userId = userData?.user?.id;
  if (!userId) return json(req, { error: "Sign in again." }, 401);

  const { orderId } = await req.json().catch(() => ({}));
  if (!orderId) return json(req, { error: "Missing order." }, 400);

  const { data: order } = await service.from("orders")
    .select("id, tenant_id, status, customer_email, ready_notified_at").eq("id", orderId).maybeSingle();
  if (!order) return json(req, { error: "Order not found." }, 404);

  // Same check the database uses: is this user staff for the order's tenant?
  const [{ data: member }, { data: admin }] = await Promise.all([
    service.from("tenant_members").select("role").eq("tenant_id", order.tenant_id).eq("user_id", userId).maybeSingle(),
    service.from("platform_admins").select("user_id").eq("user_id", userId).maybeSingle(),
  ]);
  if (!member && !admin) return json(req, { error: "Not allowed." }, 403);

  if (order.status !== "ready") return json(req, { sent: false, reason: "not_ready" });
  if (order.ready_notified_at) return json(req, { sent: false, reason: "already_sent" });
  if (!order.customer_email) return json(req, { sent: false, reason: "no_email" });

  const { data: receipt } = await service.rpc("order_receipt", { p_order: order.id });
  const sent = await sendReady(receipt as Receipt, appUrl(req));
  if (sent) await service.from("orders").update({ ready_notified_at: new Date().toISOString() }).eq("id", order.id);
  return json(req, { sent });
});
