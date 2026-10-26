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
import { sendReceipt, type Receipt } from "../_shared/email.ts";

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
