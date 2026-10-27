-- ONE-TIME SETUP: paste this whole file into Supabase → SQL Editor → Run.
-- It is the three files in supabase/migrations plus supabase/seed.sql, in order.
-- Run it only once, on a new, empty project.

-- ===== supabase/migrations/20261026000001_init.sql =====
-- KitchenOS initial schema: multi-tenant, multi-brand ordering platform.
-- Every business table carries tenant_id and is protected by RLS.
-- Money is stored as integer cents. All pricing happens in create_order().

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.member_role    as enum ('owner', 'manager', 'kitchen_staff');
create type public.diet_type      as enum ('veg', 'egg', 'non_veg');
create type public.order_channel  as enum ('web', 'whatsapp', 'phone', 'walk_in', 'doordash', 'ubereats', 'catering');
create type public.fulfilment_type as enum ('pickup', 'delivery', 'shipping');
create type public.order_status   as enum ('pending_payment', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled', 'refunded');
create type public.pay_status     as enum ('unpaid', 'paid', 'partially_refunded', 'refunded', 'failed');
create type public.pay_method     as enum ('stripe', 'cash', 'external');

-- ---------------------------------------------------------------------------
-- Platform
-- ---------------------------------------------------------------------------
create table public.tenants (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name        text not null,
  status      text not null default 'active' check (status in ('active', 'suspended')),
  created_at  timestamptz not null default now()
);

create table public.tenant_domains (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  domain     text not null unique
);

create table public.tenant_settings (
  tenant_id            uuid primary key references public.tenants(id) on delete cascade,
  timezone             text not null default 'America/Chicago',
  currency             text not null default 'usd',
  tax_rate_bps         int  not null default 825 check (tax_rate_bps between 0 and 3000),
  lead_time_minutes    int  not null default 20,
  slot_minutes         int  not null default 15,
  slot_capacity        int  not null default 4,
  -- {"mon": ["11:00","21:00"], "tue": null, ...}; null = closed that day
  pickup_hours         jsonb not null default '{}'::jsonb,
  address              text,
  phone                text,
  whatsapp             text,
  pickup_instructions  text,
  pay_at_pickup        boolean not null default false,
  platform_fee_bps     int  not null default 0 check (platform_fee_bps between 0 and 3000),
  stripe_account_id    text,
  updated_at           timestamptz not null default now()
);

create table public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table public.brands (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  slug         text not null check (slug ~ '^[a-z0-9-]{2,40}$'),
  name         text not null,
  tagline      text,
  -- {"accent": "#2f6b3a", "accentInk": "#ffffff", "logoUrl": "..."}
  theme        jsonb not null default '{}'::jsonb,
  order_prefix text not null default 'OR' check (order_prefix ~ '^[A-Z]{1,4}$'),
  sort         int  not null default 0,
  is_active    boolean not null default true,
  unique (tenant_id, slug)
);

create table public.tenant_members (
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       public.member_role not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

-- ---------------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------------
create table public.customers (
  id                         uuid primary key default gen_random_uuid(),
  tenant_id                  uuid not null references public.tenants(id) on delete cascade,
  phone                      text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  email                      text,
  name                       text,
  marketing_opt_in_email     boolean not null default false,
  marketing_opt_in_sms       boolean not null default false,
  marketing_opt_in_whatsapp  boolean not null default false,
  notes                      text,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  unique (tenant_id, phone)
);

create table public.consents (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  customer_id  uuid not null references public.customers(id) on delete cascade,
  channel      text not null check (channel in ('email', 'sms', 'whatsapp')),
  granted      boolean not null,
  source       text not null,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------
create table public.menu_categories (
  id         uuid primary key default gen_random_uuid(),
  tenant_id  uuid not null references public.tenants(id) on delete cascade,
  brand_id   uuid not null references public.brands(id) on delete cascade,
  name       text not null,
  sort       int  not null default 0,
  unique (brand_id, name)
);

create table public.menu_collections (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null references public.tenants(id) on delete cascade,
  brand_id         uuid not null references public.brands(id) on delete cascade,
  slug             text not null,
  name             text not null,
  starts_at        timestamptz,
  ends_at          timestamptz,
  order_cutoff_at  timestamptz,
  pickup_dates     date[],
  is_preorder      boolean not null default true,
  unique (brand_id, slug)
);

create table public.menu_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete cascade,
  brand_id          uuid not null references public.brands(id) on delete cascade,
  category_id       uuid references public.menu_categories(id) on delete set null,
  collection_id     uuid references public.menu_collections(id) on delete set null,
  name              text not null,
  description       text,
  diet              public.diet_type not null default 'veg',
  protein           text check (protein in ('chicken', 'goat', 'lamb', 'fish', 'shrimp', 'egg')),
  spice             smallint not null default 0 check (spice between 0 and 3),
  allergens         text[] not null default '{}',
  is_vegan          boolean not null default false,
  is_jain           boolean not null default false,
  image_url         text,
  is_available      boolean not null default true,
  daily_limit       int check (daily_limit is null or daily_limit >= 0),
  prep_minutes      int,
  station           text,
  is_catering_only  boolean not null default false,
  is_sample         boolean not null default false,
  sort              int not null default 0,
  deleted_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint veg_has_no_protein check (diet <> 'veg' or protein is null),
  constraint nonveg_needs_protein check (diet <> 'non_veg' or protein is not null)
);
create index on public.menu_items (tenant_id, brand_id) where deleted_at is null;

create table public.item_variants (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  item_id      uuid not null references public.menu_items(id) on delete cascade,
  label        text not null,
  pack_qty     numeric(10,3),
  pack_unit    text check (pack_unit in ('each', 'pcs', 'nos', 'plate', 'cup', 'kg', 'g', 'half tray', 'full tray')),
  price_cents  int not null check (price_cents >= 0),
  barcode      text,
  sort         int not null default 0,
  deleted_at   timestamptz,
  unique (tenant_id, barcode)
);
create index on public.item_variants (item_id) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------------
create table public.order_counters (
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  prefix      text not null,
  next_number int  not null default 1001,
  primary key (tenant_id, prefix)
);

create table public.orders (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.tenants(id) on delete cascade,
  brand_id                    uuid not null references public.brands(id),
  order_number                text not null,
  channel                     public.order_channel not null default 'web',
  fulfilment                  public.fulfilment_type not null default 'pickup',
  status                      public.order_status not null default 'pending_payment',
  payment_status              public.pay_status not null default 'unpaid',
  customer_id                 uuid references public.customers(id),
  customer_name               text,
  customer_phone              text,
  customer_email              text,
  pickup_at                   timestamptz not null,
  subtotal_cents              int not null,
  discount_cents              int not null default 0,
  tax_cents                   int not null,
  tip_cents                   int not null default 0,
  total_cents                 int not null,
  platform_fee_cents          int not null default 0,
  notes                       text,
  public_token                uuid not null unique default gen_random_uuid(),
  stripe_account_id           text,
  stripe_checkout_session_id  text unique,
  stripe_payment_intent_id    text,
  paid_at                     timestamptz,
  receipt_sent_at             timestamptz,
  ready_notified_at           timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  unique (tenant_id, order_number)
);
create index on public.orders (tenant_id, pickup_at);
create index on public.orders (tenant_id, status);

create table public.order_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.tenants(id) on delete cascade,
  order_id          uuid not null references public.orders(id) on delete cascade,
  item_id           uuid references public.menu_items(id),
  variant_id        uuid references public.item_variants(id),
  item_name         text not null,     -- copied at order time; menu edits never change past orders
  variant_label     text,
  diet              public.diet_type not null,
  station           text,
  unit_price_cents  int not null,
  quantity          int not null check (quantity between 1 and 100),
  line_total_cents  int not null
);
create index on public.order_items (order_id);

create table public.order_status_events (
  id           bigint generated always as identity primary key,
  tenant_id    uuid not null references public.tenants(id) on delete cascade,
  order_id     uuid not null references public.orders(id) on delete cascade,
  from_status  public.order_status,
  to_status    public.order_status not null,
  actor        uuid,
  created_at   timestamptz not null default now()
);

-- Money-free signal row per order, so kitchen screens can subscribe to Realtime
-- without being able to read prices or customer contact details.
create table public.order_signals (
  order_id    uuid primary key references public.orders(id) on delete cascade,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  status      public.order_status not null,
  changed_at  timestamptz not null default now()
);

create table public.payments (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.tenants(id) on delete cascade,
  order_id                  uuid not null references public.orders(id) on delete cascade,
  method                    public.pay_method not null,
  amount_cents              int not null,
  refunded_cents            int not null default 0,
  stripe_payment_intent_id  text unique,
  created_at                timestamptz not null default now()
);

create table public.platform_fee_ledger (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants(id) on delete cascade,
  order_id        uuid not null unique references public.orders(id) on delete cascade,
  fee_base_cents  int not null,
  fee_cents       int not null,
  collected_via   text not null check (collected_via in ('stripe', 'invoice')),
  period          date not null,
  reversed_cents  int not null default 0,
  created_at      timestamptz not null default now()
);

create table public.stripe_events (
  id           text primary key,
  type         text not null,
  received_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from platform_admins where user_id = auth.uid());
$$;

create or replace function public.auth_tenant_role(t uuid)
returns public.member_role language sql stable security definer set search_path = public as $$
  select role from tenant_members where tenant_id = t and user_id = auth.uid();
$$;

create or replace function public.is_staff(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.auth_tenant_role(t) is not null or public.is_platform_admin();
$$;

create or replace function public.is_manager(t uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.auth_tenant_role(t) in ('owner', 'manager') or public.is_platform_admin();
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger trg_items_touch    before update on public.menu_items     for each row execute function public.touch_updated_at();
create trigger trg_orders_touch   before update on public.orders         for each row execute function public.touch_updated_at();
create trigger trg_customers_touch before update on public.customers     for each row execute function public.touch_updated_at();
create trigger trg_settings_touch before update on public.tenant_settings for each row execute function public.touch_updated_at();

-- Keep order_signals in step with orders
create or replace function public.sync_order_signal()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into order_signals (order_id, tenant_id, status, changed_at)
  values (new.id, new.tenant_id, new.status, now())
  on conflict (order_id) do update set status = excluded.status, changed_at = now();
  return new;
end $$;
create trigger trg_orders_signal after insert or update of status, payment_status on public.orders
  for each row execute function public.sync_order_signal();

-- Normalise a US-style phone to E.164
create or replace function public.normalize_phone(p text)
returns text language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '[^0-9+]', '', 'g');
begin
  if d like '+%' then return d; end if;
  d := regexp_replace(d, '[^0-9]', '', 'g');
  if length(d) = 10 then return '+1' || d; end if;
  if length(d) = 11 and left(d, 1) = '1' then return '+' || d; end if;
  return null;
end $$;

-- ===== supabase/migrations/20261026000002_rls.sql =====
-- Row Level Security. Default deny; each policy opens exactly what a role needs.
--   anon / customers : published menu + brands only (settings via storefront_config()).
--   kitchen_staff    : order_signals + RPCs that return money-free order data.
--   owner / manager  : full read/write on their tenant.
--   super_admin      : everything (platform_admins).
-- Orders are created only by create_order() (service role), never by direct insert.

alter table public.tenants             enable row level security;
alter table public.tenant_domains      enable row level security;
alter table public.tenant_settings     enable row level security;
alter table public.platform_admins     enable row level security;
alter table public.brands              enable row level security;
alter table public.tenant_members      enable row level security;
alter table public.customers           enable row level security;
alter table public.consents            enable row level security;
alter table public.menu_categories     enable row level security;
alter table public.menu_collections    enable row level security;
alter table public.menu_items          enable row level security;
alter table public.item_variants       enable row level security;
alter table public.order_counters      enable row level security;
alter table public.orders              enable row level security;
alter table public.order_items         enable row level security;
alter table public.order_status_events enable row level security;
alter table public.order_signals       enable row level security;
alter table public.payments            enable row level security;
alter table public.platform_fee_ledger enable row level security;
alter table public.stripe_events       enable row level security;

-- Platform ------------------------------------------------------------------
create policy tenants_public_read on public.tenants
  for select to anon, authenticated using (status = 'active' or public.is_staff(id));
create policy tenants_admin_write on public.tenants
  for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy domains_public_read on public.tenant_domains
  for select to anon, authenticated using (true);
create policy domains_admin_write on public.tenant_domains
  for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy settings_manager_read on public.tenant_settings
  for select to authenticated using (public.is_manager(tenant_id));
create policy settings_manager_update on public.tenant_settings
  for update to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));
create policy settings_admin_all on public.tenant_settings
  for all to authenticated using (public.is_platform_admin()) with check (public.is_platform_admin());
-- Managers may not change their own platform fee or Stripe account: column grants.
revoke update on public.tenant_settings from authenticated;
grant update (timezone, tax_rate_bps, lead_time_minutes, slot_minutes, slot_capacity, pickup_hours,
              address, phone, whatsapp, pickup_instructions, pay_at_pickup)
  on public.tenant_settings to authenticated;

create policy platform_admins_self on public.platform_admins
  for select to authenticated using (user_id = auth.uid());

create policy brands_public_read on public.brands
  for select to anon, authenticated using (is_active or public.is_staff(tenant_id));
create policy brands_manager_write on public.brands
  for all to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));

create policy members_read on public.tenant_members
  for select to authenticated using (user_id = auth.uid() or public.is_manager(tenant_id));
create policy members_owner_write on public.tenant_members
  for all to authenticated
  using (public.auth_tenant_role(tenant_id) = 'owner' or public.is_platform_admin())
  with check (public.auth_tenant_role(tenant_id) = 'owner' or public.is_platform_admin());

-- People --------------------------------------------------------------------
create policy customers_manager_all on public.customers
  for all to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));
create policy consents_manager_read on public.consents
  for select to authenticated using (public.is_manager(tenant_id));

-- Menu ----------------------------------------------------------------------
create policy categories_public_read on public.menu_categories
  for select to anon, authenticated using (true);
create policy categories_manager_write on public.menu_categories
  for all to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));

create policy collections_public_read on public.menu_collections
  for select to anon, authenticated using (true);
create policy collections_manager_write on public.menu_collections
  for all to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));

create policy items_public_read on public.menu_items
  for select to anon, authenticated using (deleted_at is null or public.is_staff(tenant_id));
create policy items_manager_write on public.menu_items
  for all to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));

create policy variants_public_read on public.item_variants
  for select to anon, authenticated using (deleted_at is null or public.is_staff(tenant_id));
create policy variants_manager_write on public.item_variants
  for all to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));

-- Orders --------------------------------------------------------------------
-- Full order rows (money, contact details) are for managers only.
create policy orders_manager_read on public.orders
  for select to authenticated using (public.is_manager(tenant_id));
create policy orders_manager_update on public.orders
  for update to authenticated using (public.is_manager(tenant_id)) with check (public.is_manager(tenant_id));

create policy order_items_manager_read on public.order_items
  for select to authenticated using (public.is_manager(tenant_id));

create policy status_events_manager_read on public.order_status_events
  for select to authenticated using (public.is_manager(tenant_id));

-- Kitchen staff (and managers) see only the money-free signal stream.
create policy signals_staff_read on public.order_signals
  for select to authenticated using (public.is_staff(tenant_id));

create policy payments_manager_read on public.payments
  for select to authenticated using (public.is_manager(tenant_id));

create policy fee_ledger_read on public.platform_fee_ledger
  for select to authenticated using (public.is_manager(tenant_id));

-- order_counters and stripe_events: no policies -> only security-definer
-- functions and the service role touch them.

-- ===== supabase/migrations/20261026000003_functions.sql =====
-- Server-side business logic. Prices, tax, limits and fees are computed here,
-- never in the browser.

-- ---------------------------------------------------------------------------
-- Storefront: public config for one tenant (by slug or by host name)
-- ---------------------------------------------------------------------------
create or replace function public.storefront_config(p_tenant text default null, p_host text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  t tenants;
  s tenant_settings;
begin
  if p_tenant is not null then
    select * into t from tenants where slug = lower(p_tenant) and status = 'active';
  elsif p_host is not null then
    select tn.* into t from tenants tn join tenant_domains d on d.tenant_id = tn.id
     where d.domain = lower(p_host) and tn.status = 'active';
  end if;
  if t.id is null then return null; end if;
  select * into s from tenant_settings where tenant_id = t.id;

  return jsonb_build_object(
    'tenant', jsonb_build_object('id', t.id, 'slug', t.slug, 'name', t.name),
    'settings', jsonb_build_object(
      'timezone', s.timezone, 'currency', s.currency, 'taxRateBps', s.tax_rate_bps,
      'leadTimeMinutes', s.lead_time_minutes, 'slotMinutes', s.slot_minutes,
      'pickupHours', s.pickup_hours, 'address', s.address, 'phone', s.phone,
      'whatsapp', s.whatsapp, 'pickupInstructions', s.pickup_instructions,
      'payAtPickup', s.pay_at_pickup),
    'brands', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'slug', b.slug, 'name', b.name, 'tagline', b.tagline, 'theme', b.theme)
        order by b.sort) from brands b where b.tenant_id = t.id and b.is_active), '[]'::jsonb),
    'collections', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'brandId', c.brand_id, 'slug', c.slug, 'name', c.name,
        'orderCutoffAt', c.order_cutoff_at, 'pickupDates', c.pickup_dates, 'isPreorder', c.is_preorder))
        from menu_collections c where c.tenant_id = t.id
         and (c.ends_at is null or c.ends_at > now())), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------------
-- create_order: the only way an order is created (called by the create-order
-- edge function with the service role). Raises errors whose message starts with
-- a stable CODE: the edge function maps codes to customer-friendly text.
-- p = {
--   tenant: "aryas", brand: "ahil", channel: "web",
--   pickupAt: "2026-11-07T17:00:00Z", notes: "...",
--   customer: {name, phone, email, optInEmail, optInSms},
--   items: [{variantId, quantity}]
-- }
-- ---------------------------------------------------------------------------
create or replace function public.create_order(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t            tenants;
  s            tenant_settings;
  b            brands;
  v_pickup     timestamptz;
  v_local      timestamp;
  v_day        text;
  v_hours      jsonb;
  v_phone      text;
  v_name       text;
  v_email      text;
  v_customer   uuid;
  v_order      uuid;
  v_number     int;
  v_subtotal   int := 0;
  v_tax        int;
  v_fee        int;
  v_slot_count int;
  v_has_preorder boolean := false;
  v_line       record;
  v_lines      jsonb := '[]'::jsonb;
  v_used       int;
  v_channel    order_channel := coalesce(nullif(p->>'channel', ''), 'web')::order_channel;
begin
  select * into t from tenants where slug = p->>'tenant' and status = 'active';
  if t.id is null then raise exception 'TENANT_NOT_FOUND'; end if;
  select * into s from tenant_settings where tenant_id = t.id;
  select * into b from brands where tenant_id = t.id and slug = p->>'brand' and is_active;
  if b.id is null then raise exception 'BRAND_NOT_FOUND'; end if;

  -- One order at a time per tenant, so limits and slot counts can't race.
  perform pg_advisory_xact_lock(hashtext(t.id::text));

  -- Customer details
  v_name  := nullif(trim(p->'customer'->>'name'), '');
  v_phone := public.normalize_phone(p->'customer'->>'phone');
  v_email := nullif(lower(trim(p->'customer'->>'email')), '');
  if v_name is null then raise exception 'NAME_REQUIRED'; end if;
  if v_phone is null or v_phone !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'BAD_PHONE'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'BAD_EMAIL'; end if;

  -- Items: resolve every variant against the live menu
  if jsonb_typeof(p->'items') <> 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'CART_EMPTY';
  end if;
  if jsonb_array_length(p->'items') > 40 then raise exception 'CART_TOO_LARGE'; end if;

  drop table if exists _lines;
  create temp table _lines on commit drop as
  select v.id as variant_id, i.id as item_id, i.name as item_name, v.label as variant_label,
         i.diet, i.station, v.price_cents, i.daily_limit, i.is_available, i.is_catering_only,
         i.collection_id, sum((x->>'quantity')::int)::int as quantity
    from jsonb_array_elements(p->'items') x
    left join item_variants v on v.id = (x->>'variantId')::uuid and v.tenant_id = t.id and v.deleted_at is null
    left join menu_items i on i.id = v.item_id and i.deleted_at is null and i.brand_id = b.id
   group by v.id, i.id, i.name, v.label, i.diet, i.station, v.price_cents, i.daily_limit,
            i.is_available, i.is_catering_only, i.collection_id;

  if exists (select 1 from _lines where item_id is null) then raise exception 'ITEM_NOT_FOUND'; end if;
  if exists (select 1 from _lines where quantity is null or quantity < 1 or quantity > 100) then
    raise exception 'BAD_QUANTITY';
  end if;
  select item_name into v_name from _lines where not is_available or is_catering_only limit 1;
  if found then raise exception 'ITEM_SOLD_OUT:%', v_name; end if;
  v_name := nullif(trim(p->'customer'->>'name'), '');

  -- Pickup time
  begin
    v_pickup := (p->>'pickupAt')::timestamptz;
  exception when others then raise exception 'BAD_PICKUP_TIME';
  end;
  if v_pickup is null then raise exception 'BAD_PICKUP_TIME'; end if;
  v_local := v_pickup at time zone s.timezone;
  select exists (select 1 from _lines where collection_id is not null) into v_has_preorder;

  if v_pickup < now() + make_interval(mins => s.lead_time_minutes) - interval '2 minutes' then
    raise exception 'PICKUP_TOO_SOON';
  end if;
  if v_pickup > now() + interval '45 days' then raise exception 'PICKUP_TOO_FAR'; end if;

  v_day := lower(to_char(v_local, 'dy'));
  if s.pickup_hours ? v_day then
    v_hours := s.pickup_hours -> v_day;
    if v_hours is null or jsonb_typeof(v_hours) = 'null' then raise exception 'CLOSED_THAT_DAY'; end if;
    if v_local::time < (v_hours->>0)::time or v_local::time > (v_hours->>1)::time then
      raise exception 'OUTSIDE_PICKUP_HOURS';
    end if;
  end if;

  -- Seasonal / pre-order collections
  for v_line in
    select c.* from menu_collections c where c.id in (select collection_id from _lines where collection_id is not null)
  loop
    if v_line.order_cutoff_at is not null and now() > v_line.order_cutoff_at then
      raise exception 'COLLECTION_CLOSED:%', v_line.name;
    end if;
    if v_line.pickup_dates is not null and not (v_local::date = any (v_line.pickup_dates)) then
      raise exception 'PICKUP_DATE_NOT_ALLOWED:%', v_line.name;
    end if;
  end loop;

  -- Kitchen capacity per pickup slot
  select count(*) into v_slot_count from orders o
   where o.tenant_id = t.id
     and o.status not in ('cancelled', 'refunded')
     and (o.status <> 'pending_payment' or o.created_at > now() - interval '35 minutes')
     and date_bin(make_interval(mins => s.slot_minutes), o.pickup_at, timestamptz '2000-01-01')
       = date_bin(make_interval(mins => s.slot_minutes), v_pickup, timestamptz '2000-01-01');
  if v_slot_count >= s.slot_capacity then raise exception 'SLOT_FULL'; end if;

  -- Daily limits (per local pickup date)
  for v_line in select * from _lines where daily_limit is not null loop
    select coalesce(sum(oi.quantity), 0) into v_used
      from order_items oi join orders o on o.id = oi.order_id
     where oi.item_id = v_line.item_id
       and o.status not in ('cancelled', 'refunded')
       and (o.status <> 'pending_payment' or o.created_at > now() - interval '35 minutes')
       and (o.pickup_at at time zone s.timezone)::date = v_local::date;
    if v_used + v_line.quantity > v_line.daily_limit then
      raise exception 'LIMIT_REACHED:%', v_line.item_name;
    end if;
  end loop;

  -- Money (integer cents, half-up rounding)
  select coalesce(sum(price_cents * quantity), 0) into v_subtotal from _lines;
  v_tax := (v_subtotal * s.tax_rate_bps + 5000) / 10000;
  v_fee := (v_subtotal * s.platform_fee_bps + 5000) / 10000;

  -- Customer upsert by phone (consent is only ever granted here, never revoked)
  insert into customers (tenant_id, phone, email, name, marketing_opt_in_email, marketing_opt_in_sms)
  values (t.id, v_phone, v_email, v_name,
          coalesce((p->'customer'->>'optInEmail')::boolean, false),
          coalesce((p->'customer'->>'optInSms')::boolean, false))
  on conflict (tenant_id, phone) do update set
    name  = excluded.name,
    email = coalesce(excluded.email, customers.email),
    marketing_opt_in_email = customers.marketing_opt_in_email or excluded.marketing_opt_in_email,
    marketing_opt_in_sms   = customers.marketing_opt_in_sms   or excluded.marketing_opt_in_sms
  returning id into v_customer;

  if coalesce((p->'customer'->>'optInEmail')::boolean, false) then
    insert into consents (tenant_id, customer_id, channel, granted, source) values (t.id, v_customer, 'email', true, 'checkout');
  end if;
  if coalesce((p->'customer'->>'optInSms')::boolean, false) then
    insert into consents (tenant_id, customer_id, channel, granted, source) values (t.id, v_customer, 'sms', true, 'checkout');
  end if;

  -- Human-friendly order number per brand prefix: AC-1001, AH-1001, ...
  insert into order_counters (tenant_id, prefix, next_number) values (t.id, b.order_prefix, 1002)
  on conflict (tenant_id, prefix) do update set next_number = order_counters.next_number + 1
  returning next_number - 1 into v_number;

  insert into orders (tenant_id, brand_id, order_number, channel, fulfilment, status, payment_status,
                      customer_id, customer_name, customer_phone, customer_email, pickup_at,
                      subtotal_cents, tax_cents, total_cents, platform_fee_cents, notes, stripe_account_id)
  values (t.id, b.id, b.order_prefix || '-' || v_number, v_channel, 'pickup', 'pending_payment', 'unpaid',
          v_customer, v_name, v_phone, v_email, v_pickup,
          v_subtotal, v_tax, v_subtotal + v_tax, v_fee, nullif(trim(p->>'notes'), ''), s.stripe_account_id)
  returning id into v_order;

  insert into order_items (tenant_id, order_id, item_id, variant_id, item_name, variant_label, diet, station,
                           unit_price_cents, quantity, line_total_cents)
  select t.id, v_order, item_id, variant_id, item_name, variant_label, diet, station,
         price_cents, quantity, price_cents * quantity
    from _lines;

  insert into order_status_events (tenant_id, order_id, from_status, to_status) values (t.id, v_order, null, 'pending_payment');

  select jsonb_agg(jsonb_build_object('name', item_name || coalesce(' · ' || variant_label, ''),
                                      'unitAmount', price_cents, 'quantity', quantity))
    into v_lines from _lines;

  return (select jsonb_build_object(
    'orderId', o.id, 'orderNumber', o.order_number, 'publicToken', o.public_token,
    'brandSlug', b.slug, 'brandName', b.name, 'tenantName', t.name,
    'currency', s.currency, 'subtotalCents', o.subtotal_cents, 'taxCents', o.tax_cents,
    'totalCents', o.total_cents, 'platformFeeCents', o.platform_fee_cents,
    'stripeAccountId', o.stripe_account_id, 'customerEmail', o.customer_email,
    'lines', v_lines) from orders o where o.id = v_order);
end $$;

-- ---------------------------------------------------------------------------
-- Stripe webhook helpers (service role only)
-- ---------------------------------------------------------------------------
create or replace function public.mark_order_paid(p_session_id text, p_payment_intent text, p_amount_cents int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  o  orders;
  s  tenant_settings;
  already boolean := false;
begin
  select * into o from orders where stripe_checkout_session_id = p_session_id for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into s from tenant_settings where tenant_id = o.tenant_id;

  if o.payment_status = 'paid' then
    already := true;
  else
    if p_amount_cents is distinct from o.total_cents then
      raise warning 'Amount mismatch on %: paid %, expected %', o.order_number, p_amount_cents, o.total_cents;
    end if;
    update orders set payment_status = 'paid', paid_at = now(), stripe_payment_intent_id = p_payment_intent,
                      status = case when status in ('pending_payment', 'cancelled') then 'confirmed' else status end
     where id = o.id;
    insert into order_status_events (tenant_id, order_id, from_status, to_status)
      values (o.tenant_id, o.id, o.status, 'confirmed');
    insert into payments (tenant_id, order_id, method, amount_cents, stripe_payment_intent_id)
      values (o.tenant_id, o.id, 'stripe', coalesce(p_amount_cents, o.total_cents), p_payment_intent)
      on conflict (stripe_payment_intent_id) do nothing;
    insert into platform_fee_ledger (tenant_id, order_id, fee_base_cents, fee_cents, collected_via, period)
      values (o.tenant_id, o.id, o.subtotal_cents - o.discount_cents, o.platform_fee_cents,
              case when o.stripe_account_id is not null then 'stripe' else 'invoice' end,
              date_trunc('month', now() at time zone s.timezone)::date)
      on conflict (order_id) do nothing;
  end if;

  return public.order_receipt(o.id) || jsonb_build_object('alreadyPaid', already);
end $$;

create or replace function public.mark_order_refunded(p_payment_intent text, p_refunded_cents int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where stripe_payment_intent_id = p_payment_intent for update;
  if o.id is null then return jsonb_build_object('found', false); end if;
  update payments set refunded_cents = p_refunded_cents where stripe_payment_intent_id = p_payment_intent;
  update platform_fee_ledger
     set reversed_cents = case when o.total_cents > 0
                               then least(fee_cents, (fee_cents * p_refunded_cents + o.total_cents / 2) / o.total_cents)
                               else 0 end
   where order_id = o.id;
  if p_refunded_cents >= o.total_cents then
    update orders set payment_status = 'refunded', status = 'refunded' where id = o.id;
    insert into order_status_events (tenant_id, order_id, from_status, to_status) values (o.tenant_id, o.id, o.status, 'refunded');
  else
    update orders set payment_status = 'partially_refunded' where id = o.id;
  end if;
  return jsonb_build_object('found', true, 'orderNumber', o.order_number);
end $$;

create or replace function public.expire_pending_order(p_session_id text)
returns void language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where stripe_checkout_session_id = p_session_id for update;
  if o.id is not null and o.status = 'pending_payment' and o.payment_status = 'unpaid' then
    update orders set status = 'cancelled' where id = o.id;
    insert into order_status_events (tenant_id, order_id, from_status, to_status) values (o.tenant_id, o.id, o.status, 'cancelled');
  end if;
end $$;

-- Receipt payload used by emails and the webhook
create or replace function public.order_receipt(p_order uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'orderId', o.id, 'orderNumber', o.order_number, 'publicToken', o.public_token,
    'status', o.status, 'customerName', o.customer_name, 'customerEmail', o.customer_email,
    'pickupAt', o.pickup_at, 'timezone', s.timezone, 'currency', s.currency,
    'brandName', b.name, 'tenantName', t.name, 'address', s.address,
    'pickupInstructions', s.pickup_instructions,
    'subtotalCents', o.subtotal_cents, 'taxCents', o.tax_cents, 'totalCents', o.total_cents,
    'items', (select jsonb_agg(jsonb_build_object('name', oi.item_name, 'variant', oi.variant_label,
               'quantity', oi.quantity, 'lineTotalCents', oi.line_total_cents) order by oi.item_name)
              from order_items oi where oi.order_id = o.id))
  from orders o join brands b on b.id = o.brand_id join tenants t on t.id = o.tenant_id
  join tenant_settings s on s.tenant_id = o.tenant_id
  where o.id = p_order;
$$;

-- ---------------------------------------------------------------------------
-- Customer: order status page (the token in the link is the secret)
-- ---------------------------------------------------------------------------
create or replace function public.order_status_public(p_token uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select public.order_receipt(o.id) - 'customerEmail' - 'orderId'
         || jsonb_build_object('paymentStatus', o.payment_status,
                               'customerName', split_part(coalesce(o.customer_name, ''), ' ', 1))
    from orders o where o.public_token = p_token;
$$;

-- ---------------------------------------------------------------------------
-- Kitchen: money-free board, status changes, sold-out toggle, prep totals
-- ---------------------------------------------------------------------------
create or replace function public.kitchen_board(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff(p_tenant) then raise exception 'NOT_ALLOWED'; end if;
  return coalesce((
    select jsonb_agg(row order by (row->>'pickupAt'))
    from (
      select jsonb_build_object(
        'id', o.id, 'orderNumber', o.order_number, 'status', o.status, 'channel', o.channel,
        'brand', b.name, 'brandSlug', b.slug, 'pickupAt', o.pickup_at, 'createdAt', o.created_at,
        'paidAt', o.paid_at, 'firstName', split_part(coalesce(o.customer_name, ''), ' ', 1),
        'notes', o.notes,
        'items', (select jsonb_agg(jsonb_build_object('name', oi.item_name, 'variant', oi.variant_label,
                   'quantity', oi.quantity, 'diet', oi.diet, 'station', oi.station) order by oi.station, oi.item_name)
                  from order_items oi where oi.order_id = o.id)) as row
      from orders o join brands b on b.id = o.brand_id
      where o.tenant_id = p_tenant
        and (o.status in ('confirmed', 'preparing', 'ready')
             or (o.status = 'completed' and o.updated_at > now() - interval '12 hours'))
      order by o.pickup_at
      limit 300
    ) q), '[]'::jsonb);
end $$;

create or replace function public.advance_order(p_order uuid, p_to public.order_status)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o orders; ok boolean;
begin
  select * into o from orders where id = p_order for update;
  if o.id is null or not public.is_staff(o.tenant_id) then raise exception 'NOT_ALLOWED'; end if;
  ok := (o.status, p_to) in (('confirmed', 'preparing'), ('preparing', 'ready'), ('ready', 'completed'),
                             ('confirmed', 'ready'),
                             ('preparing', 'confirmed'), ('ready', 'preparing'), ('completed', 'ready'));
  if p_to = 'cancelled' and public.is_manager(o.tenant_id) and o.status not in ('completed', 'refunded') then
    ok := true;
  end if;
  if not ok then raise exception 'BAD_TRANSITION:% -> %', o.status, p_to; end if;
  update orders set status = p_to where id = o.id;
  insert into order_status_events (tenant_id, order_id, from_status, to_status, actor)
    values (o.tenant_id, o.id, o.status, p_to, auth.uid());
  return jsonb_build_object('orderId', o.id, 'orderNumber', o.order_number, 'from', o.status, 'to', p_to);
end $$;

create or replace function public.set_item_availability(p_item uuid, p_available boolean)
returns void language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select tenant_id into t from menu_items where id = p_item;
  if t is null or not public.is_staff(t) then raise exception 'NOT_ALLOWED'; end if;
  update menu_items set is_available = p_available where id = p_item;
end $$;

create or replace function public.prep_totals(p_tenant uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare tz text;
begin
  if not public.is_staff(p_tenant) then raise exception 'NOT_ALLOWED'; end if;
  select timezone into tz from tenant_settings where tenant_id = p_tenant;
  return coalesce((
    select jsonb_agg(jsonb_build_object('name', item_name, 'variant', variant_label, 'brand', brand,
                                        'quantity', qty, 'orders', n) order by brand, item_name, variant_label)
    from (
      select oi.item_name, oi.variant_label, b.name as brand, sum(oi.quantity)::int as qty, count(distinct o.id)::int as n
        from order_items oi join orders o on o.id = oi.order_id join brands b on b.id = o.brand_id
       where o.tenant_id = p_tenant
         and o.status in ('confirmed', 'preparing', 'ready', 'completed')
         and (o.pickup_at at time zone tz)::date = p_date
       group by oi.item_name, oi.variant_label, b.name
    ) q), '[]'::jsonb);
end $$;

-- My memberships (for the admin app to pick a tenant after login)
create or replace function public.my_tenants()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('tenantId', t.id, 'slug', t.slug, 'name', t.name,
                                               'role', coalesce(m.role::text, 'super_admin'),
                                               'timezone', coalesce(s.timezone, 'America/Chicago'),
                                               'currency', coalesce(s.currency, 'usd')) order by t.name), '[]'::jsonb)
    from tenants t left join tenant_members m on m.tenant_id = t.id and m.user_id = auth.uid()
    left join tenant_settings s on s.tenant_id = t.id
   where m.user_id is not null or public.is_platform_admin();
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.storefront_config(text, text)   to anon, authenticated;
grant execute on function public.order_status_public(uuid)       to anon, authenticated;
grant execute on function public.kitchen_board(uuid)             to authenticated;
grant execute on function public.advance_order(uuid, public.order_status) to authenticated;
grant execute on function public.set_item_availability(uuid, boolean)     to authenticated;
grant execute on function public.prep_totals(uuid, date)         to authenticated;
grant execute on function public.my_tenants()                    to authenticated;
-- RLS helpers are evaluated inside policies for signed-in users
grant execute on function public.is_platform_admin()  to anon, authenticated;
grant execute on function public.auth_tenant_role(uuid) to anon, authenticated;
grant execute on function public.is_staff(uuid)        to anon, authenticated;
grant execute on function public.is_manager(uuid)      to anon, authenticated;
grant execute on function public.normalize_phone(text) to anon, authenticated;

grant execute on function public.create_order(jsonb)                   to service_role;
grant execute on function public.mark_order_paid(text, text, int)      to service_role;
grant execute on function public.mark_order_refunded(text, int)        to service_role;
grant execute on function public.expire_pending_order(text)            to service_role;
grant execute on function public.order_receipt(uuid)                   to service_role;

-- Realtime: kitchen screens subscribe to order_signals (money-free)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.order_signals;
    alter publication supabase_realtime add table public.menu_items;
  end if;
end $$;

-- ===== supabase/seed.sql =====
-- Seed: Aryas Cuisine tenant with two brands (Aryas, AHIL).
-- Generated from the Menu Manager prototype data on 2026-10-26.
-- Aryas dishes are SAMPLE items (is_sample = true) until the real menu arrives;
-- AHIL Diwali items and prices come from the 2026 Diwali flyer. Allergens are inferred: confirm with the owner.

insert into public.tenants (id, slug, name) values ('0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'aryas', 'Aryas Cuisine') on conflict do nothing;
insert into public.tenant_domains (tenant_id, domain) values ('0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'order.aryascuisine.com') on conflict do nothing;
insert into public.tenant_settings (tenant_id, timezone, currency, tax_rate_bps, lead_time_minutes, slot_minutes, slot_capacity,
  pickup_hours, address, phone, whatsapp, pickup_instructions, pay_at_pickup, platform_fee_bps)
values ('0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'America/Chicago', 'usd', 825, 20, 15, 4, '{"mon": ["11:00", "21:00"], "tue": ["11:00", "21:00"], "wed": ["11:00", "21:00"], "thu": ["11:00", "21:00"], "fri": ["11:00", "21:00"], "sat": ["11:00", "21:00"], "sun": ["11:00", "21:00"]}'::jsonb,
  '2526 Manana Dr, Suite 104, Dallas, TX', '+19459541827', '+19459541827',
  'Pickup at Suite 104. Call or WhatsApp +1 945 954 1827 when you arrive.', false, 400)
on conflict (tenant_id) do nothing;
insert into public.brands (id, tenant_id, slug, name, tagline, theme, order_prefix, sort) values
  ('25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'aryas', 'Aryas Cuisine', 'Indian soul food, made with love', '{"accent":"#7A2318","accentInk":"#FFF8EC","accentDark":"#F08A3C","accentInkDark":"#1E1410","logo":"/brand/aryas-lockup.svg","logoStacked":"/brand/aryas-logo.svg"}', 'AC', 1),
  ('0bc8d28a-dd02-5760-89c1-4af7fc872363', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'ahil', 'AHIL', 'Bringing joy in every bite', '{"accent":"#2463B5","accentInk":"#FFFFFF","accentDark":"#7FB2F0","accentInkDark":"#0E1D33","logo":"/brand/ahil-lockup.svg","logoStacked":"/brand/ahil-logo.svg"}', 'AH', 2)
on conflict do nothing;
insert into public.menu_collections (id, tenant_id, brand_id, slug, name, ends_at, order_cutoff_at, pickup_dates, is_preorder)
values ('637cc9dd-c666-5ccf-9cbb-5f3ff5279d04', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', 'diwali-2026', 'Diwali 2026 pre-orders', '2026-11-09 00:00:00-06',
        '2026-11-05 23:59:00-06', array['2026-11-06','2026-11-07','2026-11-08']::date[], true)
on conflict do nothing;

insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('1438d090-af46-56e0-b273-1e4d55b13c60', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', 'Diwali Sweets', 0) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('205b01ca-d6a4-5853-905d-6eb2913e04fb', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', 'Diwali Savouries', 1) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('cbfb59c1-a0ab-5046-820b-e7e0621d5f5d', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'Dosas', 0) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('4296edb5-1481-51e0-b257-101b10f71eb1', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'Idli & Vada', 1) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('997488f9-e0a2-5826-9ff7-ae61afe58ce5', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'Biryani', 3) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('a196b83c-56fb-53ec-a426-b9fe265e46ff', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'Chettinad & Non-Veg Specials', 4) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('5b111240-7a56-557a-9527-310398cd47d7', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'North Indian Curries', 5) on conflict do nothing;
insert into public.menu_categories (id, tenant_id, brand_id, name, sort) values ('182df791-1e01-5764-9c79-28e54f223d0d', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'Beverages', 9) on conflict do nothing;

insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('c15d95bb-0ff7-51c2-aeca-c8d21e092073', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Almond Halwa', null, 'veg', null, 0, array['nuts','dairy']::text[], true, 'Sweets', false, 8) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('2c75742f-f17b-50f3-9e95-7c8c7870644e', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'c15d95bb-0ff7-51c2-aeca-c8d21e092073', '1 kg', 1, 'kg', 7500, 'AH-ALMOND-HALWA-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('8db5fa90-47c7-5b8e-b282-b06b8eba3dc7', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Besan Ladoo', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 2) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('d91af990-8ea8-55a2-8d52-68ce40ede8da', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '8db5fa90-47c7-5b8e-b282-b06b8eba3dc7', '25 pcs', 25, 'pcs', 2500, 'AH-BESAN-LADOO-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('dd3fd5eb-6bab-5157-86ba-a64159600c63', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Boondhi Ladoo', null, 'veg', null, 0, '{}'::text[], true, 'Sweets', false, 1) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('38ac1fe3-dcca-5173-9e88-b5f746124f61', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'dd3fd5eb-6bab-5157-86ba-a64159600c63', '25 pcs', 25, 'pcs', 2500, 'AH-BOONDHI-LADOO-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('866a7ab3-e92a-50d4-af03-e8c19745248c', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Coconut Barfi', null, 'veg', null, 0, '{}'::text[], true, 'Sweets', false, 5) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('a657faff-5c7e-5c4b-8b3b-b00ed6011e9d', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '866a7ab3-e92a-50d4-af03-e8c19745248c', '25 pcs', 25, 'pcs', 2500, 'AH-COCONUT-BARFI-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('c9549065-887b-5666-8a80-484f9385d761', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Dates & Nut Cake', null, 'veg', null, 0, array['nuts']::text[], true, 'Sweets', false, 3) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('9612f089-dbe1-5968-8094-6bac82d8b94c', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'c9549065-887b-5666-8a80-484f9385d761', '17 pcs', 17, 'pcs', 2500, 'AH-DATES-NUT-CAKE-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('4ddedfc3-40f6-51ef-aba9-3f8d3689eef0', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Ghee Adhirasam (big size)', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 11) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('788b38fc-b581-581c-b0f7-002fdea3695a', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '4ddedfc3-40f6-51ef-aba9-3f8d3689eef0', '20 nos', 20, 'nos', 2500, 'AH-GHEE-ADHIRASAM-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('83325950-1a80-567a-9ca0-b806d06e3421', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '205b01ca-d6a4-5853-905d-6eb2913e04fb', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Karasev', null, 'veg', null, 1, '{}'::text[], true, 'Fryer/Snacks', false, 2) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('7f4511f6-be35-50b3-a9f5-f8fc08ea01c9', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '83325950-1a80-567a-9ca0-b806d06e3421', '1 kg', 1, 'kg', 2500, 'AH-KARASEV-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('1a442270-c537-5fb4-90c6-650719c7e63e', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '205b01ca-d6a4-5853-905d-6eb2913e04fb', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Mullu Murukku', null, 'veg', null, 0, '{}'::text[], true, 'Fryer/Snacks', false, 4) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('16bfcce6-143c-513b-9742-8798364df71b', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '1a442270-c537-5fb4-90c6-650719c7e63e', '1 kg', 1, 'kg', 2500, 'AH-MULLU-MURUKKU-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('8bb6d51a-ae0d-5650-8399-ea55dae6d834', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Palkova', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 10) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('b68dd1ab-41ab-5292-904a-a844640743cb', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '8bb6d51a-ae0d-5650-8399-ea55dae6d834', '¼ kg', 0.25, 'kg', 2500, 'AH-PALKOVA-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('a4673881-c588-52c7-a6b1-ddf51d1b5944', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Peda Kesar', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 7) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('f692c391-872c-5cda-a26a-27c9710ed7ef', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'a4673881-c588-52c7-a6b1-ddf51d1b5944', '20 pcs', 20, 'pcs', 2500, 'AH-PEDA-KESAR-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('4019ef6a-ae31-51b8-b5cf-fbb76512f4f0', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Peda Malai', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 6) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('8e34982a-31f3-51e8-a796-8266a7ffbbc3', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '4019ef6a-ae31-51b8-b5cf-fbb76512f4f0', '20 pcs', 20, 'pcs', 2500, 'AH-PEDA-MALAI-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('6334fbe5-5004-5f66-a0c1-fa9898f90633', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '205b01ca-d6a4-5853-905d-6eb2913e04fb', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Ribbon Pakoda', null, 'veg', null, 1, '{}'::text[], true, 'Fryer/Snacks', false, 3) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('39870443-a9e8-5f50-bea7-44902532d518', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '6334fbe5-5004-5f66-a0c1-fa9898f90633', '1 kg', 1, 'kg', 2500, 'AH-RIBBON-PAKODA-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('7a5303f3-8556-5be7-b878-d953b311550a', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Special Mysore Pak', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 4) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('a05689e1-93bb-5807-a1ef-383a99f0831c', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '7a5303f3-8556-5be7-b878-d953b311550a', '25 pcs', 25, 'pcs', 2500, 'AH-SPECIAL-MYSORE-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('1e0e1a1f-fec8-5384-8fcc-164797d09150', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '205b01ca-d6a4-5853-905d-6eb2913e04fb', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Thattai', null, 'veg', null, 1, '{}'::text[], true, 'Fryer/Snacks', false, 6) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('a5b0ded4-1143-5d0e-b474-7ae699400c6f', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '1e0e1a1f-fec8-5384-8fcc-164797d09150', '25 nos', 25, 'nos', 2500, 'AH-THATTAI-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('c6bc09ef-9250-5c19-9a3c-b6040aea8ea7', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '205b01ca-d6a4-5853-905d-6eb2913e04fb', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Thenkuzhal', null, 'veg', null, 0, '{}'::text[], true, 'Fryer/Snacks', false, 5) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('7b14230c-63b8-5668-a86d-e481e2aefcdb', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'c6bc09ef-9250-5c19-9a3c-b6040aea8ea7', '25 nos', 25, 'nos', 2500, 'AH-THENKUZHAL-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('948f8d28-056a-5fdd-8923-84576dc9a834', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '1438d090-af46-56e0-b273-1e4d55b13c60', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Tirunelveli Halwa', null, 'veg', null, 0, array['dairy']::text[], true, 'Sweets', false, 9) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('c5f561a3-a86e-5db4-962c-ae9cb402bb44', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '948f8d28-056a-5fdd-8923-84576dc9a834', '1 kg', 1, 'kg', 9000, 'AH-TIRUNELVELI-HA-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('2038f4cf-2aee-562e-8b15-9e43b96d6ea3', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '0bc8d28a-dd02-5760-89c1-4af7fc872363', '205b01ca-d6a4-5853-905d-6eb2913e04fb', '637cc9dd-c666-5ccf-9cbb-5f3ff5279d04',
  'Tamil Nadu Mixture', null, 'veg', null, 1, array['nuts']::text[], true, 'Fryer/Snacks', false, 1) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('363d0a2c-2cea-58b9-9e44-84fd6fb96fea', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '2038f4cf-2aee-562e-8b15-9e43b96d6ea3', '1 kg', 1, 'kg', 2500, 'AH-TN-MIXTURE-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('ca4efed0-c91e-5cf7-a3e2-1113401eea3a', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'a196b83c-56fb-53ec-a426-b9fe265e46ff', null,
  'Chettinad Chicken', 'Pepper-forward Chettinad curry.', 'non_veg', 'chicken', 3, '{}'::text[], true, 'Curry', true, 9) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('29526cb1-42db-587c-8d0e-8d1221968b3f', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'ca4efed0-c91e-5cf7-a3e2-1113401eea3a', 'Regular', 1, 'each', 1600, 'AC-CHETTINAD-CHIC-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('22f7f80e-41a1-5826-ba7c-ddd2a517a2c6', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '997488f9-e0a2-5826-9ff7-ae61afe58ce5', null,
  'Chicken Biryani', null, 'non_veg', 'chicken', 2, array['dairy']::text[], true, 'Curry', true, 7) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('f86a96e4-4992-5f14-a0ae-5bff8c70cabd', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '22f7f80e-41a1-5826-ba7c-ddd2a517a2c6', 'Regular', 1, 'each', 1600, 'AC-CHICKEN-BIRYAN-1', 0) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('d36476f3-8859-547f-a62e-8d146c0e71d5', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '22f7f80e-41a1-5826-ba7c-ddd2a517a2c6', 'Half tray', 1, 'half tray', 9000, 'AC-CHICKEN-BIRYAN-2', 1) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('519fe182-2a0c-5932-9350-76ba59eb7453', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '997488f9-e0a2-5826-9ff7-ae61afe58ce5', null,
  'Egg Biryani', null, 'egg', 'egg', 2, array['dairy']::text[], true, 'Curry', true, 6) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('40808249-d8c1-558e-8419-140e9acaebb1', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '519fe182-2a0c-5932-9350-76ba59eb7453', 'Regular', 1, 'each', 1400, 'AC-EGG-BIRYANI-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('7a320587-843e-577c-b6cf-d8e7d67e58a1', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '182df791-1e01-5764-9c79-28e54f223d0d', null,
  'Filter Coffee', 'South Indian decoction coffee with milk.', 'veg', null, 0, array['dairy']::text[], true, 'Beverages', true, 11) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('9fb0f225-cb4e-50f1-a8e5-23b77fd4f14d', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '7a320587-843e-577c-b6cf-d8e7d67e58a1', 'Cup', 1, 'cup', 400, 'AC-FILTER-COFFEE-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('1094862e-8153-54ae-a1a9-c183ec4120da', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'cbfb59c1-a0ab-5046-820b-e7e0621d5f5d', null,
  'Ghee Roast Dosa', 'Paper-thin dosa roasted in ghee.', 'veg', null, 0, array['dairy']::text[], true, 'Dosa tawa', true, 2) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('dc3e61e3-0586-507a-b13c-efef25eef6af', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '1094862e-8153-54ae-a1a9-c183ec4120da', 'Regular', 1, 'each', 1200, 'AC-GHEE-ROAST-DOS-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('2c3840bd-13c7-5a1a-b7e6-6e5255af3df6', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '997488f9-e0a2-5826-9ff7-ae61afe58ce5', null,
  'Goat Biryani', null, 'non_veg', 'goat', 2, array['dairy']::text[], true, 'Curry', true, 8) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('f3878613-6211-59f0-b9fc-ba0ca3fe2b8d', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '2c3840bd-13c7-5a1a-b7e6-6e5255af3df6', 'Regular', 1, 'each', 1800, 'AC-GOAT-BIRYANI-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('e0ec449c-c752-5d53-bb99-9166b812eae0', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '4296edb5-1481-51e0-b257-101b10f71eb1', null,
  'Idli', 'Steamed rice cakes with sambar and chutneys.', 'veg', null, 0, '{}'::text[], true, 'Dosa tawa', true, 3) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('76f662bb-fb78-5c1c-8a9f-1d1fe152f239', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'e0ec449c-c752-5d53-bb99-9166b812eae0', '3 pcs', 3, 'pcs', 800, 'AC-IDLI-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('9086d15c-5ece-576b-8fb6-a37e9c38594e', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', 'cbfb59c1-a0ab-5046-820b-e7e0621d5f5d', null,
  'Masala Dosa', 'Crisp rice-lentil crepe with potato masala, sambar and chutneys.', 'veg', null, 1, '{}'::text[], true, 'Dosa tawa', true, 1) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('18ba5986-e808-52c2-8e64-c0ecbe24b871', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '9086d15c-5ece-576b-8fb6-a37e9c38594e', 'Regular', 1, 'each', 1100, 'AC-MASALA-DOSA-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('5a74edcf-9e26-52cb-89b9-f357eadeaca2', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '4296edb5-1481-51e0-b257-101b10f71eb1', null,
  'Medu Vada', 'Crisp lentil fritters.', 'veg', null, 0, '{}'::text[], true, 'Fryer/Snacks', true, 4) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('6a9eb567-e290-5f2c-8a2b-926359505805', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '5a74edcf-9e26-52cb-89b9-f357eadeaca2', '2 pcs', 2, 'pcs', 700, 'AC-MEDU-VADA-1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('18e1079b-0f41-5a1e-830b-f6ee9ca555a8', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '5b111240-7a56-557a-9527-310398cd47d7', null,
  'Paneer Butter Masala', null, 'veg', null, 1, array['dairy','nuts']::text[], true, 'Curry', true, 10) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('17da1f3d-d55c-5a38-9603-dabd90bde3f0', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '18e1079b-0f41-5a1e-830b-f6ee9ca555a8', 'Regular', 1, 'each', 1400, 'AC-PANEER-BUTTER--1', 0) on conflict do nothing;
insert into public.menu_items (id, tenant_id, brand_id, category_id, collection_id, name, description, diet, protein, spice, allergens,
  is_available, station, is_sample, sort) values ('458fd934-cf33-53ba-a5a3-f85c37ce87bb', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '997488f9-e0a2-5826-9ff7-ae61afe58ce5', null,
  'Vegetable Biryani', 'Basmati rice layered with vegetables and spices, with raita.', 'veg', null, 2, array['dairy']::text[], true, 'Curry', true, 5) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('090bcca9-e238-581f-b3d7-d99a477d7b97', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '458fd934-cf33-53ba-a5a3-f85c37ce87bb', 'Regular', 1, 'each', 1300, 'AC-VEG-BIRYANI-1', 0) on conflict do nothing;
insert into public.item_variants (id, tenant_id, item_id, label, pack_qty, pack_unit, price_cents, barcode, sort) values ('4bd326d1-bf74-5c06-8407-1dab05987de1', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', '458fd934-cf33-53ba-a5a3-f85c37ce87bb', 'Half tray', 1, 'half tray', 7500, 'AC-VEG-BIRYANI-2', 1) on conflict do nothing;

