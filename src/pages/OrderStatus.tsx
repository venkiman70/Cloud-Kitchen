import { useEffect } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "../lib/supabase";
import { clearCart, useStore } from "../lib/store";
import { fmtPickup, money } from "../lib/format";
import { FullPage, Notice, Spinner } from "../components/ui";

type PublicOrder = {
  orderNumber: string; status: string; paymentStatus: string; customerName: string;
  pickupAt: string; timezone: string; currency: string; brandName: string; tenantName: string;
  address: string | null; pickupInstructions: string | null;
  subtotalCents: number; taxCents: number; totalCents: number;
  items: { name: string; variant: string | null; quantity: number; lineTotalCents: number }[];
};

const STEPS = [
  { key: "confirmed", label: "Confirmed" },
  { key: "preparing", label: "Preparing" },
  { key: "ready", label: "Ready for pickup" },
  { key: "completed", label: "Picked up" },
];

export default function OrderStatus() {
  const { token } = useParams();
  const [params] = useSearchParams();
  const store = useStore();
  const justPaid = params.get("paid") === "1" || params.get("placed") === "1";

  const q = useQuery({
    queryKey: ["order", token],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("order_status_public", { p_token: token });
      if (error) throw error;
      return data as PublicOrder | null;
    },
    refetchInterval: (query) => {
      const st = query.state.data?.status;
      return st === "completed" || st === "cancelled" || st === "refunded" ? false : st === "pending_payment" ? 3000 : 15000;
    },
  });

  // After a successful payment, empty that brand's cart
  useEffect(() => {
    if (justPaid) store.brands.forEach((b) => clearCart(store.tenant.slug, b.slug));
  }, [justPaid, store]);

  if (q.isLoading) return <Spinner label="Loading your order" />;
  if (!q.data) return <FullPage title="Order not found">Check the link in your receipt email, or call us.</FullPage>;
  const o = q.data;
  const stepIndex = STEPS.findIndex((x) => x.key === o.status);

  return (
    <main className="wrap max-w-xl py-8">
      <p className="text-sm text-muted">{o.brandName}</p>
      <h1 className="h-display text-3xl">Order {o.orderNumber}</h1>
      <p className="mt-1 text-muted">{o.customerName ? `${o.customerName}, ` : ""}pickup {fmtPickup(o.pickupAt, o.timezone)}</p>

      <div className="mt-5">
        {o.status === "pending_payment" && (justPaid
          ? <Notice>Confirming your payment with the bank. This page updates on its own.</Notice>
          : <Notice tone="warn">This order hasn't been paid yet.</Notice>)}
        {o.status === "cancelled" && <Notice tone="warn">This order was cancelled. If you were charged, the refund is on its way.</Notice>}
        {o.status === "refunded" && <Notice>This order was refunded. It can take 5–10 days to show on your card.</Notice>}
        {o.status === "ready" && <Notice tone="ok">Your order is ready. {o.pickupInstructions}</Notice>}
        {o.paymentStatus === "unpaid" && !["pending_payment", "cancelled", "refunded"].includes(o.status) && (
          <div className="mt-3"><Notice tone="warn">Please pay {money(o.totalCents, o.currency)} at the counter when you pick up.</Notice></div>
        )}
      </div>

      {stepIndex >= 0 && (
        <ol className="mt-6 grid grid-cols-4 gap-2" aria-label="Order progress">
          {STEPS.map((st, i) => (
            <li key={st.key} className="flex flex-col gap-2">
              <span className="h-2 rounded-full" style={{ background: i <= stepIndex ? "var(--accent)" : "rgb(var(--line))" }} />
              <span className={`text-xs sm:text-sm ${i === stepIndex ? "font-bold" : "text-muted"}`} aria-current={i === stepIndex ? "step" : undefined}>{st.label}</span>
            </li>
          ))}
        </ol>
      )}

      <section className="card mt-6 divide-y divide-line">
        {o.items.map((it, i) => (
          <div key={i} className="flex justify-between gap-3 p-3 tabular-nums">
            <span>{it.quantity} × {it.name}{it.variant && it.variant !== "Regular" ? <span className="text-muted"> ({it.variant})</span> : null}</span>
            <span>{money(it.lineTotalCents, o.currency)}</span>
          </div>
        ))}
        <div className="flex justify-between p-3 text-muted tabular-nums"><span>Sales tax</span><span>{money(o.taxCents, o.currency)}</span></div>
        <div className="flex justify-between p-3 font-bold tabular-nums"><span>{o.paymentStatus === "unpaid" && o.status !== "pending_payment" ? "Due at pickup" : "Total"}</span><span>{money(o.totalCents, o.currency)}</span></div>
      </section>

      {o.address && <p className="mt-6 text-sm"><span className="font-semibold">Pickup at</span> {o.address}</p>}
      {o.pickupInstructions && o.status !== "ready" && <p className="mt-1 text-sm text-muted">{o.pickupInstructions}</p>}

      <Link to="/" className="btn mt-8">Order something else</Link>
    </main>
  );
}
