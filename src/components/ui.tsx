import type { ReactNode } from "react";
import type { Diet } from "../lib/types";

/** Indian veg / non-veg mark: square outline with a dot (veg, egg) or triangle (non-veg). */
export function DietMark({ diet, size = 16 }: { diet: Diet; size?: number }) {
  const color = diet === "veg" ? "rgb(var(--veg))" : diet === "egg" ? "rgb(var(--egg))" : "rgb(var(--nonveg))";
  const title = diet === "veg" ? "Vegetarian" : diet === "egg" ? "Contains egg" : "Non-vegetarian";
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" role="img" aria-label={title} className="mt-0.5 flex-none">
      <title>{title}</title>
      <rect x="1" y="1" width="14" height="14" rx="2.5" fill="none" stroke={color} strokeWidth="2" />
      {diet === "non_veg" ? <path d="M8 4.2 L11.6 11 H4.4 Z" fill={color} /> : <circle cx="8" cy="8" r="3.4" fill={color} />}
    </svg>
  );
}

export function Notice({ tone = "info", children }: { tone?: "info" | "warn" | "error" | "ok"; children: ReactNode }) {
  const cls = {
    info: "bg-sunk text-fg",
    warn: "bg-[#fff1d6] text-[#7a4a00] dark:bg-[#3a2c10] dark:text-[#f6cf86]",
    error: "bg-[#fde8e6] text-[#8a1c14] dark:bg-[#3d1714] dark:text-[#ffb4ab]",
    ok: "bg-[#e3f2e5] text-[#1d5a2a] dark:bg-[#1c3320] dark:text-[#a6dfb1]",
  }[tone];
  return <div role={tone === "error" ? "alert" : "status"} className={`rounded-xl px-4 py-3 text-sm ${cls}`}>{children}</div>;
}

export function FullPage({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="wrap flex min-h-[60vh] flex-col items-center justify-center gap-3 py-16 text-center">
      <h1 className="font-display text-3xl">{title}</h1>
      {children && <div className="max-w-md text-muted">{children}</div>}
    </div>
  );
}

export function Spinner({ label = "Loading" }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-3 py-16 text-muted" role="status">
      <span className="h-5 w-5 animate-spin rounded-full border-2 border-line" style={{ borderTopColor: "var(--accent)" }} />
      {label}
    </div>
  );
}

export const SPICE = ["", "Mild", "Medium", "Hot"];
