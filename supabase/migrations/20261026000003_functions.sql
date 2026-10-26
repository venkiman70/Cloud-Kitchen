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
