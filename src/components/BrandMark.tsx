import { useState } from "react";
import type { Brand } from "../lib/types";

/** Brand logo from brands.theme, falling back to the name in the display face if there's no logo or it fails to load. */
export function BrandMark({ brand, variant = "lockup", className = "" }: { brand: Brand; variant?: "lockup" | "stacked"; className?: string }) {
  const src = variant === "stacked" ? brand.theme.logoStacked ?? brand.theme.logo : brand.theme.logo;
  const [failed, setFailed] = useState(false);
  if (src && !failed) {
    return <img src={src} alt={brand.name} className={`${className} dark:rounded-xl dark:bg-[#FBF3E2] ${variant === "stacked" ? "dark:p-3" : "dark:px-2 dark:py-1"}`} onError={() => setFailed(true)} />;
  }
  return <span className={`h-display ${variant === "stacked" ? "text-5xl" : "text-2xl"}`} style={{ color: "var(--accent)" }}>{brand.name}</span>;
}
