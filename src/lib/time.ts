// Pickup slot maths in the store's time zone (America/Chicago for Aryas),
// whatever time zone the customer's phone is in.

const DAY_KEYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;

function partsIn(date: Date, timeZone: string) {
  const p = new Intl.DateTimeFormat("en-US", {
    timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(date);
  const get = (t: string) => Number(p.find((x) => x.type === t)?.value);
  return { y: get("year"), m: get("month"), d: get("day"), h: get("hour"), min: get("minute"), s: get("second") };
}

/** Offset (ms) of a time zone from UTC at a given instant. */
function offsetMs(date: Date, timeZone: string) {
  const p = partsIn(date, timeZone);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.min, p.s) - Math.floor(date.getTime() / 1000) * 1000;
}

/** "2026-11-07" + "12:30" in America/Chicago -> Date (UTC instant). */
export function zonedTime(dateStr: string, timeStr: string, timeZone: string): Date {
  const [y, m, d] = dateStr.split("-").map(Number);
  const [hh, mm] = timeStr.split(":").map(Number);
  const guess = Date.UTC(y, m - 1, d, hh, mm);
  let t = guess - offsetMs(new Date(guess), timeZone);
  t = guess - offsetMs(new Date(t), timeZone); // second pass handles DST edges
  return new Date(t);
}

/** Today's date (YYYY-MM-DD) in the store's time zone. */
export function todayIn(timeZone: string, addDays = 0): string {
  const p = partsIn(new Date(Date.now() + addDays * 86400000), timeZone);
  return `${p.y}-${String(p.m).padStart(2, "0")}-${String(p.d).padStart(2, "0")}`;
}

export function dayKey(dateStr: string): (typeof DAY_KEYS)[number] {
  const [y, m, d] = dateStr.split("-").map(Number);
  return DAY_KEYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
}

export function dateLabel(dateStr: string, timeZone: string) {
  const noon = zonedTime(dateStr, "12:00", timeZone);
  return new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short", month: "short", day: "numeric" }).format(noon);
}

const DEFAULT_HOURS: [string, string] = ["11:00", "21:00"];

/** Available pickup slots for one date, respecting hours and lead time. */
export function slotsFor(
  dateStr: string,
  opts: { timeZone: string; hours: Record<string, [string, string] | null>; slotMinutes: number; leadMinutes: number },
): { iso: string; label: string }[] {
  const key = dayKey(dateStr);
  // Same rule as create_order(): a day missing from pickup_hours is open (default hours); null = closed.
  const hours = opts.hours ?? {};
  const h = key in hours ? hours[key] : DEFAULT_HOURS;
  if (!h) return [];
  const [oh, om] = h[0].split(":").map(Number);
  const [ch, cm] = h[1].split(":").map(Number);
  const earliest = Date.now() + opts.leadMinutes * 60000;
  const out: { iso: string; label: string }[] = [];
  for (let mins = oh * 60 + om; mins <= ch * 60 + cm; mins += opts.slotMinutes) {
    const t = zonedTime(dateStr, `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, "0")}`, opts.timeZone);
    if (t.getTime() < earliest) continue;
    out.push({
      iso: t.toISOString(),
      label: new Intl.DateTimeFormat("en-US", { timeZone: opts.timeZone, hour: "numeric", minute: "2-digit" }).format(t),
    });
  }
  return out;
}
