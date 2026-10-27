import { useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import { fmtPickup, fmtTime } from "../../lib/format";
import { todayIn } from "../../lib/time";
import type { BoardOrder, OrderStatus } from "../../lib/types";
import { DietMark, Notice } from "../../components/ui";
import { useAdmin } from "./AdminShell";

const COLUMNS: { status: OrderStatus; title: string; next?: OrderStatus; nextLabel?: string; back?: OrderStatus }[] = [
  { status: "confirmed", title: "New", next: "preparing", nextLabel: "Start preparing" },
  { status: "preparing", title: "Preparing", next: "ready", nextLabel: "Mark ready", back: "confirmed" },
  { status: "ready", title: "Ready", next: "completed", nextLabel: "Picked up", back: "preparing" },
  { status: "completed", title: "Picked up", back: "ready" },
];

function useChime() {
  const ctx = useRef<AudioContext | null>(null);
  const [on, setOn] = useState(false);
  return {
    on,
    enable() {
      try { ctx.current = new AudioContext(); setOn(true); } catch { setOn(false); }
    },
    play() {
      const ac = ctx.current;
      if (!ac) return;
      [0, 0.18, 0.36].forEach((t, i) => {
        const o = ac.createOscillator(); const g = ac.createGain();
        o.frequency.value = [880, 1175, 1568][i]; o.type = "sine";
        g.gain.setValueAtTime(0.0001, ac.currentTime + t);
        g.gain.exponentialRampToValueAtTime(0.4, ac.currentTime + t + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + t + 0.3);
        o.connect(g).connect(ac.destination); o.start(ac.currentTime + t); o.stop(ac.currentTime + t + 0.32);
      });
    },
  };
}

export default function Board({ kitchen = false }: { kitchen?: boolean }) {
  const { member } = useAdmin();
  const TZ = member.timezone;
  const qc = useQueryClient();
  const chime = useChime();
  const seen = useRef<Set<string> | null>(null);
  const [fresh, setFresh] = useState<Set<string>>(new Set());
  const [live, setLive] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  const board = useQuery({
    queryKey: ["board", member.tenantId],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("kitchen_board", { p_tenant: member.tenantId });
      if (error) throw error;
      return data as BoardOrder[];
    },
    refetchInterval: 15_000, // backup in case the live connection drops
  });

  useEffect(() => {
    const ch = supabase.channel(`board-${member.tenantId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "order_signals", filter: `tenant_id=eq.${member.tenantId}` },
        () => qc.invalidateQueries({ queryKey: ["board", member.tenantId] }))
      .subscribe((status) => setLive(status === "SUBSCRIBED"));
    return () => { supabase.removeChannel(ch); };
  }, [member.tenantId, qc]);

  // Chime and highlight for orders we haven't seen before
  useEffect(() => {
    if (!board.data) return;
    const ids = board.data.filter((o) => o.status === "confirmed").map((o) => o.id);
    if (seen.current === null) { seen.current = new Set(board.data.map((o) => o.id)); return; }
    const newOnes = ids.filter((id) => !seen.current!.has(id));
    board.data.forEach((o) => seen.current!.add(o.id));
    if (newOnes.length) {
      chime.play();
      setFresh((f) => new Set([...f, ...newOnes]));
    }
  }, [board.data]); // eslint-disable-line

  async function move(o: BoardOrder, to: OrderStatus) {
    setBusyId(o.id); setProblem(null);
    const { error } = await supabase.rpc("advance_order", { p_order: o.id, p_to: to });
    setBusyId(null);
    setFresh((f) => { const n = new Set(f); n.delete(o.id); return n; });
    if (error) { setProblem(`Couldn't update ${o.orderNumber}. Try again.`); return; }
    qc.invalidateQueries({ queryKey: ["board", member.tenantId] });
    if (to === "ready") supabase.functions.invoke("notify-ready", { body: { orderId: o.id } }).catch(() => undefined);
  }

  const today = todayIn(TZ);
  const orders = board.data ?? [];
  const localDate = (iso: string) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date(iso));
  const current = orders.filter((o) => localDate(o.pickupAt) <= today || o.status !== "confirmed");
  const upcoming = orders.filter((o) => localDate(o.pickupAt) > today && o.status === "confirmed");
  const big = kitchen ? "text-lg" : "text-base";

  return (
    <div className={kitchen ? "kitchen-dark min-h-screen bg-bg text-fg" : ""}>
      <div className={kitchen ? "px-4 py-3" : "wrap max-w-none py-4"}>
        <div className="mb-3 flex flex-wrap items-center gap-3">
          {kitchen && <span className="h-display text-2xl">{member.name} · Kitchen</span>}
          <span className="flex-1" />
          {!live && <span className="rounded-full bg-nonveg px-3 py-1 text-sm font-bold text-white">Offline: retrying</span>}
          {!chime.on && <button className="btn-primary" onClick={chime.enable}>Turn on new-order sound</button>}
          {kitchen && <a href="/admin" className="btn">Exit kitchen screen</a>}
        </div>
        {problem && <div className="mb-3"><Notice tone="error">{problem}</Notice></div>}
        {board.isError && <div className="mb-3"><Notice tone="error">Can't load orders. Check the internet connection.</Notice></div>}

        {upcoming.length > 0 && (
          <details className="card mb-4 p-3">
            <summary className="cursor-pointer font-semibold">Upcoming pre-orders: {upcoming.length} for later dates</summary>
            <ul className="mt-2 grid gap-1 text-sm sm:grid-cols-2 lg:grid-cols-3">
              {upcoming.map((o) => (
                <li key={o.id}><b>{o.orderNumber}</b> · {fmtPickup(o.pickupAt, TZ)} · {o.firstName} · {o.items.reduce((n, i) => n + i.quantity, 0)} items</li>
              ))}
            </ul>
          </details>
        )}

        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          {COLUMNS.map((col) => {
            const list = current.filter((o) => o.status === col.status);
            return (
              <section key={col.status} className="flex min-w-0 flex-col gap-3 rounded-2xl bg-sunk p-3">
                <h2 className="flex items-center justify-between h-display text-xl">{col.title}<span className="text-base text-muted">{list.length}</span></h2>
                {list.length === 0 && <p className="py-6 text-center text-sm text-muted">No orders</p>}
                {list.map((o) => {
                  const mins = Math.round((new Date(o.pickupAt).getTime() - Date.now()) / 60000);
                  const urgent = col.status !== "completed" && col.status !== "ready" && mins < 0 ? "border-nonveg" : col.status !== "completed" && col.status !== "ready" && mins < 10 ? "border-gold" : "border-line";
                  const mixed = o.items.some((i) => i.diet !== "veg") && o.items.some((i) => i.diet === "veg");
                  return (
                    <article key={o.id} className={`card border-2 ${urgent} ${fresh.has(o.id) ? "ring-4 ring-[color:var(--accent)]" : ""} flex flex-col gap-2 p-3`}>
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <div className={`h-display ${kitchen ? "text-3xl" : "text-2xl"}`}>{o.orderNumber}</div>
                          <div className="text-sm text-muted">{o.firstName || "Guest"} · {o.brand} · {o.channel.replace("_", " ")}</div>
                        </div>
                        <div className="text-right">
                          <div className={`font-bold ${big}`}>{fmtTime(o.pickupAt, TZ)}</div>
                          <div className="text-xs text-muted">{localDate(o.pickupAt) === today ? (mins >= 0 ? `in ${mins} min` : `${-mins} min late`) : fmtPickup(o.pickupAt, TZ)}</div>
                        </div>
                      </div>
                      {mixed && <div className="rounded-md bg-nonveg px-2 py-0.5 text-center text-xs font-bold uppercase tracking-wider text-white">Non-veg on ticket</div>}
                      <ul className={`flex flex-col gap-1 ${big}`}>
                        {o.items.map((it, i) => (
                          <li key={i} className="flex items-start gap-2">
                            <DietMark diet={it.diet} />
                            <span><b className="tabular-nums">{it.quantity} ×</b> {it.name}{it.variant && it.variant !== "Regular" ? <span className="text-muted"> ({it.variant})</span> : null}</span>
                          </li>
                        ))}
                      </ul>
                      {o.notes && <div className="rounded-lg border-2 border-dashed border-gold px-2 py-1 text-sm"><b>Note:</b> {o.notes}</div>}
                      <div className="mt-1 flex gap-2">
                        {col.back && <button className="btn min-h-[48px] px-3 text-sm" disabled={busyId === o.id} onClick={() => move(o, col.back!)} aria-label={`Move ${o.orderNumber} back`}>Back</button>}
                        {col.next && <button className="btn-primary min-h-[56px] flex-1 text-base" disabled={busyId === o.id} onClick={() => move(o, col.next!)}>{col.nextLabel}</button>}
                      </div>
                    </article>
                  );
                })}
              </section>
            );
          })}
        </div>
      </div>
    </div>
  );
}
