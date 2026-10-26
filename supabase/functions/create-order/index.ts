// create-order: validates and prices the cart in Postgres (create_order), then
// opens a Stripe Checkout Session for it. The browser never sends a trusted price.
//
// POST { tenant, brand, pickupAt, notes?, customer: {name, phone, email?, optInEmail?, optInSms?},
//        items: [{variantId, quantity}] }
// 200  { url, orderNumber, publicToken }
// 4xx  { error: <customer-friendly message>, code }

import Stripe from "npm:stripe@17.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.46.1";
import { appUrl, corsHeaders, json } from "../_shared/http.ts";

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

  // 2. Open a Stripe Checkout Session on the tenant's connected account (if any)
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
