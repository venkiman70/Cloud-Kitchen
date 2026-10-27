import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { functionError, supabase } from "../lib/supabase";
import { savedCustomer, useBrand, useCart, useStore } from "../lib/store";
import { formatPhone, money, taxPreview } from "../lib/format";
import { dateLabel, slotsFor, todayIn } from "../lib/time";
import { DietMark, FullPage, Notice } from "../components/ui";
import { BrandMark } from "../components/BrandMark";

export default function Checkout() {
  const { brandSlug } = useParams();
  const [params] = useSearchParams();
  const store = useStore();
  const s = store.settings;
  const brand = useBrand(brandSlug);
  const cart = useCart(store.tenant.slug, brandSlug ?? "");
  const me = savedCustomer.get();

  const [name, setName] = useState(me?.name ?? "");
  const [phone, setPhone] = useState(me?.phone ?? "");
  const [email, setEmail] = useState(me?.email ?? "");
  const [optIn, setOptIn] = useState(false);
  const [notes, setNotes] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Pickup dates: pre-order collections restrict the dates; otherwise the next 7 days.
  const cartCollections = store.collections.filter((c) => cart.lines.some((l) => l.collectionId === c.id));
  const dates = useMemo(() => {
    const today = todayIn(s.timezone);
    const restricted = cartCollections.find((c) => c.pickupDates?.length)?.pickupDates;
    const base = restricted ?? Array.from({ length: 7 }, (_, i) => todayIn(s.timezone, i));
    return base.filter((d) => d >= today);
  }, [cartCollections, s.timezone]);

  const [date, setDate] = useState<string>("");
  const slotOpts = { timeZone: s.timezone, hours: s.pickupHours, slotMinutes: s.slotMinutes, leadMinutes: s.leadTimeMinutes };
  const dateWithSlots = dates.filter((d) => slotsFor(d, slotOpts).length > 0);
  const activeDate = date && dateWithSlots.includes(date) ? date : dateWithSlots[0] ?? "";
  const slots = activeDate ? slotsFor(activeDate, slotOpts) : [];
  const [slot, setSlot] = useState("");
  useEffect(() => { if (!slots.some((x) => x.iso === slot)) setSlot(slots[0]?.iso ?? ""); }, [activeDate]); // eslint-disable-line

  const tax = taxPreview(cart.subtotal, s.taxRateBps);
  const total = cart.subtotal + tax;

  if (!brand) return <FullPage title="Menu not found"><Link to="/" className="underline">See all menus</Link></FullPage>;
  if (cart.count === 0) {
    return (
      <FullPage title="Your cart is empty">
        <Link to={`/${brand.slug}`} className="btn-primary mt-4">Back to the menu</Link>
      </FullPage>
    );
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const digits = phone.replace(/\D/g, "");
    if (!name.trim()) return setError("Enter your name.");
    if (digits.length < 10) return setError("Enter a 10-digit mobile number.");
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return setError("Check your email address.");
    if (!slot) return setError("Choose a pickup time.");

    setBusy(true);
    const { data, error } = await supabase.functions.invoke("create-order", {
      body: {
        tenant: store.tenant.slug,
        brand: brand!.slug,
        pickupAt: slot,
        notes,
        customer: { name: name.trim(), phone: digits, email: email.trim() || null, optInEmail: optIn && Boolean(email), optInSms: optIn },
        items: cart.lines.map((l) => ({ variantId: l.variantId, quantity: l.quantity })),
      },
    });
    if (error || !data?.url) {
      setBusy(false);
      setError(error ? await functionError(error) : "Payments aren't available right now. Try again in a minute.");
      return;
    }
    savedCustomer.set({ name: name.trim(), phone: formatPhone(digits), email: email.trim() });
    window.location.href = data.url; // Stripe Checkout
  }

  return (
    <>
    <header className="border-b border-line bg-surface" style={{ paddingTop: "env(safe-area-inset-top)" }}>
      <div className="wrap flex max-w-2xl items-center gap-3 py-2">
        <Link to={`/${brand.slug}`} className="btn min-h-[40px] px-3 text-sm" aria-label={`Back to ${brand.name}`}>←</Link>
        <BrandMark brand={brand} className="h-16 w-auto max-w-full rounded-lg" />
      </div>
      <div className="toran" aria-hidden="true" />
    </header>
    <main className="wrap max-w-2xl py-6 pb-16">
      <h1 className="h-display text-3xl" style={{ color: "var(--accent)" }}>Your order</h1>

      {params.get("cancelled") && (
        <div className="mt-4"><Notice tone="warn">Payment was cancelled, so order {params.get("cancelled")} wasn't placed. Your cart is still here.</Notice></div>
      )}

      <section className="card mt-4 divide-y divide-line">
        {cart.lines.map((l) => (
          <div key={l.variantId} className="flex flex-wrap items-center gap-x-3 gap-y-2 p-4">
            <DietMark diet={l.diet} />
            <div className="min-w-0 flex-1 basis-40">
              <div className="font-semibold">{l.name}</div>
              <div className="text-sm text-muted">{l.label} · {money(l.priceCents, s.currency)} each</div>
            </div>
            <div className="flex items-center gap-1" role="group" aria-label={`Quantity of ${l.name}`}>
              <button type="button" className="btn h-10 min-h-0 w-10 px-0" aria-label="Remove one" onClick={() => cart.setQty(l.variantId, l.quantity - 1)}>−</button>
              <span className="w-8 text-center font-semibold tabular-nums">{l.quantity}</span>
              <button type="button" className="btn h-10 min-h-0 w-10 px-0" aria-label="Add one" onClick={() => cart.setQty(l.variantId, l.quantity + 1)}>+</button>
            </div>
            <div className="w-20 text-right font-semibold tabular-nums">{money(l.priceCents * l.quantity, s.currency)}</div>
          </div>
        ))}
      </section>

      <form onSubmit={submit} className="mt-6 flex flex-col gap-6" noValidate>
        <fieldset className="flex flex-col gap-3">
          <legend className="mb-2 text-xs font-bold uppercase tracking-widest text-muted">Pickup</legend>
          {cartCollections.length > 0 && (
            <p className="text-sm text-muted">{cartCollections.map((c) => c.name).join(", ")}: pickup only on the dates below.</p>
          )}
          {dateWithSlots.length === 0 ? (
            <Notice tone="warn">No pickup times are open for these items right now. Call us to order.</Notice>
          ) : (
            <>
              <div className="flex gap-2 overflow-x-auto pb-1" role="group" aria-label="Pickup date">
                {dateWithSlots.map((d) => (
                  <button type="button" key={d} className="chip" aria-pressed={d === activeDate} onClick={() => setDate(d)}>
                    {d === todayIn(s.timezone) ? "Today" : dateLabel(d, s.timezone)}
                  </button>
                ))}
              </div>
              <label className="label" htmlFor="slot">Pickup time</label>
              <select id="slot" className="input" value={slot} onChange={(e) => setSlot(e.target.value)}>
                {slots.map((x) => <option key={x.iso} value={x.iso}>{x.label}</option>)}
              </select>
              {s.address && <p className="text-sm text-muted">Pickup at {s.address}</p>}
            </>
          )}
        </fieldset>

        <fieldset className="flex flex-col gap-3">
          <legend className="mb-2 text-xs font-bold uppercase tracking-widest text-muted">Your details</legend>
          <div className="flex flex-col gap-1">
            <label className="label" htmlFor="name">Name</label>
            <input id="name" className="input" autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Priya Raman" />
          </div>
          <div className="flex flex-col gap-1">
            <label className="label" htmlFor="phone">Mobile number</label>
            <input id="phone" className="input" inputMode="tel" autoComplete="tel" value={phone}
              onChange={(e) => setPhone(formatPhone(e.target.value))} placeholder="(214) 555-0101" />
          </div>
          <div className="flex flex-col gap-1">
            <label className="label" htmlFor="email">Email for your receipt</label>
            <input id="email" className="input" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="priya@example.com" />
          </div>
          <div className="flex flex-col gap-1">
            <label className="label" htmlFor="notes">Notes for the kitchen (optional)</label>
            <textarea id="notes" className="input min-h-[72px] py-2" maxLength={500} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Less spicy please" />
          </div>
          <label className="flex cursor-pointer items-start gap-3 text-sm">
            <input type="checkbox" className="mt-0.5 h-5 w-5 flex-none" style={{ accentColor: "var(--accent)" }} checked={optIn} onChange={(e) => setOptIn(e.target.checked)} />
            <span>Send me offers and festival menus from {store.tenant.name}. You can unsubscribe any time.</span>
          </label>
          {me && <button type="button" className="w-fit text-sm text-muted underline" onClick={() => { savedCustomer.clear(); setName(""); setPhone(""); setEmail(""); }}>Not {me.name.split(" ")[0]}? Clear details</button>}
        </fieldset>

        <section className="card flex flex-col gap-1 p-4 tabular-nums">
          <div className="flex justify-between"><span>Subtotal</span><span>{money(cart.subtotal, s.currency)}</span></div>
          <div className="flex justify-between text-muted"><span>Sales tax</span><span>{money(tax, s.currency)}</span></div>
          <div className="mt-1 flex justify-between border-t border-line pt-2 text-lg font-bold"><span>Total</span><span>{money(total, s.currency)}</span></div>
        </section>

        {error && <Notice tone="error">{error}</Notice>}

        <button type="submit" className="btn-primary min-h-[52px] text-lg" disabled={busy || !slot}>
          {busy ? "Opening secure payment…" : `Pay ${money(total, s.currency)}`}
        </button>
        <p className="-mt-3 text-center text-xs text-muted">Card, Apple Pay or Google Pay on Stripe's secure page. We never see your card number.</p>
      </form>
    </main>
    </>
  );
}
