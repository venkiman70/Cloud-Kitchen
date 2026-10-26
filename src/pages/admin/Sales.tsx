import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import { fmtPickup, money } from "../../lib/format";
import { todayIn, zonedTime } from "../../lib/time";
import { Notice, Spinner } from "../../components/ui";
import { useAdmin } from "./AdminShell";

type Order = {
  id: string; order_number: string; status: string; payment_status: string; channel: string;
  customer_name: string | null; customer_phone: string | null; pickup_at: string; created_at: string;
  subtotal_cents: number; tax_cents: number; total_cents: number; platform_fee_cents: number;
  brand: { name: string } | null;
};

/** Owners and managers: orders placed on a day, with money. Kitchen staff never reach this page or its data. */
export default function Sales() {
  const { member, isManager } = useAdmin();
  const [date, setDate] = useState(todayIn(member.timezone));
  const q = useQuery({
    queryKey: ["sales", member.tenantId, date],
    enabled: isManager,
    queryFn: async () => {
      const from = zonedTime(date, "00:00", member.timezone).toISOString();
      const [y, m, d] = date.split("-").map(Number);
      const next = new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
      const to = zonedTime(next, "00:00", member.timezone).toISOString();
      const { data, error } = await supabase.from("orders")
        .select("id,order_number,status,payment_status,channel,customer_name,customer_phone,pickup_at,created_at,subtotal_cents,tax_cents,total_cents,platform_fee_cents,brand:brands(name)")
        .eq("tenant_id", member.tenantId).gte("created_at", from).lt("created_at", to).order("created_at", { ascending: false });
      if (error) throw error;
      return data as unknown as Order[];
    },
  });
  if (!isManager) return <main className="wrap py-10"><Notice tone="warn">Sales are visible to owners and managers only.</Notice></main>;

  const paid = (q.data ?? []).filter((o) => o.payment_status === "paid" || o.payment_status === "partially_refunded");
  const sum = (f: (o: Order) => number) => paid.reduce((n, o) => n + f(o), 0);
  const cur = member.currency;

  return (
    <main className="wrap py-6">
      <div className="flex flex-wrap items-end gap-3">
        <h1 className="flex-1 font-display text-3xl">Sales</h1>
        <label className="flex flex-col gap-1"><span className="label">Orders placed on</span>
          <input type="date" className="input" value={date} onChange={(e) => setDate(e.target.value)} /></label>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[["Paid orders", String(paid.length)], ["Food sales", money(sum((o) => o.subtotal_cents), cur)],
          ["Sales tax", money(sum((o) => o.tax_cents), cur)], ["Platform fee (4%)", money(sum((o) => o.platform_fee_cents), cur)]].map(([k, v]) => (
          <div key={k} className="rounded-2xl bg-sunk p-4"><div className="text-sm text-muted">{k}</div><div className="text-2xl font-bold tabular-nums">{v}</div></div>
        ))}
      </div>
      {q.isLoading && <Spinner />}
      <div className="card mt-6 overflow-x-auto">
        <table className="w-full min-w-[720px] text-left text-sm tabular-nums">
          <thead className="text-muted"><tr>{["Order", "Customer", "Pickup", "Status", "Payment", "Total"].map((h) => <th key={h} className="p-3">{h}</th>)}</tr></thead>
          <tbody>
            {(q.data ?? []).map((o) => (
              <tr key={o.id} className="border-t border-line">
                <td className="p-3 font-semibold">{o.order_number}<div className="font-normal text-muted">{o.brand?.name} · {o.channel}</div></td>
                <td className="p-3">{o.customer_name}<div className="text-muted">{o.customer_phone}</div></td>
                <td className="p-3">{fmtPickup(o.pickup_at, member.timezone)}</td>
                <td className="p-3">{o.status.replace("_", " ")}</td>
                <td className="p-3">{o.payment_status.replace("_", " ")}</td>
                <td className="p-3 text-right font-semibold">{money(o.total_cents, cur)}</td>
              </tr>
            ))}
            {q.data?.length === 0 && <tr><td colSpan={6} className="p-6 text-center text-muted">No orders placed on this day.</td></tr>}
          </tbody>
        </table>
      </div>
      <p className="mt-3 text-sm text-muted">Refunds: open the payment in your Stripe dashboard and refund it there. The order updates here automatically.</p>
    </main>
  );
}
