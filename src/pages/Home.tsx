import { Link } from "react-router-dom";
import { useBrand, useStore } from "../lib/store";
import { BrandMark } from "../components/BrandMark";
import { dateLabel } from "../lib/time";

/** Landing page: the two brands side by side under a marigold garland, like the shop's artwork. */
export default function Home() {
  const store = useStore();
  useBrand(undefined);
  const s = store.settings;
  const phone = s.phone?.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");

  return (
    <div className="min-h-screen" style={{ paddingTop: "env(safe-area-inset-top)" }}>
      <div className="toran" aria-hidden="true" />
      <main className="wrap pb-16 pt-6">
        <div className="text-center">
          <p className="eyebrow">Order online · pickup in Dallas</p>
          <h1 className="h-display mt-2 text-4xl text-fg sm:text-5xl">{store.tenant.name}</h1>
          <p className="script mt-1 text-xl" style={{ color: "rgb(var(--leaf))" }}>Good food · Happy moments</p>
        </div>

        <div className="mt-8 grid gap-5 sm:grid-cols-2">
          {store.brands.map((b) => {
            const cols = store.collections.filter((c) => c.brandId === b.id);
            return (
              <Link key={b.id} to={`/${b.slug}`}
                className="card group relative flex flex-col items-center gap-3 overflow-hidden p-6 text-center shadow-sm transition hover:-translate-y-1 hover:shadow-md"
                style={{ borderColor: `${b.theme.accent ?? "#7A2318"}55` }}>
                {cols.length > 0 && (
                  <span className="absolute right-3 top-3 rounded-full px-3 py-1 text-xs font-bold text-fg" style={{ background: "rgb(var(--marigold) / .25)" }}>
                    {cols.map((c) => c.name).join(" · ")}
                  </span>
                )}
                <BrandMark brand={b} variant="stacked" className={`${cols.length ? "mt-8" : "mt-2"} h-48 w-48 object-contain sm:h-56 sm:w-56`} />
                {cols.map((c) => c.pickupDates?.length ? (
                  <p key={c.id} className="text-sm text-muted">Pickup {c.pickupDates.map((d) => dateLabel(d, s.timezone)).join(", ")}</p>
                ) : null)}
                <span className="btn-primary mt-1 w-full max-w-xs" style={{ background: b.theme.accent, color: b.theme.accentInk }}>
                  {b.slug === "ahil" ? "Order sweets & savouries" : "Order food"}
                </span>
              </Link>
            );
          })}
        </div>

        <section className="mt-10 grid gap-3 text-center text-sm text-muted sm:grid-cols-3">
          <div className="rounded-2xl bg-sunk px-4 py-3"><b className="block text-fg">Pick up</b>{s.address ?? "Dallas, TX"}</div>
          <div className="rounded-2xl bg-sunk px-4 py-3"><b className="block text-fg">Pay securely</b>Card, Apple Pay or Google Pay</div>
          <div className="rounded-2xl bg-sunk px-4 py-3"><b className="block text-fg">Questions</b>{phone ? <>Call or WhatsApp <span className="font-semibold text-fg">{phone}</span></> : "Message us on WhatsApp"}</div>
        </section>
      </main>
    </div>
  );
}
