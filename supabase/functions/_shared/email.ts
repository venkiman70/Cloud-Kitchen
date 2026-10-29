// Transactional email through Resend. If RESEND_API_KEY is missing, emails are
// logged and skipped so local and staging setups still work.

export type Receipt = {
  orderNumber: string;
  publicToken: string;
  customerName?: string | null;
  customerEmail?: string | null;
  pickupAt: string;
  timezone: string;
  currency: string;
  brandName: string;
  tenantName: string;
  address?: string | null;
  pickupInstructions?: string | null;
  subtotalCents: number;
  taxCents: number;
  totalCents: number;
  paymentStatus?: string | null;
  payAtPickup?: boolean | null;
  items: { name: string; variant?: string | null; quantity: number; lineTotalCents: number }[];
};

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

export const money = (cents: number, currency = "usd") =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: currency.toUpperCase() }).format(cents / 100);

export const pickupText = (iso: string, timeZone: string) =>
  new Intl.DateTimeFormat("en-US", {
    timeZone, weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  }).format(new Date(iso));

function layout(r: Receipt, heading: string, intro: string, statusUrl: string): string {
  const due = r.paymentStatus === "unpaid";
  const rows = (r.items ?? []).map((i) =>
    `<tr><td style="padding:6px 0">${i.quantity} × ${esc(i.name)}${i.variant ? ` <span style="color:#666">(${esc(i.variant)})</span>` : ""}</td>
     <td style="padding:6px 0;text-align:right">${money(i.lineTotalCents, r.currency)}</td></tr>`
  ).join("");
  return `<!doctype html><html><body style="font-family:Arial,Helvetica,sans-serif;color:#1d2219;max-width:520px;margin:0 auto;padding:16px">
  <p style="font-size:13px;color:#666;margin:0">${esc(r.brandName)}</p>
  <h1 style="font-size:22px;margin:4px 0 12px">${esc(heading)}</h1>
  <p style="margin:0 0 12px">${esc(intro)}</p>
  <p style="margin:0 0 4px"><b>Order ${esc(r.orderNumber)}</b></p>
  <p style="margin:0 0 16px">Pickup: ${esc(pickupText(r.pickupAt, r.timezone))}${r.address ? `<br>${esc(r.address)}` : ""}</p>
  <table style="width:100%;border-collapse:collapse;font-size:14px">${rows}
    <tr><td style="padding:6px 0;border-top:1px solid #ddd">Subtotal</td><td style="padding:6px 0;border-top:1px solid #ddd;text-align:right">${money(r.subtotalCents, r.currency)}</td></tr>
    <tr><td style="padding:2px 0">Sales tax</td><td style="padding:2px 0;text-align:right">${money(r.taxCents, r.currency)}</td></tr>
    <tr><td style="padding:6px 0"><b>${due ? "Total to pay at pickup" : "Total paid"}</b></td><td style="padding:6px 0;text-align:right"><b>${money(r.totalCents, r.currency)}</b></td></tr>
  </table>
  ${r.pickupInstructions ? `<p style="margin:16px 0 0;font-size:14px">${esc(r.pickupInstructions)}</p>` : ""}
  <p style="margin:20px 0"><a href="${esc(statusUrl)}" style="background:#2f6b3a;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">View order status</a></p>
  <p style="font-size:12px;color:#888">${esc(r.tenantName)}</p>
  </body></html>`;
}

async function send(to: string, subject: string, html: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("EMAIL_FROM") ?? "Orders <onboarding@resend.dev>";
  if (!key) {
    console.log(`[email skipped: no RESEND_API_KEY] to=${to} subject=${subject}`);
    return false;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject, html }),
  });
  if (!res.ok) console.error("Resend error", res.status, await res.text());
  return res.ok;
}

export function sendReceipt(r: Receipt, appUrl: string) {
  if (!r.customerEmail) return Promise.resolve(false);
  const first = (r.customerName ?? "").split(" ")[0];
  return send(r.customerEmail, `${r.brandName}: order ${r.orderNumber} confirmed`,
    layout(r, "Thanks for your order",
      `${first ? first + ", w" : "W"}e've got your order and will have it ready for pickup.` +
        (r.paymentStatus === "unpaid" ? " You'll pay when you pick it up." : ""),
      `${appUrl}/order/${r.publicToken}`));
}

export function sendReady(r: Receipt, appUrl: string) {
  if (!r.customerEmail) return Promise.resolve(false);
  return send(r.customerEmail, `${r.brandName}: order ${r.orderNumber} is ready for pickup`,
    layout(r, "Your order is ready", "Your order is packed and ready for pickup.", `${appUrl}/order/${r.publicToken}`));
}
