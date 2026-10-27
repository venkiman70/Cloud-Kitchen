import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "./supabase";
import { safeStorage } from "./format";
import type { Brand, StoreConfig } from "./types";

const storage = safeStorage();

/**
 * Which tenant is this? In order:
 *   1. ?tenant=aryas in the URL (local dev and preview links; remembered for the session)
 *   2. the custom domain (order.aryascuisine.com -> tenant_domains)
 *   3. VITE_DEFAULT_TENANT (fallback for *.vercel.app previews)
 */
function tenantHint(): { slug?: string; host?: string } {
  const fromUrl = new URLSearchParams(window.location.search).get("tenant");
  if (fromUrl) {
    try { sessionStorage.setItem("kos:tenant", fromUrl); } catch { /* ignore */ }
    return { slug: fromUrl };
  }
  try {
    const remembered = sessionStorage.getItem("kos:tenant");
    if (remembered) return { slug: remembered };
  } catch { /* ignore */ }
  const host = window.location.hostname;
  const isPreview = host === "localhost" || host.endsWith(".vercel.app") || /^[\d.]+$/.test(host);
  if (isPreview) return { slug: (import.meta.env.VITE_DEFAULT_TENANT as string) || "aryas" };
  return { host };
}

const StoreContext = createContext<StoreConfig | null>(null);

export function StoreProvider({ children, fallback }: { children: ReactNode; fallback: (state: "loading" | "missing" | "error") => ReactNode }) {
  const hint = useMemo(tenantHint, []);
  const q = useQuery({
    queryKey: ["store", hint],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("storefront_config", { p_tenant: hint.slug ?? null, p_host: hint.host ?? null });
      if (error) throw error;
      return data as StoreConfig | null;
    },
    staleTime: 5 * 60_000,
  });
  if (q.isLoading) return <>{fallback("loading")}</>;
  if (q.isError) return <>{fallback("error")}</>;
  if (!q.data) return <>{fallback("missing")}</>;
  return <StoreContext.Provider value={q.data}>{children}</StoreContext.Provider>;
}

export function useStore() {
  const ctx = useContext(StoreContext);
  if (!ctx) throw new Error("useStore outside StoreProvider");
  return ctx;
}

export function useBrand(slug: string | undefined): Brand | undefined {
  const store = useStore();
  const brand = store.brands.find((b) => b.slug === slug);
  useEffect(() => {
    const root = document.documentElement;
    const t = brand?.theme ?? store.brands[0]?.theme ?? {};
    const accent = t.accent ?? "#7A2318";
    // Light and dark accents; index.css picks the right pair for the viewer's theme.
    root.style.setProperty("--accent-l", accent);
    root.style.setProperty("--accent-ink-l", t.accentInk ?? "#FFF8EC");
    root.style.setProperty("--accent-d", t.accentDark ?? accent);
    root.style.setProperty("--accent-ink-d", t.accentInkDark ?? t.accentInk ?? "#1E1410");
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", accent);
    document.title = brand ? `${brand.name}: order online` : `${store.tenant.name}: order online`;
  }, [brand, store]);
  return brand;
}

// ---------------------------------------------------------------- cart
export type CartLine = {
  variantId: string;
  itemId: string;
  name: string;
  label: string;
  priceCents: number;
  quantity: number;
  diet: "veg" | "egg" | "non_veg";
  collectionId: string | null;
};

export function useCart(tenantSlug: string, brandSlug: string) {
  const key = `kos:cart:${tenantSlug}:${brandSlug}`;
  const [lines, setLines] = useState<CartLine[]>(() => storage.get<CartLine[]>(key, []));
  useEffect(() => storage.set(key, lines), [key, lines]);
  useEffect(() => {
    const onStorage = (e: StorageEvent) => { if (e.key === key) setLines(storage.get<CartLine[]>(key, [])); };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, [key]);

  return {
    lines,
    count: lines.reduce((n, l) => n + l.quantity, 0),
    subtotal: lines.reduce((n, l) => n + l.quantity * l.priceCents, 0),
    add(line: Omit<CartLine, "quantity">, qty = 1) {
      setLines((cur) => {
        const found = cur.find((l) => l.variantId === line.variantId);
        if (found) return cur.map((l) => (l.variantId === line.variantId ? { ...l, quantity: Math.min(100, l.quantity + qty) } : l));
        return [...cur, { ...line, quantity: qty }];
      });
    },
    setQty(variantId: string, qty: number) {
      setLines((cur) => (qty <= 0 ? cur.filter((l) => l.variantId !== variantId) : cur.map((l) => (l.variantId === variantId ? { ...l, quantity: Math.min(100, qty) } : l))));
    },
    clear() { setLines([]); },
  };
}

export function clearCart(tenantSlug: string, brandSlug: string) {
  storage.remove(`kos:cart:${tenantSlug}:${brandSlug}`);
}

// ---------------------------------------------------------------- remembered customer
export type SavedCustomer = { name: string; phone: string; email: string };
export const savedCustomer = {
  get: () => storage.get<SavedCustomer | null>("kos:me", null),
  set: (c: SavedCustomer) => storage.set("kos:me", c),
  clear: () => storage.remove("kos:me"),
};
