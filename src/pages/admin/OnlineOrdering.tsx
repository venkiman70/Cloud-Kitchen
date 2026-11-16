import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import { dateLabel, todayIn, zonedTime } from "../../lib/time";
import type { Closure } from "../../lib/types";
import { Notice, Spinner } from "../../components/ui";
import { useAdmin } from "./AdminShell";

type Hours = Record<string, [string, string] | null>;
type OrderingStatus = {
  paused: boolean;
  reason: string | null;
  until: string | null;
  pausedAt: string | null;
  pausedBy: string | null;
  pickupHours: Hours;
  closures: Closure[];
  timezone: string;
};

const DAYS: { key: string; label: string }[] = [
  { key: "mon", label: "Monday" }, { key: "tue", label: "Tuesday" }, { key: "wed", label: "Wednesday" },
  { key: "thu", label: "Thursday" }, { key: "fri", label: "Friday" }, { key: "sat", label: "Saturday" }, { key: "sun", label: "Sunday" },
];
// Same as the app and create_order(): a day missing from pickup_hours is open 11:00–21:00.
const DEFAULT_WINDOW: [string, string] = ["11:00", "21:00"];

const ERRORS: Record<string, string> = {
  NOT_ALLOWED: "Only owners and managers can change hours.",
  BAD_CLOSURES: "Check the closure dates.",
  BAD_RESUME_TIME: "Choose a resume time in the future.",
};
function friendly(message: string) {
  const [code, detail] = message.split(":");
  if (code === "BAD_HOURS") return `Check ${DAYS.find((d) => d.key === detail)?.label ?? "the"} hours: closing must be after opening.`;
  return ERRORS[code] ?? "Couldn't save. Check the internet connection and try again.";
}

export function useOrderingStatus() {
  const { member } = useAdmin();
  return useQuery({
    queryKey: ["ordering-status", member.tenantId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("online_ordering_status", { p_tenant: member.tenantId });
      if (error) throw error;
      return data as OrderingStatus;
    },
    refetchInterval: 30_000,
  });
}

function fmtTime(iso: string, tz: string) {
  return new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "short", hour: "numeric", minute: "2-digit" }).format(new Date(iso));
}

/** The emergency switch. On the Orders board (all staff) and the Hours page. */
export function PauseControl({ dark = false }: { dark?: boolean }) {
  const { member } = useAdmin();
  const tz = member.timezone;
  const qc = useQueryClient();
  const status = useOrderingStatus();
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState("");
  const [resume, setResume] = useState<"manual" | "30" | "60" | "120" | "today">("manual");
  const [err, setErr] = useState<string | null>(null);

  const set = useMutation({
    mutationFn: async (paused: boolean) => {
      let until: string | null = null;
      if (paused && resume !== "manual") {
        until = resume === "today"
          ? zonedTime(todayIn(tz, 1), "00:00", tz).toISOString()
          : new Date(Date.now() + Number(resume) * 60_000).toISOString();
      }
      const { data, error } = await supabase.rpc("set_online_ordering", {
        p_tenant: member.tenantId, p_paused: paused, p_reason: paused ? reason : null, p_until: until,
      });
      if (error) throw error;
      return data as OrderingStatus;
    },
    onSuccess: (data) => {
      qc.setQueryData(["ordering-status", member.tenantId], data);
      setAsking(false); setReason(""); setResume("manual"); setErr(null);
    },
    onError: (e: Error) => setErr(friendly(e.message)),
  });

  if (status.isLoading) return null;
  if (status.isError) return <Notice tone="error">Can't check whether online ordering is on.</Notice>;
  const s = status.data!;

  if (s.paused) {
    return (
      <div role="status" className="flex w-full flex-wrap items-center gap-3 rounded-xl bg-nonveg px-4 py-3 text-white">
        <div className="min-w-0 flex-1">
          <b className="block text-lg">Online ordering is PAUSED</b>
          <span className="text-sm opacity-90">
            {s.reason ? `${s.reason}. ` : ""}
            {s.until ? `Turns back on ${fmtTime(s.until, tz)}.` : "Stays off until someone turns it back on."}
            {s.pausedBy ? ` Paused by ${s.pausedBy}.` : ""}
          </span>
        </div>
        <button className="btn min-h-[48px] bg-white px-5 font-bold text-[rgb(var(--nonveg))]" disabled={set.isPending} onClick={() => set.mutate(false)}>
          {set.isPending ? "Turning on…" : "Turn online ordering back on"}
        </button>
        {err && <div className="w-full"><Notice tone="error">{err}</Notice></div>}
      </div>
    );
  }

  if (!asking) {
    return (
      <button className={`btn min-h-[44px] ${dark ? "" : "border-[rgb(var(--nonveg))] text-[rgb(var(--nonveg))]"}`} onClick={() => setAsking(true)}>
        Pause online orders
      </button>
    );
  }

  function submit(e: FormEvent) { e.preventDefault(); set.mutate(true); }
  return (
    <form onSubmit={submit} className="card flex w-full flex-col gap-3 p-4">
      <b className="text-lg">Pause online orders?</b>
      <p className="text-sm text-muted">Customers can still see the menu but can't place orders. Orders already placed are not affected.</p>
      <label className="label" htmlFor="pause-reason">Message for customers (optional)</label>
      <input id="pause-reason" className="input" maxLength={200} value={reason} onChange={(e) => setReason(e.target.value)}
        placeholder="Kitchen is very busy, back soon" />
      <span className="label">Turn back on</span>
      <div className="flex flex-wrap gap-2" role="group" aria-label="Turn back on">
        {([["manual", "When I turn it on"], ["30", "In 30 min"], ["60", "In 1 hour"], ["120", "In 2 hours"], ["today", "Tomorrow"]] as const).map(([v, l]) => (
          <button type="button" key={v} className="chip min-h-[44px]" aria-pressed={resume === v} onClick={() => setResume(v)}>{l}</button>
        ))}
      </div>
      {err && <Notice tone="error">{err}</Notice>}
      <div className="flex gap-2">
        <button type="button" className="btn flex-1" onClick={() => { setAsking(false); setErr(null); }} disabled={set.isPending}>Cancel</button>
        <button type="submit" className="btn-primary flex-1 !bg-[rgb(var(--nonveg))]" disabled={set.isPending}>{set.isPending ? "Pausing…" : "Pause now"}</button>
      </div>
    </form>
  );
}

type DayRow = { open: boolean; from: string; to: string };

/** Admin → Hours (owners and managers): pause switch, weekly hours, closure dates. */
export default function HoursPage() {
  const { member } = useAdmin();
  const tz = member.timezone;
  const qc = useQueryClient();
  const status = useOrderingStatus();
  const [rows, setRows] = useState<Record<string, DayRow> | null>(null);
  const [closures, setClosures] = useState<Closure[]>([]);
  const [newDate, setNewDate] = useState("");
  const [newNote, setNewNote] = useState("");
  const [msg, setMsg] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const today = todayIn(tz);

  // Load once from the server; after that the form is the source until saved.
  useEffect(() => {
    if (!status.data || rows) return;
    const h = status.data.pickupHours ?? {};
    const r: Record<string, DayRow> = {};
    for (const d of DAYS) {
      const w = d.key in h ? h[d.key] : DEFAULT_WINDOW;
      r[d.key] = w ? { open: true, from: w[0], to: w[1] } : { open: false, from: "10:00", to: "17:00" };
    }
    setRows(r);
    setClosures((status.data.closures ?? []).filter((c) => c.date >= today));
  }, [status.data, rows, today]);

  const bad = useMemo(() => rows ? DAYS.filter((d) => rows[d.key].open && !(rows[d.key].from < rows[d.key].to)).map((d) => d.key) : [], [rows]);

  const save = useMutation({
    mutationFn: async () => {
      const hours: Hours = {};
      for (const d of DAYS) hours[d.key] = rows![d.key].open ? [rows![d.key].from, rows![d.key].to] : null;
      const { data, error } = await supabase.rpc("update_store_hours", { p_tenant: member.tenantId, p_hours: hours, p_closures: closures });
      if (error) throw error;
      return data as { pickupHours: Hours; closures: Closure[] };
    },
    onSuccess: (data) => {
      setClosures(data.closures);
      qc.invalidateQueries({ queryKey: ["ordering-status", member.tenantId] });
      setMsg({ tone: "ok", text: "Saved. Customers see the new hours within a minute." });
    },
    onError: (e: Error) => setMsg({ tone: "error", text: friendly(e.message) }),
  });

  function setDay(key: string, patch: Partial<DayRow>) {
    setMsg(null);
    setRows((r) => r && { ...r, [key]: { ...r[key], ...patch } });
  }
  function copyMonday() {
    setMsg(null);
    setRows((r) => r && Object.fromEntries(DAYS.map((d) => [d.key, d.key === "sun" || d.key === "sat" ? r[d.key] : { ...r.mon }])));
  }
  function addClosure(e: FormEvent) {
    e.preventDefault();
    if (!newDate || newDate < today) return;
    setMsg(null);
    setClosures((c) => [...c.filter((x) => x.date !== newDate), { date: newDate, note: newNote.trim() || null }].sort((a, b) => a.date.localeCompare(b.date)));
    setNewDate(""); setNewNote("");
  }

  if (status.isLoading || !rows) return status.isError ? <main className="wrap py-6"><Notice tone="error">Can't load hours. Check the internet connection.</Notice></main> : <Spinner />;

  return (
    <main className="wrap max-w-2xl pb-24 pt-4">
      <h1 className="h-display text-3xl">Hours</h1>

      <section className="mt-4">
        <h2 className="eyebrow mb-2">Online ordering</h2>
        <div className="flex flex-wrap items-center gap-3">
          {!status.data!.paused && <span className="font-semibold text-[rgb(var(--veg))]">● On: customers can order</span>}
          <PauseControl />
        </div>
      </section>

      <section className="mt-8">
        <div className="mb-2 flex items-center gap-2">
          <h2 className="eyebrow flex-1">Weekly pickup hours</h2>
          <button type="button" className="btn min-h-[40px] text-sm" onClick={copyMonday}>Copy Monday to Tue–Fri</button>
        </div>
        <div className="card divide-y divide-line">
          {DAYS.map((d) => {
            const r = rows[d.key];
            return (
              <div key={d.key} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <span className="w-28 font-semibold">{d.label}</span>
                <label className="flex min-h-[44px] cursor-pointer items-center gap-2 text-sm">
                  <input type="checkbox" className="h-5 w-5" checked={r.open} onChange={(e) => setDay(d.key, { open: e.target.checked })} />
                  Open
                </label>
                {r.open ? (
                  <span className="flex items-center gap-2">
                    <input type="time" aria-label={`${d.label} opens`} className="input w-32" value={r.from} step={900}
                      onChange={(e) => setDay(d.key, { from: e.target.value })} />
                    <span aria-hidden="true">to</span>
                    <input type="time" aria-label={`${d.label} closes`} className="input w-32" value={r.to} step={900}
                      aria-invalid={bad.includes(d.key)} onChange={(e) => setDay(d.key, { to: e.target.value })} />
                  </span>
                ) : <span className="text-muted">Closed</span>}
                {bad.includes(d.key) && <span className="w-full text-sm text-[rgb(var(--nonveg))]">Closing time must be after opening time.</span>}
              </div>
            );
          })}
        </div>
        <p className="mt-2 text-sm text-muted">Times are {tz.replace("_", " ")} time. The last pickup slot is the closing time.</p>
      </section>

      <section className="mt-8">
        <h2 className="eyebrow mb-2">Closed dates (holidays, days off)</h2>
        <div className="card divide-y divide-line">
          {closures.length === 0 && <p className="px-4 py-3 text-muted">No closed dates coming up.</p>}
          {closures.map((c) => (
            <div key={c.date} className="flex items-center gap-3 px-4 py-3">
              <span className="w-32 font-semibold">{dateLabel(c.date, tz)}</span>
              <span className="min-w-0 flex-1 truncate text-muted">{c.note ?? ""}</span>
              <button type="button" className="btn min-h-[44px] text-[rgb(var(--nonveg))]"
                onClick={() => { setMsg(null); setClosures((x) => x.filter((y) => y.date !== c.date)); }}>Remove</button>
            </div>
          ))}
          <form onSubmit={addClosure} className="flex flex-wrap items-end gap-2 px-4 py-3">
            <div className="flex flex-col gap-1">
              <label className="label" htmlFor="c-date">Date</label>
              <input id="c-date" type="date" className="input" min={today} value={newDate} onChange={(e) => setNewDate(e.target.value)} />
            </div>
            <div className="flex min-w-0 flex-1 basis-48 flex-col gap-1">
              <label className="label" htmlFor="c-note">Note for customers (optional)</label>
              <input id="c-note" className="input" maxLength={120} value={newNote} onChange={(e) => setNewNote(e.target.value)} placeholder="Closed for Thanksgiving" />
            </div>
            <button className="btn min-h-[48px]" disabled={!newDate || newDate < today}>Add date</button>
          </form>
        </div>
      </section>

      <div className="sticky bottom-0 mt-8 flex flex-col gap-2 bg-bg py-3">
        {msg && <Notice tone={msg.tone}>{msg.text}</Notice>}
        <button className="btn-primary min-h-[52px] text-lg" disabled={save.isPending || bad.length > 0} onClick={() => save.mutate()}>
          {save.isPending ? "Saving…" : "Save hours and dates"}
        </button>
      </div>
    </main>
  );
}
