export const money = (cents: number, currency = "usd") =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: currency.toUpperCase() }).format(cents / 100);

export const fmtPickup = (iso: string, timeZone: string) =>
  new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
    .format(new Date(iso));

export const fmtTime = (iso: string, timeZone: string) =>
  new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" }).format(new Date(iso));

/** Tax preview shown in the cart. The server recalculates the real amount. */
export const taxPreview = (subtotalCents: number, bps: number) => Math.floor((subtotalCents * bps + 5000) / 10000);

/** Format a US phone number as the customer types. */
export function formatPhone(raw: string) {
  const d = raw.replace(/\D/g, "").replace(/^1(?=\d{10})/, "").slice(0, 10);
  if (d.length < 4) return d;
  if (d.length < 7) return `(${d.slice(0, 3)}) ${d.slice(3)}`;
  return `(${d.slice(0, 3)}) ${d.slice(3, 6)}-${d.slice(6)}`;
}

export function safeStorage() {
  return {
    get<T>(key: string, fallback: T): T {
      try {
        const v = localStorage.getItem(key);
        return v ? (JSON.parse(v) as T) : fallback;
      } catch {
        return fallback;
      }
    },
    set(key: string, value: unknown) {
      try {
        localStorage.setItem(key, JSON.stringify(value));
      } catch {
        /* private mode or storage blocked */
      }
    },
    remove(key: string) {
      try {
        localStorage.removeItem(key);
      } catch {
        /* ignore */
      }
    },
  };
}
