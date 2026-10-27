import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "../lib/supabase";
import { useBrand, useCart, useStore } from "../lib/store";
import { money } from "../lib/format";
import { dateLabel } from "../lib/time";
import type { MenuItem } from "../lib/types";
import { DietMark, FullPage, Spinner, SPICE } from "../components/ui";
import { BrandMark } from "../components/BrandMark";

const MENU_SELECT =
  "id,name,description,diet,protein,spice,allergens,is_vegan,is_jain,image_url,is_available,is_catering_only,is_sample,sort,collection_id," +
  "category:menu_categories(id,name,sort),variants:item_variants(id,label,pack_qty,pack_unit,price_cents,sort,deleted_at)";

export function useMenu(brandId: string | undefined) {
  const qc = useQueryClient();
  const q = useQuery({
    queryKey: ["menu", brandId],
    enabled: Boolean(brandId),
    queryFn: async () => {
      const { data, error } = await supabase.from("menu_items").select(MENU_SELECT)
        .eq("brand_id", brandId!).is("deleted_at", null).eq("is_catering_only", false);
      if (error) throw error;
      return (data as unknown as MenuItem[])
        .map((i) => ({ ...i, variants: i.variants.filter((v) => !v.deleted_at).sort((a, b) => a.sort - b.sort) }))
        .filter((i) => i.variants.length > 0);
    },
  });
  // Sold-out changes show up live
  useEffect(() => {
    if (!brandId) return;
    const ch = supabase.channel(`menu-${brandId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "menu_items", filter: `brand_id=eq.${brandId}` },
        () => qc.invalidateQueries({ queryKey: ["menu", brandId] }))
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [brandId, qc]);
  return q;
}

export default function Menu() {
  const { brandSlug } = useParams();
  const store = useStore();
  const brand = useBrand(brandSlug);
  const menu = useMenu(brand?.id);
  const cart = useCart(store.tenant.slug, brandSlug ?? "");
  const nav = useNavigate();
  const [vegOnly, setVegOnly] = useState(false);
  const [search, setSearch] = useState("");
  const [cat, setCat] = useState("All");
  const [added, setAdded] = useState<string | null>(null);

  const collections = store.collections.filter((c) => c.brandId === brand?.id);
  const items = menu.data ?? [];
  const cats = useMemo(() => {
    const m = new Map<string, number>();
    items.forEach((i) => m.set(i.category?.name ?? "Other", i.category?.sort ?? 99));
    return [...m.entries()].sort((a, b) => a[1] - b[1]).map(([n]) => n);
  }, [items]);
  const shown = items
    .filter((i) => (!vegOnly || i.diet === "veg") && (cat === "All" || (i.category?.name ?? "Other") === cat))
    .filter((i) => !search || `${i.name} ${i.description ?? ""}`.toLowerCase().includes(search.toLowerCase()))
    .sort((a, b) => (a.category?.sort ?? 99) - (b.category?.sort ?? 99) || a.sort - b.sort);
  const groups = shown.reduce<Record<string, MenuItem[]>>((g, i) => ((g[i.category?.name ?? "Other"] ??= []).push(i), g), {});

  useEffect(() => { if (added) { const t = setTimeout(() => setAdded(null), 1600); return () => clearTimeout(t); } }, [added]);

  if (!brand) return <FullPage title="Menu not found"><Link className="underline" to="/">See all menus</Link></FullPage>;

  return (
    <div className="pb-28">
      <header className="sticky top-0 z-10 border-b border-line bg-surface/95 backdrop-blur" style={{ paddingTop: "env(safe-area-inset-top)" }}>
        <div className="wrap flex items-center gap-3 py-2">
          {store.brands.length > 1 && <Link to="/" className="btn min-h-[40px] px-3 text-sm" aria-label="All menus">←</Link>}
          <div className="min-w-0 flex-1">
            <BrandMark brand={brand} className="h-12 w-auto max-w-full sm:h-14" />
          </div>
        </div>
        <div className="toran opacity-90" aria-hidden="true" />
      </header>

      <main className="wrap pt-4">
        {collections.map((c) => (
          <div key={c.id} className="mb-4 rounded-2xl border-2 border-dashed px-4 py-3" style={{ borderColor: "rgb(var(--marigold) / .7)", background: "rgb(var(--marigold) / .12)" }}>
            <div className="h-display text-2xl" style={{ color: "var(--accent)" }}>{c.name}</div>
            <div className="text-sm text-muted">
              {c.pickupDates?.length ? <>Pickup on {c.pickupDates.map((d) => dateLabel(d, store.settings.timezone)).join(", ")}. </> : null}
              {c.orderCutoffAt && <>Order by {new Intl.DateTimeFormat("en-US", { timeZone: store.settings.timezone, weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(c.orderCutoffAt))}.</>}
            </div>
          </div>
        ))}

        <div className="flex flex-wrap items-center gap-3">
          <input className="input min-w-0 flex-1 basis-56" type="search" placeholder="Search the menu" aria-label="Search the menu"
            value={search} onChange={(e) => setSearch(e.target.value)} />
          <label className="flex cursor-pointer select-none items-center gap-2 text-sm font-semibold">
            <input type="checkbox" className="h-5 w-5 accent-[rgb(var(--veg))]" checked={vegOnly} onChange={(e) => setVegOnly(e.target.checked)} />
            Veg only
          </label>
        </div>

        <div className="-mx-4 mt-3 flex gap-2 overflow-x-auto px-4 pb-1" role="group" aria-label="Categories">
          {["All", ...cats].map((c) => (
            <button key={c} className="chip" aria-pressed={c === cat} onClick={() => setCat(c)}>{c}</button>
          ))}
        </div>

        {menu.isLoading && <Spinner label="Loading the menu" />}
        {menu.isError && <p className="py-10 text-center text-muted">The menu didn't load. Check your connection and refresh.</p>}
        {!menu.isLoading && shown.length === 0 && <p className="py-10 text-center text-muted">Nothing matches. Clear the filters to see the full menu.</p>}

        {Object.entries(groups).map(([name, list]) => (
          <section key={name} className="mt-6">
            <h2 className="h-display mb-3 flex items-center gap-3 text-2xl" style={{ color: "var(--accent)" }}>
              {name}<span className="h-px flex-1" style={{ background: "linear-gradient(90deg, rgb(var(--marigold) / .7), transparent)" }} />
            </h2>
            <div className="grid gap-3 sm:grid-cols-2">
              {list.map((i) => (
                <article key={i.id} className={`card flex gap-3 p-4 shadow-sm transition hover:shadow-md ${i.is_available ? "" : "opacity-60"}`}>
                  <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                    <h3 className="flex items-start gap-2 font-bold"><DietMark diet={i.diet} /><span>{i.name}</span></h3>
                    {i.description && <p className="text-sm text-muted">{i.description}</p>}
                    <div className="flex flex-wrap gap-1">
                      {!i.is_available && <span className="tag !text-nonveg">Sold out today</span>}
                      {i.spice > 0 && <span className="tag">{SPICE[i.spice]}</span>}
                      {i.allergens.map((a) => <span key={a} className="tag">{a}</span>)}
                      {i.is_vegan && <span className="tag">Vegan</span>}
                      {i.is_jain && <span className="tag">Jain</span>}
                    </div>
                    <div className="mt-1 flex flex-wrap gap-2">
                      {i.variants.map((v) => (
                        <button key={v.id} disabled={!i.is_available}
                          className="flex min-h-[40px] items-center gap-2 rounded-full border-2 px-3.5 text-sm font-bold tabular-nums transition hover:bg-sunk disabled:cursor-not-allowed" style={{ borderColor: "var(--accent)" }}
                          onClick={() => {
                            cart.add({ variantId: v.id, itemId: i.id, name: i.name, label: v.label, priceCents: v.price_cents, diet: i.diet, collectionId: i.collection_id });
                            setAdded(`${i.name}${i.variants.length > 1 ? ` (${v.label})` : ""}`);
                          }}>
                          <span>{money(v.price_cents, store.settings.currency)}</span>
                          {(i.variants.length > 1 || v.label !== "Regular") && <span className="font-normal text-muted">{v.label}</span>}
                          <span aria-hidden="true" style={{ color: "var(--accent)" }}>+</span>
                        </button>
                      ))}
                    </div>
                  </div>
                  {i.image_url && <img src={i.image_url} alt="" className="h-24 w-24 flex-none rounded-xl object-cover" loading="lazy" />}
                </article>
              ))}
            </div>
          </section>
        ))}
      </main>

      {added && (
        <div role="status" className="fixed left-1/2 z-20 -translate-x-1/2 rounded-full bg-fg px-4 py-2 text-sm font-semibold text-bg"
          style={{ bottom: "calc(96px + env(safe-area-inset-bottom))" }}>Added {added}</div>
      )}

      {cart.count > 0 && (
        <div className="fixed inset-x-0 bottom-0 z-10 border-t border-line bg-surface"
          style={{ paddingBottom: "max(12px, env(safe-area-inset-bottom))" }}>
          <div className="wrap pt-3">
            <button className="btn-primary w-full text-lg" onClick={() => nav(`/${brand.slug}/checkout`)}>
              View cart · {cart.count} {cart.count === 1 ? "item" : "items"} · {money(cart.subtotal, store.settings.currency)}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
