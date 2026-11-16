import { useStore } from "../lib/store";
import { todayIn } from "../lib/time";
import { Notice } from "./ui";

/** Customer-facing note when online ordering is paused or the store is closed today. */
export function StoreStatus() {
  const { settings: s } = useStore();
  const phone = s.phone?.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");
  if (s.orderingPaused) {
    const back = s.pausedUntil
      ? new Intl.DateTimeFormat("en-US", { timeZone: s.timezone, weekday: "short", hour: "numeric", minute: "2-digit" }).format(new Date(s.pausedUntil))
      : null;
    return (
      <Notice tone="warn">
        <b>Online ordering is paused right now.</b>{" "}
        {s.pausedReason ? `${s.pausedReason}. ` : ""}
        {back ? `We expect to be back ${back}. ` : "Please check back soon. "}
        {phone ? <>To order, call or WhatsApp {phone}.</> : null}
      </Notice>
    );
  }
  const closedToday = s.closures?.find((c) => c.date === todayIn(s.timezone));
  if (closedToday) {
    return (
      <Notice tone="info">
        <b>We're closed today{closedToday.note ? `: ${closedToday.note}` : ""}.</b> You can still order for pickup on another day.
      </Notice>
    );
  }
  return null;
}

/** True while customers can't place online orders. */
export function useOrderingPaused() {
  return Boolean(useStore().settings.orderingPaused);
}
