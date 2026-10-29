// stripe-webhook: Stripe tells us a payment succeeded, expired or was refunded.
// Signature-checked, and safe to receive the same event more than once.
//
// Set up TWO endpoints in the Stripe dashboard pointing at this function:
//   1. "Your account" events      -> secret in STRIPE_WEBHOOK_SECRET
//   2. "Connected accounts" events -> secret in STRIPE_CONNECT_WEBHOOK_SECRET (needed once tenants use Connect)
// Events: checkout.session.completed, checkout.session.async_payment_succeeded,
//         checkout.session.expired, charge.refunded

import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.46.1";

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
const crypto = Stripe.createSubtleCryptoProvider();
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const secrets = [Deno.env.get("STRIPE_WEBHOOK_SECRET"), Deno.env.get("STRIPE_CONNECT_WEBHOOK_SECRET")].filter(Boolean) as string[];

async function verify(body: string, signature: string): Promise<Stripe.Event | null> {
  for (const secret of secrets) {
    try {
      return await stripe.webhooks.constructEventAsync(body, signature, secret, undefined, crypto);
    } catch {
      // try the next endpoint secret
    }
  }
  return null;
}

async function paid(session: Stripe.Checkout.Session) {
  if (session.payment_status !== "paid") return;
  const pi = typeof session.payment_intent === "string" ? session.payment_intent : session.payment_intent?.id ?? null;
  const { data, error } = await db.rpc("mark_order_paid", {
    p_session_id: session.id,
    p_payment_intent: pi,
    p_amount_cents: session.amount_total,
  });
  if (error) throw error;
  if (!data.alreadyPaid && data.customerEmail) {
    const site = (Deno.env.get("APP_URL") ?? "").replace(/\/$/, "");
    if (await sendReceipt(data as Receipt, site)) {
      await db.from("orders").update({ receipt_sent_at: new Date().toISOString() }).eq("id", data.orderId);
    }
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();
  if (!signature) return new Response("Missing signature", { status: 400 });

  const event = await verify(body, signature);
  if (!event) return new Response("Bad signature", { status: 400 });

  // Already handled? (Stripe retries; every handler is idempotent anyway.)
  const { data: seen } = await db.from("stripe_events").select("id").eq("id", event.id).maybeSingle();
  if (seen) return new Response(JSON.stringify({ duplicate: true }), { status: 200 });

  try {
    switch (event.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded":
        await paid(event.data.object as Stripe.Checkout.Session);
        break;
      case "checkout.session.expired":
        await db.rpc("expire_pending_order", { p_session_id: (event.data.object as Stripe.Checkout.Session).id });
        break;
      case "charge.refunded": {
        const charge = event.data.object as Stripe.Charge;
        const pi = typeof charge.payment_intent === "string" ? charge.payment_intent : charge.payment_intent?.id;
        if (pi) {
          const { error } = await db.rpc("mark_order_refunded", { p_payment_intent: pi, p_refunded_cents: charge.amount_refunded });
          if (error) throw error;
        }
        break;
      }
      default:
        break; // ignore everything else
    }
  } catch (e) {
    console.error(`Webhook ${event.type} ${event.id} failed`, e);
    return new Response("Handler error", { status: 500 }); // Stripe will retry
  }

  await db.from("stripe_events").insert({ id: event.id, type: event.type });
  return new Response(JSON.stringify({ received: true }), { status: 200 });
});
