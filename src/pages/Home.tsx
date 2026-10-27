import { Link } from "react-router-dom";
import { useBrand, useStore } from "../lib/store";
import { BrandMark } from "../components/BrandMark";
import { dateLabel } from "../lib/time";

/** Landing page: the shop's banner, then one card per brand using its own artwork. */
export default function Home() {
  const store = useStore();
  useBrand(undefined);
  const s = store.settings;
  const phone = s.phone?.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");
  const brandNames = store.brands.map((b) => b.name).join(" and ");

  return (
    <div className="min-h-screen" style={{ paddingTop: "env(safe-area-inset-top)" }}>
      {s.bannerUrl ? (
        <img src={s.bannerUrl} alt={`${brandNames}: authentic Indian food, sweets and snacks`}
          className="hidden max-h-[480px] w-full object-cover sm:block" />
      ) : null}
      <div className={`toran ${s.bannerUrl ? "sm:hidden" : ""}`} aria-hidden="true" />

      <main className="wrap pb-16 pt-6">
        <div className={`text-center ${s.bannerUrl ? "sm:sr-only" : ""}`}>
          <p className="eyebrow">Order online · pickup in Dallas</p>
          <h1 className="h-display mt-2 text-4xl text-fg sm:text-5xl">{store.tenant.name}</h1>
          <p className="script mt-1 text-xl" style={{ color: "rgb(var(--leaf))" }}>Good food · Happy moments</p>
        </div>

        <div className="mt-6 grid gap-5 sm:mt-2 sm:grid-cols-2">
          {store.brands.map((b) => {
            const cols = store.collections.filter((c) => c.brandId === b.id);
            return (
              <Link key={b.id} to={`/${b.slug}`}
                className="brand-scope card group relative flex flex-col overflow-hidden shadow-sm transition hover:-translate-y-1 hover:shadow-md"
                style={{
                  borderColor: `${b.theme.accent ?? "#1E6B33"}66`,
                  ["--accent-l" as string]: b.theme.accent ?? "#1E6B33", ["--accent-ink-l" as string]: b.theme.accentInk ?? "#FFFFFF",
                  ["--accent-d" as string]: b.theme.accentDark ?? b.theme.accent ?? "#7CC98C", ["--accent-ink-d" as string]: b.theme.accentInkDark ?? "#10230F",
                }}>
                {cols.length > 0 && (
                  <span className="absolute left-3 top-3 z-[1] rounded-full px-3 py-1 text-xs font-bold text-white shadow"
                    style={{ background: "#C2410C" }}>
                    {cols.map((c) => c.name).join(" · ")}
                  </span>
                )}
                {/* Phones: the brand's half of the artwork. Wide screens already show the full banner above, so just the logo. */}
                {b.theme.hero && (
                  <img src={b.theme.hero} alt={`${b.name}${b.tagline ? `: ${b.tagline}` : ""}`}
                    className={`aspect-[1095/750] w-full object-cover transition duration-300 group-hover:scale-[1.02] ${s.bannerUrl ? "sm:hidden" : ""}`} />
                )}
                {(!b.theme.hero || s.bannerUrl) && (
                  <div className={`justify-center pt-6 ${b.theme.hero ? "hidden sm:flex" : "flex"}`}>
                    <BrandMark brand={b} variant="stacked" className="h-44 w-auto max-w-[80%] rounded-xl object-contain" />
                  </div>
                )}
                <div className="flex flex-col items-center gap-2 p-5 text-center">
                  {cols.map((c) => c.pickupDates?.length ? (
                    <p key={c.id} className="text-sm text-muted">Pickup {c.pickupDates.map((d) => dateLabel(d, s.timezone)).join(", ")}</p>
                  ) : c.orderCutoffAt ? (
                    <p key={c.id} className="text-sm text-muted">Order by {dateLabel(c.orderCutoffAt.slice(0, 10), s.timezone)}</p>
                  ) : null)}
                  <span className="btn-primary w-full max-w-xs">
                    {b.slug === "ahil" ? "Order sweets & snacks" : "Order food"}
                  </span>
                </div>
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
