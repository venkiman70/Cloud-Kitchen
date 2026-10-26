import { Link } from "react-router-dom";
import { useBrand, useStore } from "../lib/store";

/** Landing page: pick a brand (Aryas Cuisine or AHIL). Skips straight to the menu when there's only one. */
export default function Home() {
  const store = useStore();
  useBrand(undefined);
  const s = store.settings;

  return (
    <main className="wrap py-10">
      <p className="text-sm font-semibold uppercase tracking-widest text-muted">Order for pickup</p>
      <h1 className="mt-1 font-display text-4xl sm:text-5xl">{store.tenant.name}</h1>
      {s.address && <p className="mt-2 text-muted">{s.address}</p>}

      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        {store.brands.map((b) => (
          <Link key={b.id} to={`/${b.slug}`} className="card group flex flex-col gap-2 p-6 transition hover:-translate-y-0.5"
            style={{ borderColor: b.theme.accent }}>
            <span className="font-display text-3xl" style={{ color: b.theme.accent }}>{b.name}</span>
            {b.tagline && <span className="text-muted">{b.tagline}</span>}
            {store.collections.some((c) => c.brandId === b.id) && (
              <span className="mt-1 w-fit rounded-full px-3 py-1 text-sm font-semibold" style={{ background: "rgb(var(--gold) / .18)" }}>
                {store.collections.filter((c) => c.brandId === b.id).map((c) => c.name).join(" · ")}
              </span>
            )}
            <span className="mt-3 font-semibold" style={{ color: b.theme.accent }}>See the menu →</span>
          </Link>
        ))}
      </div>

      {(s.phone || s.pickupInstructions) && (
        <p className="mt-10 text-sm text-muted">
          {s.pickupInstructions} {s.phone && <>Questions? Call or WhatsApp <span className="font-semibold text-fg">{s.phone.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3")}</span>.</>}
        </p>
      )}
    </main>
  );
}
