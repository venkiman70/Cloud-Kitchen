import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import { dateLabel, todayIn } from "../../lib/time";
import { Spinner } from "../../components/ui";
import { useAdmin } from "./AdminShell";

type Row = { name: string; variant: string | null; brand: string; quantity: number; orders: number };

/** What to make for a pickup date: paid orders only, summed per item and pack size. */
export default function Prep() {
  const { member } = useAdmin();
  const [date, setDate] = useState(todayIn(member.timezone));
  const q = useQuery({
    queryKey: ["prep", member.tenantId, date],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("prep_totals", { p_tenant: member.tenantId, p_date: date });
      if (error) throw error;
      return data as Row[];
    },
    refetchInterval: 30_000,
  });
  const byBrand = (q.data ?? []).reduce<Record<string, Row[]>>((g, r) => ((g[r.brand] ??= []).push(r), g), {});

  return (
    <main className="wrap py-6">
      <div className="flex flex-wrap items-end gap-3">
        <h1 className="flex-1 font-display text-3xl">Prep list</h1>
        <label className="flex flex-col gap-1">
          <span className="label">Pickup date</span>
          <input type="date" className="input" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
      </div>
      <p className="mt-1 text-muted">{dateLabel(date, member.timezone)} · paid orders only</p>
      {q.isLoading && <Spinner />}
      {q.data?.length === 0 && <p className="py-10 text-center text-muted">No paid orders for this date yet.</p>}
      {Object.entries(byBrand).map(([brand, rows]) => (
        <section key={brand} className="mt-6">
          <h2 className="mb-2 font-display text-xl">{brand}</h2>
          <div className="card overflow-x-auto">
            <table className="w-full text-left tabular-nums">
              <thead className="text-sm text-muted"><tr><th className="p-3">Item</th><th className="p-3">Pack</th><th className="p-3 text-right">Quantity</th><th className="p-3 text-right">Orders</th></tr></thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i} className="border-t border-line">
                    <td className="p-3 font-semibold">{r.name}</td><td className="p-3">{r.variant}</td>
                    <td className="p-3 text-right text-xl font-bold">{r.quantity}</td><td className="p-3 text-right text-muted">{r.orders}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ))}
    </main>
  );
}
