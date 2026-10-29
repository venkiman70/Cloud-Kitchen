# Changelog

## 0.4.0 — Wed 28 Oct 2026 (Pay at pickup + Mark paid)

- **Checkout:** when the kitchen allows it, customers choose **Pay now** (card, Apple Pay, Google Pay, Link) or **Pay at pickup**. Pay at pickup sends the order straight to the kitchen as confirmed and unpaid, emails a receipt that says "Total to pay at pickup", and is refused over the cap (`tenant_settings.pay_at_pickup_max_cents`, default $100). Aryas: on.
- **Orders board and kitchen screen:** unpaid orders carry a PAY AT PICKUP banner with the amount due. In Ready, "Picked up" is replaced by **Mark paid by Cash / Check / Zelle / Card (Square)**; other columns have a "Paid?" button for early payers. Paid orders show how they were paid. Owners and managers can **Undo** a wrong tap before pickup.
- **Rules in the database:** an unpaid order can't be marked Picked up (`NOT_PAID`). Each manual payment writes `payments` (method, who), `audit_log` (`mark_paid` / `undo_paid`) and the 4% fee to `platform_fee_ledger` as `invoice`.
- **Stripe:** pickup checkouts offer cards and Link only, no bank debits (ACH takes days to clear; kept for catering). The webhook already confirms orders only when Stripe says `paid`.
- Upcoming strip: "1 item" not "1 items".
- **Database:** migration `20261028000006_pay_at_pickup.sql` (paste-in copy: `supabase/pay_at_pickup_2026-10-28.sql`). New tests in `supabase/tests/rls_and_orders_test.sql`. `scripts/build_paste_functions.py` regenerates `supabase/functions_paste/`.

## 0.3.0 — Tue 27 Oct 2026 (Menu manager)

- **Admin → Menu** (owners and managers only; hidden from kitchen staff): dishes grouped by brand and category with photo, price, veg/non-veg mark and a Sold-out switch.
- **Add / Edit dish** in one form (bottom sheet on phones, dialog on tablets and desktop): name, category, price in dollars (saved as cents), description, veg/egg/non-veg, photo. Validated with Zod + React Hook Form.
- **Photos:** take with the phone camera or choose a file (max 5 MB), shrunk to 1200 px WebP in the browser, uploaded to the `menu` bucket at `tenant/{tenant_id}/menu/{item_id}.webp`; preview and Remove photo.
- **Remove / Restore:** soft delete (`deleted_at`) with a confirm step; "Show removed" lists removed dishes with Restore. Past orders keep their names and prices.
- **Audit log:** new `audit_log` table; database triggers record every price change and every remove/restore (old value, new value, user, time). Readable by owners and managers only.
- **Database:** migration `20261027000005_menu_manager.sql` (paste-in copy: `supabase/menu_manager_2026-10-27.sql`) creates the public-read `menu` bucket and storage policies that let only owners and managers of that tenant write to it. Tests: `supabase/tests/menu_manager_test.sql`.
- Not yet: crop, CSV import, drag reorder, adding variants or modifiers, daily limits.

## 0.2.1 — Mon 26 Oct 2026 (owner's artwork)

- Uses the Aryas / AHIL banner artwork: full banner on the home page (wide screens), each brand's half as its card picture on phones, logos cropped from the artwork in the menu and checkout headers, new app icon (chef and "A").
- Colours matched to the artwork: Aryas leaf green, AHIL sky blue, dark-brown lettering; each brand card keeps its own colour.
- New `tenant_settings.banner_url` (migration 0004) so each kitchen can have its own banner.
- Paste-in file for existing projects: `supabase/branding_2026-10-26.sql` (replaces brand_theme_2026-10-26.sql).
- Dish photos for 9 Aryas items (`public/menu/aryas/`, set by `supabase/menu_photos_2026-10-26.sql`); larger photos on menu cards; admin Menu shows a thumbnail or a "No photo" tag.
- 29 more dish photos from the menu poster; 4 matched to existing dishes (Sev Puri, Ragada Chaat, Podi Rice, Egg Kathi Roll); 25 new dishes ready in `supabase/menu_aryas_full_menu_TEMPLATE.sql`, which refuses to run until every price is filled in.
- Photos for every remaining dish: 11 Aryas (larger versions replace 4 small ones) and all 17 AHIL Diwali items (`public/menu/ahil/`). `menu_photos_2026-10-26.sql` now covers all 37 dishes.

## 0.2.0 — Mon 26 Oct 2026 (festive theme)

- New look from the Aryas / AHIL artwork: cream paper, maroon and marigold for Aryas, royal blue for AHIL, banana-leaf green, marigold garland strip on every customer page.
- Logos come from `brands.theme` so other kitchens can use their own.
- Fonts bundled with the app (Rozha One, Kaushan Script, Figtree) instead of loading from Google.
- Dark mode: logos sit on a cream plate so they stay readable; brand colours have dark-mode versions.
- Checkout has the brand header; roomier cart rows on phones.
- Fix: a weekday missing from pickup hours now counts as open in the app, matching the database.
- Real Aryas menu from Uber Eats (`supabase/menu_aryas_ubereats_2026-10-26.sql`).

## 0.1.0 — Mon 26 Oct 2026 (Day 1)

First cut of the Diwali fast-track.

- **Database:** multi-tenant schema with brands (Aryas Cuisine, AHIL), menu with pack-size variants and seasonal collections, customers keyed by phone, orders, payments, status history, platform fee ledger. Row Level Security on every table.
- **Pricing on the server:** `create_order()` checks stock, sold-out items, daily limits, pickup hours, lead time, slot capacity and Diwali pickup dates and cutoff, then computes subtotal, 8.25% tax and the 4% platform fee.
- **Stripe (test mode):** `create-order` opens Stripe Checkout (cards, Apple Pay, Google Pay) with Connect application fee support; `stripe-webhook` marks orders paid, expired or refunded and is safe to replay.
- **Customer app:** brand picker, menu with veg filter and live sold-out, cart, checkout with pickup date/time and remembered details, order status page.
- **Staff app:** email sign-in; order board (New → Preparing → Ready → Picked up) with live updates, new-order chime and late warnings; full-screen kitchen screen; prep list per pickup date; menu sold-out switches and price edits; sales page for owners and managers.
- **Emails (Resend):** receipt after payment, "ready for pickup" when staff mark Ready.
- **Tests:** `supabase/tests/rls_and_orders_test.sql` covers tenant isolation, kitchen staff seeing no money, pricing, Diwali rules, webhook replay and refunds.
- **Seed:** Aryas sample dishes (marked Sample) and the 17 AHIL Diwali items from the flyer.
