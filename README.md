# KitchenOS: Aryas Cuisine ordering platform

White-label ordering for cloud kitchens. Tenant #1 is **Aryas Cuisine** (Dallas) with two brands: **Aryas Cuisine** (South and North Indian meals) and **AHIL** (sweets and savouries, Diwali pre-orders).

One React app on Vercel serves everyone; the login decides what each person sees.

| Who | Address | What they can do |
| --- | --- | --- |
| Customers | `/`, `/aryas`, `/ahil` | Browse, veg filter, cart, pick pickup time, pay with Stripe, track order |
| Kitchen staff | `/admin`, `/kitchen` (login) | Order board, prep list, sold-out switches. **No prices, totals or customer contact details.** |
| Owner / manager | `/admin` (login) | Everything above, plus price edits and the Sales page |
| Platform admin (you) | SQL for now | Tenants, fee %, Stripe account per tenant |

```
Customer phone ─┐                       ┌─ Stripe Checkout (cards, Apple Pay, Google Pay)
Store tablet ───┼─ React app (Vercel) ──┤
Owner phone ────┘          │            └─ Resend (receipt + "ready" emails)
                     Supabase: Postgres + RLS, Auth, Realtime,
                     Edge Functions: create-order, stripe-webhook, notify-ready
```

Card numbers never touch this app: customers pay on Stripe's page. All prices, tax, limits and the platform fee are computed in Postgres (`create_order()`); the browser never sends a trusted price.

---

## Set it up (about 45 minutes, all in test mode)

### 1. Supabase (database, logins, functions)

1. Create a project at [supabase.com](https://supabase.com) (region: US East or US Central). Note the **Project URL**, **anon key** and **service_role key** (Project Settings → API).
2. Install the CLI and link the project:
   ```bash
   npm i -g supabase
   supabase login
   supabase link --project-ref YOUR-PROJECT-REF
   ```
3. Create the tables, rules and functions, then load the menu:
   ```bash
   supabase db push      # runs supabase/migrations/*
   ```
   Then open **SQL Editor**, paste the contents of `supabase/seed.sql` and click **Run**.
   Do **not** run `supabase/tests/_local_supabase_shim.sql` on Supabase; it's only for local testing.
4. Run the safety test (it rolls back and leaves no data): paste `supabase/tests/rls_and_orders_test.sql` into SQL Editor → Run. The last line should read `ALL TESTS PASSED`.
5. **Auth → URL Configuration:** Site URL = your Vercel URL (later `https://order.aryascuisine.com`). Add redirect URLs: `https://*.vercel.app/**`, `http://localhost:5173/**`.
6. **Add staff.** Authentication → Users → *Invite user* (their email). Then in SQL Editor:
   ```sql
   insert into tenant_members (tenant_id, user_id, role)
   select t.id, u.id, 'owner'            -- or 'manager' / 'kitchen_staff'
   from tenants t, auth.users u
   where t.slug = 'aryas' and u.email = 'owner@example.com';

   -- Your own platform-admin access:
   insert into platform_admins (user_id) select id from auth.users where email = 'venkiman70@gmail.com';
   ```

### 2. Stripe (test mode)

1. In the Stripe dashboard (Test mode), copy the **secret key** (`sk_test_...`).
2. Deploy the functions and set their secrets:
   ```bash
   supabase functions deploy create-order notify-ready stripe-webhook
   supabase secrets set STRIPE_SECRET_KEY=sk_test_... \
     APP_URL=https://YOUR-VERCEL-URL \
     ALLOWED_ORIGINS=https://YOUR-VERCEL-URL,http://localhost:5173
   ```
3. Developers → Webhooks → *Add endpoint*:
   - URL: `https://YOUR-PROJECT-REF.supabase.co/functions/v1/stripe-webhook`
   - Events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.expired`, `charge.refunded`
   - Copy its signing secret: `supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...`
4. **Stripe Connect (to collect the 4% automatically):** once Aryas' account is connected, add a second endpoint listening to **events on Connected accounts** with the same URL and events, set `STRIPE_CONNECT_WEBHOOK_SECRET`, and store his account id:
   ```sql
   update tenant_settings set stripe_account_id = 'acct_...' where tenant_id = (select id from tenants where slug = 'aryas');
   ```
   Without an account id, payments go to the platform's own Stripe account and the fee ledger marks the 4% as "invoice".

### 3. Email (optional for testing)

Create a [Resend](https://resend.com) API key and verify `aryascuisine.com` (add the DNS records it shows in InMotion). Then:
```bash
supabase secrets set RESEND_API_KEY=re_... EMAIL_FROM="Aryas Cuisine <orders@aryascuisine.com>"
```
Without it, emails are skipped and logged in the function logs.

### 4. Vercel (the app)

1. In the **cloud-kitchen4** team: *Add New → Project → Import* `venkiman70/Cloud-Kitchen`. Framework preset: **Vite** (build `npm run build`, output `dist`).
2. Environment variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_DEFAULT_TENANT=aryas`. Deploy.
3. Custom domain later: add `order.aryascuisine.com` in Vercel, then in InMotion cPanel → Zone Editor add a **CNAME** `order` → `cname.vercel-dns.com`. Add the domain to `ALLOWED_ORIGINS`, `APP_URL` and Supabase redirect URLs.

### 5. Try it

1. Open the Vercel URL on a phone → **AHIL** → add sweets → checkout → pick a Diwali date → pay with test card **4242 4242 4242 4242**, any future date, any CVC.
2. You land on the order status page. Sign in at `/admin` on a tablet: the order is on the board with a chime. Tap **Start preparing → Mark ready → Picked up**.
3. Refund it from the Stripe dashboard; the order flips to Refunded.

### Run locally

```bash
cp .env.example .env.local   # fill in the two VITE_ values
npm install
npm run dev                  # http://localhost:5173/?tenant=aryas
```

Database tests against a local Postgres 15+ (no Docker needed):
```bash
psql -d test -f supabase/tests/_local_supabase_shim.sql
for f in supabase/migrations/*.sql supabase/seed.sql; do psql -d test -f "$f"; done
psql -d test -f supabase/tests/rls_and_orders_test.sql   # → ALL TESTS PASSED
```

---

## Project layout

```
src/
  pages/Home, Menu, Checkout, OrderStatus      customer screens
  pages/admin/Board, Prep, MenuAdmin, Sales    staff screens (Board also powers /kitchen)
  lib/store.tsx    tenant + brand resolution, theme, cart, remembered customer details
  lib/time.ts      pickup slots in the store's time zone
supabase/
  migrations/      schema, RLS policies, business functions
  functions/       create-order, stripe-webhook, notify-ready (+ _shared)
  seed.sql         Aryas tenant, brands, sample menu, AHIL Diwali 2026
  tests/           RLS + order flow test
```

## Assumptions (change in `tenant_settings` / seed without code)

- Pickup hours 11:00–21:00 every day; 20-minute lead time; 15-minute slots with max 4 orders each. Raise `slot_capacity` for Diwali.
- Sales tax 8.25% (confirm with the accountant). Tips off.
- AHIL Diwali 2026: order cutoff Thu 5 Nov 11:59 pm CT; pickup 6–8 Nov.
- Aryas dishes are **sample** items until the real menu arrives; AHIL prices are from the flyer; allergens are inferred.
- Platform fee 4% of food subtotal after discounts, excluding tax, tips and marketplace orders; no monthly minimum.
- Guest checkout only; customers are matched by mobile number. No card data is stored.

## Not built yet (next)

Full product editor in admin (add items, photos, variants); walk-in/phone order entry and barcode scan-to-cart; WhatsApp paste-and-parse; promo codes and BOGO; loyalty; catering quotes and deposits; platform console; Stripe Connect onboarding screen; monthly fee statements; rate limiting on create-order.
