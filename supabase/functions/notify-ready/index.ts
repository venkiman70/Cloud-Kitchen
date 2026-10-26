// notify-ready: the kitchen board calls this after marking an order Ready.
// Checks the caller is staff for that order's tenant, then emails the customer once.
//
// POST { orderId }   (Authorization: Bearer <staff user's access token>)

import { createClient } from "npm:@supabase/supabase-js@2.46.1";
import { appUrl, corsHeaders, json } from "../_shared/http.ts";
import { sendReady, type Receipt } from "../_shared/email.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await asUser.auth.getUser();
  if (!userData?.user) return json(req, { error: "Sign in again." }, 401);

  const { orderId } = await req.json().catch(() => ({}));
  if (!orderId) return json(req, { error: "Missing order." }, 400);

  const { data: order } = await service.from("orders")
    .select("id, tenant_id, status, customer_email, ready_notified_at").eq("id", orderId).maybeSingle();
  if (!order) return json(req, { error: "Order not found." }, 404);

  // Same check the database uses: is this user staff for the order's tenant?
  const { data: isStaff } = await asUser.rpc("is_staff", { t: order.tenant_id });
  if (!isStaff) return json(req, { error: "Not allowed." }, 403);

  if (order.status !== "ready") return json(req, { sent: false, reason: "not_ready" });
  if (order.ready_notified_at) return json(req, { sent: false, reason: "already_sent" });
  if (!order.customer_email) return json(req, { sent: false, reason: "no_email" });

  const { data: receipt } = await service.rpc("order_receipt", { p_order: order.id });
  const sent = await sendReady(receipt as Receipt, appUrl(req));
  if (sent) await service.from("orders").update({ ready_notified_at: new Date().toISOString() }).eq("id", order.id);
  return json(req, { sent });
});
