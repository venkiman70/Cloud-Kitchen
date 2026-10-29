// create-order: validates and prices the cart in Postgres (create_order), then either
// opens a Stripe Checkout Session for it, or (pay at pickup) sends it straight to the
// kitchen as confirmed and unpaid. The browser never sends a trusted price.
//
// POST { tenant, brand, pickupAt, notes?, payAtPickup?, customer: {name, phone, email?, optInEmail?, optInSms?},
//        items: [{variantId, quantity}] }
// 200  { url, orderNumber, publicToken }            (pay now: redirect to url)
// 200  { payAtPickup: true, orderNumber, publicToken } (pay at pickup: no redirect)
// 4xx  { error: <customer-friendly message>, code }

import Stripe from "npm:stripe@17.7.0";
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
  paymentStatus?: string | null;
  payAtPickup?: boolean | null;
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
  const due = r.paymentStatus === "unpaid";
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
    <tr><td style="padding:6px 0"><b>${due ? "Total to pay at pickup" : "Total paid"}</b></td><td style="padding:6px 0;text-align:right"><b>${money(r.totalCents, r.currency)}</b></td></tr>
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
    layout(r, "Thanks for your order",
      `${first ? first + ", w" : "W"}e've got your order and will have it ready for pickup.` +
        (r.paymentStatus === "unpaid" ? " You'll pay when you pick it up." : ""),
      `${appUrl}/order/${r.publicToken}`));
}

export function sendReady(r: Receipt, appUrl: string) {
  if (!r.customerEmail) return Promise.resolve(false);
  return send(r.customerEmail, `${r.brandName}: order ${r.orderNumber} is ready for pickup`,
    layout(r, "Your order is ready", "Your order is packed and ready for pickup.", `${appUrl}/order/${r.publicToken}`));
}
// ---- end inlined ----

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", { httpClient: Stripe.createFetchHttpClient() });
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const MESSAGES: Record<string, (detail: string) => string> = {
  TENANT_NOT_FOUND: () => "This store isn't taking orders right now.",
  BRAND_NOT_FOUND: () => "This menu isn't available right now.",
  NAME_REQUIRED: () => "Enter your name.",
  BAD_PHONE: () => "Enter a 10-digit mobile number, for example 214 555 0101.",
  BAD_EMAIL: () => "Check your email address.",
  CART_EMPTY: () => "Your cart is empty.",
  CART_TOO_LARGE: () => "That's a lot of items. Split it into two orders or call us.",
  ITEM_NOT_FOUND: () => "Something in your cart is no longer on the menu. Refresh the page and try again.",
  BAD_QUANTITY: () => "Check the quantities in your cart.",
  ITEM_SOLD_OUT: (d) => `${d} just sold out. Remove it to continue.`,
  BAD_PICKUP_TIME: () => "Choose a pickup time.",
  PICKUP_TOO_SOON: () => "That pickup time is too soon. Choose a later time.",
  PICKUP_TOO_FAR: () => "Choose a pickup date within the next 45 days.",
  CLOSED_THAT_DAY: () => "We're closed that day. Choose another date.",
  OUTSIDE_PICKUP_HOURS: () => "That time is outside pickup hours. Choose another time.",
  COLLECTION_CLOSED: (d) => `Orders for ${d} have closed.`,
  PICKUP_DATE_NOT_ALLOWED: (d) => `${d} can only be picked up on the listed pickup dates.`,
  SLOT_FULL: () => "That pickup time is full. Choose another time.",
  LIMIT_REACHED: (d) => `We've reached the limit for ${d} on that day. Lower the quantity or pick another day.`,
  PAY_AT_PICKUP_OFF: () => "Pay at pickup isn't available right now. Choose Pay now to place your order.",
  PAY_AT_PICKUP_LIMIT: (d) => `Pay at pickup is for orders up to ${d}. Choose Pay now for this order.`,
};

function friendly(message: string): { code: string; error: string } {
  const [code, ...rest] = message.split(":");
  const make = MESSAGES[code];
  return make
    ? { code, error: make(rest.join(":").trim()) }
    : { code: "UNKNOWN", error: "We couldn't place your order. Try again, or call us to order." };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(req, { error: "Invalid request." }, 400);
  }
  if (typeof body.tenant !== "string" || typeof body.brand !== "string" || !Array.isArray(body.items)) {
    return json(req, { error: "Invalid request." }, 400);
  }

  // 1. Price and save the order in Postgres
  const { data: order, error } = await db.rpc("create_order", {
    p: {
      tenant: body.tenant,
      brand: body.brand,
      channel: "web",
      pickupAt: body.pickupAt,
      notes: typeof body.notes === "string" ? body.notes.slice(0, 500) : null,
      customer: body.customer,
      items: (body.items as { variantId: string; quantity: number }[]).map((i) => ({
        variantId: String(i.variantId),
        quantity: Math.trunc(Number(i.quantity)),
      })),
    },
  });
  if (error || !order) {
    const f = friendly(error?.message ?? "");
    if (f.code === "UNKNOWN") console.error("create_order failed", error);
    return json(req, f, 422);
  }

  // 2a. Pay at pickup: confirm it for the kitchen, email the receipt, no Stripe
  if (body.payAtPickup === true) {
    const { data: receipt, error: payError } = await db.rpc("confirm_pay_at_pickup", { p_order: order.orderId });
    if (payError || !receipt) {
      await db.from("orders").update({ status: "cancelled" }).eq("id", order.orderId).eq("status", "pending_payment");
      const f = friendly(payError?.message ?? "");
      if (f.code === "UNKNOWN") console.error("confirm_pay_at_pickup failed", payError);
      return json(req, f, 422);
    }
    if (order.customerEmail) {
      const site = appUrl(req);
      if (await sendReceipt(receipt as Receipt, site)) {
        await db.from("orders").update({ receipt_sent_at: new Date().toISOString() }).eq("id", order.orderId);
      }
    }
    return json(req, { payAtPickup: true, orderNumber: order.orderNumber, publicToken: order.publicToken });
  }

  // 2b. Pay now: open a Stripe Checkout Session on the tenant's connected account (if any)
  const site = appUrl(req);
  const currency = order.currency ?? "usd";
  const lineItems: Stripe.Checkout.SessionCreateParams.LineItem[] = order.lines.map(
    (l: { name: string; unitAmount: number; quantity: number }) => ({
      quantity: l.quantity,
      price_data: { currency, unit_amount: l.unitAmount, product_data: { name: l.name } },
    }),
  );
  if (order.taxCents > 0) {
    lineItems.push({ quantity: 1, price_data: { currency, unit_amount: order.taxCents, product_data: { name: "Sales tax" } } });
  }

  const connected = order.stripeAccountId as string | null;
  const metadata = { order_id: order.orderId, order_number: order.orderNumber };
  try {
    const session = await stripe.checkout.sessions.create(
      {
        mode: "payment",
        // Pickup orders: cards (Apple Pay and Google Pay ride on "card") and Link only.
        // Bank debits (ACH) take days to clear, so they're kept for catering.
        payment_method_types: ["card", "link"],
        line_items: lineItems,
        customer_email: order.customerEmail ?? undefined,
        client_reference_id: order.orderId,
        metadata,
        payment_intent_data: {
          metadata,
          description: `${order.brandName} order ${order.orderNumber}`,
          ...(connected && order.platformFeeCents > 0 ? { application_fee_amount: order.platformFeeCents } : {}),
        },
        success_url: `${site}/order/${order.publicToken}?paid=1`,
        cancel_url: `${site}/${order.brandSlug}/checkout?cancelled=${encodeURIComponent(order.orderNumber)}`,
        expires_at: Math.floor(Date.now() / 1000) + 31 * 60,
      },
      { idempotencyKey: `checkout-${order.orderId}`, ...(connected ? { stripeAccount: connected } : {}) },
    );

    const { error: saveError } = await db.from("orders")
      .update({ stripe_checkout_session_id: session.id })
      .eq("id", order.orderId);
    if (saveError) throw saveError;

    return json(req, { url: session.url, orderNumber: order.orderNumber, publicToken: order.publicToken });
  } catch (e) {
    console.error("Stripe checkout failed", e);
    await db.from("orders").update({ status: "cancelled" }).eq("id", order.orderId).eq("status", "pending_payment");
    return json(req, { code: "PAYMENT_UNAVAILABLE", error: "Payments aren't working right now. Try again in a minute, or call us to order." }, 502);
  }
});
