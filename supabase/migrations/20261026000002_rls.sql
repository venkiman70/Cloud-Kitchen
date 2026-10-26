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
