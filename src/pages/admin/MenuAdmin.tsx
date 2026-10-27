import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFieldArray, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { supabase } from "../../lib/supabase";
import { money } from "../../lib/format";
import { MAX_PHOTO_BYTES, resizePhoto } from "../../lib/image";
import type { Diet } from "../../lib/types";
import { DietMark, Notice, Spinner } from "../../components/ui";
import { ConfirmDialog, Sheet } from "../../components/Sheet";
import { useAdmin } from "./AdminShell";

type VariantRow = { id: string; label: string; price_cents: number; sort: number; deleted_at: string | null };
type Row = {
  id: string; name: string; description: string | null; diet: Diet; protein: string | null;
  is_available: boolean; is_sample: boolean; deleted_at: string | null; image_url: string | null;
  brand_id: string; category_id: string | null;
  brand: { name: string; sort: number } | null; category: { name: string; sort: number } | null;
  variants: VariantRow[];
};
type Category = { id: string; name: string; sort: number; brand_id: string; brand: { name: string; sort: number } | null };

const DIETS: { value: Diet; label: string }[] = [
  { value: "veg", label: "Veg" }, { value: "egg", label: "Egg" }, { value: "non_veg", label: "Non-veg" },
];

const priceText = z.string().trim()
  .regex(/^\d+(\.\d{1,2})?$/, "Enter a price like 12.99")
  .refine((v) => Number(v) > 0, "Price must be more than $0");

const schema = z.object({
  name: z.string().trim().min(1, "Enter a name").max(120, "Keep the name under 120 characters"),
  categoryId: z.string().min(1, "Pick a category"),
  prices: z.array(z.object({ id: z.string().optional(), label: z.string(), price: priceText })).min(1),
  description: z.string().max(1000, "Keep the description under 1,000 characters"),
  diet: z.enum(["veg", "egg", "non_veg"]),
});
type FormValues = z.infer<typeof schema>;

const toCents = (v: string) => Math.round(Number(v) * 100);
const liveVariants = (r: Row) => r.variants.filter((v) => !v.deleted_at).sort((a, b) => a.sort - b.sort);

/** Owners and managers: add, edit, photo, sell out, remove and restore dishes. */
export default function MenuAdmin() {
  const { member } = useAdmin();
  const qc = useQueryClient();
  const [search, setSearch] = useState("");
  const [showRemoved, setShowRemoved] = useState(false);
  const [msg, setMsg] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const [editing, setEditing] = useState<Row | "new" | null>(null);
  const [removing, setRemoving] = useState<Row | null>(null);

  const items = useQuery({
    queryKey: ["menu-admin", member.tenantId],
    queryFn: async () => {
      const { data, error } = await supabase.from("menu_items")
        .select("id,name,description,diet,protein,is_available,is_sample,deleted_at,image_url,brand_id,category_id,brand:brands(name,sort),category:menu_categories(name,sort),variants:item_variants(id,label,price_cents,sort,deleted_at)")
        .eq("tenant_id", member.tenantId);
      if (error) throw error;
      return (data as unknown as Row[]).sort((a, b) =>
        (a.brand?.sort ?? 0) - (b.brand?.sort ?? 0) || (a.category?.sort ?? 99) - (b.category?.sort ?? 99) || a.name.localeCompare(b.name));
    },
  });
  const categories = useQuery({
    queryKey: ["menu-admin-categories", member.tenantId],
    queryFn: async () => {
      const { data, error } = await supabase.from("menu_categories").select("id,name,sort,brand_id,brand:brands(name,sort)").eq("tenant_id", member.tenantId);
      if (error) throw error;
      return (data as unknown as Category[]).sort((a, b) => (a.brand?.sort ?? 0) - (b.brand?.sort ?? 0) || a.sort - b.sort);
    },
  });

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["menu-admin", member.tenantId] });
    qc.invalidateQueries({ queryKey: ["menu"] }); // storefront in this browser
  };

  async function toggle(r: Row) {
    const { error } = await supabase.rpc("set_item_availability", { p_item: r.id, p_available: !r.is_available });
    setMsg(error ? { tone: "error", text: `Couldn't update ${r.name}.` } : { tone: "ok", text: r.is_available ? `${r.name} is sold out on the menu.` : `${r.name} is back on the menu.` });
    refresh();
  }

  const removal = useMutation({
    mutationFn: async ({ row, remove }: { row: Row; remove: boolean }) => {
      const { error } = await supabase.from("menu_items").update({ deleted_at: remove ? new Date().toISOString() : null }).eq("id", row.id);
      if (error) throw error;
    },
    onSuccess: (_d, { row, remove }) => {
      setMsg({ tone: "ok", text: remove ? `${row.name} removed. Turn on "Show removed" to bring it back.` : `${row.name} is back on the menu.` });
      setRemoving(null);
      refresh();
    },
    onError: (_e, { row }) => setMsg({ tone: "error", text: `Couldn't change ${row.name}. Try again.` }),
  });

  const visible = (items.data ?? []).filter((r) => (showRemoved ? r.deleted_at : !r.deleted_at)
    && (!search || r.name.toLowerCase().includes(search.toLowerCase())));
  const groups = useMemo(() => {
    const map = new Map<string, { title: string; rows: Row[] }>();
    for (const r of visible) {
      const key = `${r.brand_id}:${r.category_id ?? "none"}`;
      const title = `${r.brand?.name ?? ""} · ${r.category?.name ?? "No category"}`;
      if (!map.has(key)) map.set(key, { title, rows: [] });
      map.get(key)!.rows.push(r);
    }
    return [...map.values()];
  }, [visible]);
  const removedCount = (items.data ?? []).filter((r) => r.deleted_at).length;

  return (
    <main className="wrap py-6">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="h-display flex-1 text-3xl">Menu</h1>
        <button className="btn-primary min-h-[48px] px-6" onClick={() => { setMsg(null); setEditing("new"); }}>+ Add item</button>
      </div>
      <p className="mt-1 text-muted">Tap the switch to sell a dish out. Customers see changes when they refresh, or live if their menu is open.</p>
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <input className="input min-w-0 flex-1 basis-56" type="search" placeholder="Search dishes" aria-label="Search dishes" value={search} onChange={(e) => setSearch(e.target.value)} />
        <button type="button" className="chip min-h-[44px]" aria-pressed={showRemoved} onClick={() => setShowRemoved((s) => !s)}>
          Show removed{removedCount ? ` (${removedCount})` : ""}
        </button>
      </div>
      {msg && <div className="mt-3"><Notice tone={msg.tone}>{msg.text}</Notice></div>}
      {items.isLoading && <Spinner />}
      {items.isError && <div className="mt-4"><Notice tone="error">Couldn't load the menu. Refresh to try again.</Notice></div>}
      {!items.isLoading && groups.length === 0 && (
        <p className="mt-8 text-center text-muted">{showRemoved ? "Nothing has been removed." : "No dishes match."}</p>
      )}

      {groups.map((g) => (
        <section key={g.title} className="mt-6">
          <h2 className="eyebrow mb-2">{g.title}</h2>
          <div className="card divide-y divide-line">
            {g.rows.map((r) => (
              <div key={r.id} className="flex flex-wrap items-center gap-3 p-3">
                {r.image_url
                  ? <img src={r.image_url} alt="" className="h-14 w-14 flex-none rounded-xl object-cover" loading="lazy" />
                  : <span className="grid h-14 w-14 flex-none place-items-center rounded-xl bg-sunk text-[10px] font-semibold uppercase text-muted">No photo</span>}
                <div className="min-w-0 flex-1 basis-40">
                  <div className="flex items-start gap-1.5 font-semibold">
                    <DietMark diet={r.diet} />
                    <span className="min-w-0">{r.name}{r.is_sample && <span className="tag ml-1.5 !bg-[#fff1d6] !text-[#7a4a00]">Sample</span>}</span>
                  </div>
                  <div className="mt-0.5 text-sm tabular-nums text-muted">
                    {liveVariants(r).map((v) => `${liveVariants(r).length > 1 || v.label !== "Regular" ? `${v.label} ` : ""}${money(v.price_cents, member.currency)}`).join(" · ") || "No price"}
                  </div>
                </div>
                <div className="flex w-full items-center justify-end gap-2 sm:w-auto">
                  {showRemoved ? (
                    <button className="btn-primary min-h-[48px] px-6" disabled={removal.isPending} onClick={() => removal.mutate({ row: r, remove: false })}>Restore</button>
                  ) : (
                    <>
                      <button type="button" role="switch" aria-checked={!r.is_available} aria-label={`Sold out: ${r.name}`} onClick={() => toggle(r)}
                        className="flex min-h-[48px] items-center gap-2 rounded-full px-2 text-sm font-semibold">
                        <span className={`relative h-7 w-12 rounded-full transition ${r.is_available ? "bg-sunk" : "bg-[rgb(var(--nonveg))]"}`}>
                          <span className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-all ${r.is_available ? "left-0.5" : "left-[22px]"}`} />
                        </span>
                        <span className="w-16 text-left">{r.is_available ? "On menu" : "Sold out"}</span>
                      </button>
                      <button className="btn min-h-[48px]" onClick={() => { setMsg(null); setEditing(r); }}>Edit</button>
                      <button className="btn min-h-[48px] text-[rgb(var(--nonveg))]" onClick={() => setRemoving(r)}>Remove</button>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        </section>
      ))}

      <ItemForm
        key={editing === "new" ? "new" : editing?.id ?? "closed"}
        open={editing !== null}
        item={editing === "new" ? null : editing}
        categories={categories.data ?? []}
        tenantId={member.tenantId}
        onClose={() => setEditing(null)}
        onSaved={(text) => { setEditing(null); setMsg({ tone: "ok", text }); refresh(); }}
      />
      <ConfirmDialog
        open={removing !== null}
        title="Remove this dish?"
        body={<>{removing?.name} will disappear from the online menu. Past orders keep it. You can restore it from "Show removed".</>}
        confirmLabel="Remove"
        busy={removal.isPending}
        onConfirm={() => removing && removal.mutate({ row: removing, remove: true })}
        onClose={() => setRemoving(null)}
      />
    </main>
  );
}

function ItemForm({ open, item, categories, tenantId, onClose, onSaved }: {
  open: boolean; item: Row | null; categories: Category[]; tenantId: string; onClose: () => void; onSaved: (msg: string) => void;
}) {
  const variants = item ? liveVariants(item) : [];
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: item?.name ?? "",
      categoryId: item?.category_id ?? "",
      prices: variants.length
        ? variants.map((v) => ({ id: v.id, label: v.label, price: (v.price_cents / 100).toFixed(2) }))
        : [{ label: "Regular", price: "" }],
      description: item?.description ?? "",
      diet: item?.diet ?? "veg",
    },
  });
  const prices = useFieldArray({ control: form.control, name: "prices" });
  const { errors } = form.formState;

  // Photo: null = unchanged; a new resized blob; or "remove".
  const [photo, setPhoto] = useState<{ blob: Blob; type: string; ext: string } | "remove" | null>(null);
  const [preview, setPreview] = useState<string | null>(item?.image_url ?? null);
  const [photoError, setPhotoError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [busyPhoto, setBusyPhoto] = useState(false);
  useEffect(() => () => { if (preview?.startsWith("blob:")) URL.revokeObjectURL(preview); }, [preview]);

  async function pickPhoto(file: File | undefined) {
    setPhotoError(null);
    if (!file) return;
    if (!file.type.startsWith("image/")) { setPhotoError("Choose a photo (JPG, PNG or WebP)."); return; }
    if (file.size > MAX_PHOTO_BYTES) { setPhotoError("That photo is over 5 MB. Choose a smaller one."); return; }
    setBusyPhoto(true);
    try {
      const out = await resizePhoto(file, 1200);
      setPhoto(out);
      setPreview(URL.createObjectURL(out.blob));
    } catch {
      setPhotoError("Couldn't read that photo. Try a JPG or PNG.");
    } finally {
      setBusyPhoto(false);
    }
  }

  const save = useMutation({
    mutationFn: async (v: FormValues) => {
      const id = item?.id ?? crypto.randomUUID();
      const cat = categories.find((c) => c.id === v.categoryId);
      if (!cat) throw new Error("Pick a category");

      let image_url: string | null | undefined; // undefined = leave as is
      if (photo && photo !== "remove") {
        const path = `tenant/${tenantId}/menu/${id}.${photo.ext}`;
        const up = await supabase.storage.from("menu").upload(path, photo.blob, { upsert: true, contentType: photo.type, cacheControl: "31536000" });
        if (up.error) throw new Error("Couldn't upload the photo. Check you're signed in as owner or manager.");
        image_url = `${supabase.storage.from("menu").getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
      } else if (photo === "remove") {
        image_url = null;
        await supabase.storage.from("menu").remove([`tenant/${tenantId}/menu/${id}.webp`, `tenant/${tenantId}/menu/${id}.jpg`]);
      }

      const fields = {
        name: v.name.trim(),
        description: v.description.trim() || null,
        diet: v.diet,
        category_id: cat.id,
        brand_id: cat.brand_id,
        ...(v.diet === "veg" ? { protein: null } : {}),
        ...(image_url !== undefined ? { image_url } : {}),
      };

      if (!item) {
        const ins = await supabase.from("menu_items").insert({ id, tenant_id: tenantId, ...fields });
        if (ins.error) throw new Error("Couldn't add the dish.");
        const vi = await supabase.from("item_variants").insert({ tenant_id: tenantId, item_id: id, label: "Regular", price_cents: toCents(v.prices[0].price), sort: 0 });
        if (vi.error) throw new Error("Dish added, but the price didn't save. Edit it to set the price.");
        return `${fields.name} added at $${Number(v.prices[0].price).toFixed(2)}.`;
      }

      // Prices first, then the item row, so the storefront's live update sees the new price.
      for (const p of v.prices) {
        const old = variants.find((x) => x.id === p.id);
        if (p.id && old && old.price_cents !== toCents(p.price)) {
          const { error } = await supabase.from("item_variants").update({ price_cents: toCents(p.price) }).eq("id", p.id);
          if (error) throw new Error("Couldn't save the price.");
        }
      }
      const upd = await supabase.from("menu_items").update(fields).eq("id", id);
      if (upd.error) throw new Error("Couldn't save the dish.");
      return `${fields.name} saved.`;
    },
    onSuccess: onSaved,
    onError: (e) => setSaveError(e instanceof Error ? e.message : "Couldn't save. Try again."),
  });

  const brands = useMemo(() => {
    const m = new Map<string, { name: string; cats: Category[] }>();
    for (const c of categories) {
      if (!m.has(c.brand_id)) m.set(c.brand_id, { name: c.brand?.name ?? "Menu", cats: [] });
      m.get(c.brand_id)!.cats.push(c);
    }
    return [...m.values()];
  }, [categories]);

  const busy = save.isPending || busyPhoto;
  return (
    <Sheet open={open} onClose={() => !busy && onClose()} title={item ? "Edit dish" : "Add a dish"}
      footer={
        <div className="flex gap-2">
          <button type="button" className="btn flex-1" onClick={onClose} disabled={busy}>Cancel</button>
          <button type="submit" form="item-form" className="btn-primary flex-1" disabled={busy}>
            {save.isPending ? "Saving…" : item ? "Save" : "Add dish"}
          </button>
        </div>
      }>
      <form id="item-form" noValidate className="flex flex-col gap-4"
        onSubmit={form.handleSubmit((v) => { setSaveError(null); save.mutate(v); })}>
        <div>
          <label className="label" htmlFor="f-name">Name</label>
          <input id="f-name" className="input mt-1" autoComplete="off" {...form.register("name")} aria-invalid={!!errors.name} />
          {errors.name && <p className="mt-1 text-sm text-[rgb(var(--nonveg))]">{errors.name.message}</p>}
        </div>

        <div>
          <label className="label" htmlFor="f-cat">Category</label>
          <select id="f-cat" className="input mt-1" {...form.register("categoryId")} aria-invalid={!!errors.categoryId}>
            <option value="">Choose…</option>
            {brands.map((b) => (
              <optgroup key={b.name} label={b.name}>
                {b.cats.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </optgroup>
            ))}
          </select>
          {errors.categoryId && <p className="mt-1 text-sm text-[rgb(var(--nonveg))]">{errors.categoryId.message}</p>}
        </div>

        <fieldset>
          <legend className="label">Price</legend>
          <div className="mt-1 flex flex-col gap-2">
            {prices.fields.map((f, i) => (
              <div key={f.id}>
                <label className="flex items-center gap-2">
                  {prices.fields.length > 1 && <span className="w-20 text-sm text-muted">{f.label}</span>}
                  <span className="text-muted">$</span>
                  <input className="input tabular-nums" inputMode="decimal" placeholder="12.99" aria-label={`Price${prices.fields.length > 1 ? ` (${f.label})` : ""} in dollars`}
                    {...form.register(`prices.${i}.price`)} aria-invalid={!!errors.prices?.[i]?.price} />
                </label>
                {errors.prices?.[i]?.price && <p className="mt-1 text-sm text-[rgb(var(--nonveg))]">{errors.prices[i]!.price!.message}</p>}
              </div>
            ))}
          </div>
        </fieldset>

        <fieldset>
          <legend className="label">Veg or non-veg</legend>
          <div className="mt-1 grid grid-cols-3 gap-2">
            {DIETS.map((d) => (
              <label key={d.value} className="flex min-h-[48px] cursor-pointer items-center justify-center gap-2 rounded-xl border border-line px-2 font-semibold has-[:checked]:border-transparent has-[:checked]:bg-sunk has-[:checked]:ring-2 has-[:checked]:ring-[var(--accent)]">
                <input type="radio" value={d.value} className="sr-only" {...form.register("diet")} />
                <DietMark diet={d.value} /> {d.label}
              </label>
            ))}
          </div>
        </fieldset>

        <div>
          <label className="label" htmlFor="f-desc">Description <span className="font-normal text-muted">(optional)</span></label>
          <textarea id="f-desc" rows={3} className="input mt-1 py-2" {...form.register("description")} />
          {errors.description && <p className="mt-1 text-sm text-[rgb(var(--nonveg))]">{errors.description.message}</p>}
        </div>

        <div>
          <span className="label">Photo <span className="font-normal text-muted">(optional, up to 5 MB)</span></span>
          <div className="mt-1 flex flex-wrap items-center gap-3">
            {preview
              ? <img src={preview} alt="Dish photo preview" className="h-24 w-24 rounded-xl object-cover" />
              : <span className="grid h-24 w-24 place-items-center rounded-xl bg-sunk text-xs font-semibold uppercase text-muted">No photo</span>}
            <div className="flex flex-col gap-2">
              <label className="btn min-h-[48px] cursor-pointer">
                {busyPhoto ? "Preparing…" : preview ? "Change photo" : "Take or choose photo"}
                <input type="file" accept="image/*" capture="environment" className="sr-only"
                  onChange={(e) => { pickPhoto(e.target.files?.[0]); e.target.value = ""; }} />
              </label>
              {preview && (
                <button type="button" className="btn min-h-[48px] text-[rgb(var(--nonveg))]"
                  onClick={() => { setPhoto(item?.image_url ? "remove" : null); setPreview(null); }}>Remove photo</button>
              )}
            </div>
          </div>
          {photoError && <p className="mt-1 text-sm text-[rgb(var(--nonveg))]">{photoError}</p>}
        </div>

        {saveError && <Notice tone="error">{saveError}</Notice>}
      </form>
    </Sheet>
  );
}
