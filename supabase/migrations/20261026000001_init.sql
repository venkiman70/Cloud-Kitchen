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
