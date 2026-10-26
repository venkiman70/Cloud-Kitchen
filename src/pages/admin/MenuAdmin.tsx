import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import { money } from "../../lib/format";
import type { Diet } from "../../lib/types";
import { DietMark, Notice, Spinner } from "../../components/ui";
import { useAdmin } from "./AdminShell";

type Row = {
  id: string; name: string; diet: Diet; is_available: boolean; is_sample: boolean; deleted_at: string | null;
  brand: { name: string; sort: number } | null; category: { name: string; sort: number } | null;
  variants: { id: string; label: string; price_cents: number; deleted_at: string | null }[];
};

/** Sold-out toggle for everyone; price edits for owners and managers. Full product editing comes next. */
export default function MenuAdmin() {
  const { member, isManager } = useAdmin();
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [msg, setMsg] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const q = useQuery({
    queryKey: ["menu-admin", member.tenantId],
    queryFn: async () => {
      const { data, error } = await supabase.from("menu_items")
        .select("id,name,diet,is_available,is_sample,deleted_at,brand:brands(name,sort),category:menu_categories(name,sort),variants:item_variants(id,label,price_cents,deleted_at)")
        .eq("tenant_id", member.tenantId).is("deleted_at", null);
      if (error) throw error;
      return (data as unknown as Row[]).sort((a, b) =>
        (a.brand?.sort ?? 0) - (b.brand?.sort ?? 0) || (a.category?.sort ?? 99) - (b.category?.sort ?? 99) || a.name.localeCompare(b.name));
    },
  });

  async function toggle(r: Row) {
    const { error } = await supabase.rpc("set_item_availability", { p_item: r.id, p_available: !r.is_available });
    setMsg(error ? { tone: "error", text: `Couldn't update ${r.name}.` } : { tone: "ok", text: r.is_available ? `${r.name} is sold out on the menu.` : `${r.name} is back on the menu.` });
    qc.invalidateQueries({ queryKey: ["menu-admin", member.tenantId] });
  }

  async function savePrice(r: Row, variantId: string, value: string) {
    const cents = Math.round(Number(value) * 100);
    if (!Number.isFinite(cents) || cents < 0) { setMsg({ tone: "error", text: "Enter a price like 12.99." }); return; }
    const { error } = await supabase.from("item_variants").update({ price_cents: cents }).eq("id", variantId);
    setMsg(error ? { tone: "error", text: `Couldn't save the price for ${r.name}.` } : { tone: "ok", text: `Saved ${r.name} at ${money(cents, member.currency)}.` });
    qc.invalidateQueries({ queryKey: ["menu-admin", member.tenantId] });
  }

  const rows = (q.data ?? []).filter((r) => !search || r.name.toLowerCase().includes(search.toLowerCase()));
  return (
    <main className="wrap py-6">
      <h1 className="font-display text-3xl">Menu</h1>
      <p className="mt-1 text-muted">Tap a switch to sell an item out. Customers see it within seconds.{isManager ? " Edit a price and press Enter to save." : ""}</p>
      <input className="input mt-4 max-w-sm" type="search" placeholder="Search products" aria-label="Search products" value={search} onChange={(e) => setSearch(e.target.value)} />
      {msg && <div className="mt-3"><Notice tone={msg.tone}>{msg.text}</Notice></div>}
      {q.isLoading && <Spinner />}
      <div className="card mt-4 divide-y divide-line">
        {rows.map((r) => (
          <div key={r.id} className="flex flex-wrap items-center gap-3 p-3">
            <DietMark diet={r.diet} />
            <div className="min-w-0 flex-1">
              <div className="font-semibold">{r.name} {r.is_sample && <span className="tag !bg-[#fff1d6] !text-[#7a4a00]">Sample</span>}</div>
              <div className="text-sm text-muted">{r.brand?.name} · {r.category?.name}</div>
            </div>
            <div className="flex flex-wrap gap-2">
              {r.variants.filter((v) => !v.deleted_at).map((v) => isManager ? (
                <label key={v.id} className="flex items-center gap-1 text-sm">
                  <span className="text-muted">{v.label}</span>
                  <span className="text-muted">$</span>
                  <input className="input min-h-[40px] w-24 tabular-nums" inputMode="decimal" defaultValue={(v.price_cents / 100).toFixed(2)}
                    aria-label={`Price for ${r.name} ${v.label}`}
                    onKeyDown={(e) => { if (e.key === "Enter") savePrice(r, v.id, (e.target as HTMLInputElement).value); }}
                    onBlur={(e) => { if (Math.round(Number(e.target.value) * 100) !== v.price_cents) savePrice(r, v.id, e.target.value); }} />
                </label>
              ) : (
                <span key={v.id} className="text-sm tabular-nums">{v.label} {money(v.price_cents, member.currency)}</span>
              ))}
            </div>
            <label className="flex min-w-[96px] cursor-pointer items-center justify-end gap-2 text-sm font-semibold">
              <input type="checkbox" className="h-6 w-6" style={{ accentColor: "rgb(var(--veg))" }} checked={r.is_available} onChange={() => toggle(r)} />
              {r.is_available ? "On menu" : "Sold out"}
            </label>
          </div>
        ))}
      </div>
    </main>
  );
}
