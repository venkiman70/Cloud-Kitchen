-- Pay at pickup + "Mark paid" (28 Oct 2026). Safe to run more than once.
--
-- * Customers can choose "Pay at pickup" at checkout when the tenant allows it, up to a cap.
--   The order goes straight to the kitchen as confirmed and unpaid.
-- * Staff record how it was paid at handover: cash, check, Zelle or card on the counter (Square).
--   Each manual payment is written to payments, audit_log and the platform fee ledger ("invoice").
-- * An unpaid order can't be marked Picked up.

-- New payment methods (the enum already has stripe, cash, external)
alter type public.pay_method add value if not exists 'check';
alter type public.pay_method add value if not exists 'zelle';
alter type public.pay_method add value if not exists 'square';

-- Settings: cap on unpaid pay-at-pickup orders (null = no cap)
alter table public.tenant_settings add column if not exists pay_at_pickup_max_cents int default 10000
  check (pay_at_pickup_max_cents is null or pay_at_pickup_max_cents >= 0);
grant update (pay_at_pickup, pay_at_pickup_max_cents) on public.tenant_settings to authenticated;

-- Orders and payments: who chose pay at pickup, who recorded a manual payment
alter table public.orders   add column if not exists pay_at_pickup boolean not null default false;
alter table public.payments add column if not exists recorded_by uuid;

-- Aryas: owner confirmed pay at pickup on 27 Oct
update public.tenant_settings set pay_at_pickup = true
 where tenant_id = (select id from public.tenants where slug = 'aryas');

-- ---------------------------------------------------------------------------
-- Storefront config: also returns the pay-at-pickup cap
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
      'payAtPickup', s.pay_at_pickup, 'payAtPickupMaxCents', s.pay_at_pickup_max_cents,
      'bannerUrl', s.banner_url),
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
-- Receipt payload: now says whether the order is paid or due at pickup
-- ---------------------------------------------------------------------------
create or replace function public.order_receipt(p_order uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'orderId', o.id, 'orderNumber', o.order_number, 'publicToken', o.public_token,
    'status', o.status, 'customerName', o.customer_name, 'customerEmail', o.customer_email,
    'pickupAt', o.pickup_at, 'timezone', s.timezone, 'currency', s.currency,
    'brandName', b.name, 'tenantName', t.name, 'address', s.address,
    'pickupInstructions', s.pickup_instructions,
    'subtotalCents', o.subtotal_cents, 'taxCents', o.tax_cents, 'totalCents', o.total_cents,
    'paymentStatus', o.payment_status, 'payAtPickup', o.pay_at_pickup,
    'items', (select jsonb_agg(jsonb_build_object('name', oi.item_name, 'variant', oi.variant_label,
               'quantity', oi.quantity, 'lineTotalCents', oi.line_total_cents) order by oi.item_name)
              from order_items oi where oi.order_id = o.id))
  from orders o join brands b on b.id = o.brand_id join tenants t on t.id = o.tenant_id
  join tenant_settings s on s.tenant_id = o.tenant_id
  where o.id = p_order;
$$;

-- ---------------------------------------------------------------------------
-- confirm_pay_at_pickup: called by create-order (service role) right after
-- create_order when the customer chose to pay at pickup. Checks the tenant
-- allows it and the total is under the cap, then sends the order to the kitchen.
-- ---------------------------------------------------------------------------
create or replace function public.confirm_pay_at_pickup(p_order uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  o orders;
  s tenant_settings;
begin
  select * into o from orders where id = p_order for update;
  if o.id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into s from tenant_settings where tenant_id = o.tenant_id;

  if o.status <> 'pending_payment' or o.payment_status <> 'unpaid' or o.stripe_checkout_session_id is not null then
    raise exception 'NOT_PAYABLE';
  end if;
  if not s.pay_at_pickup then raise exception 'PAY_AT_PICKUP_OFF'; end if;
  if s.pay_at_pickup_max_cents is not null and o.total_cents > s.pay_at_pickup_max_cents then
    raise exception 'PAY_AT_PICKUP_LIMIT:%', to_char(s.pay_at_pickup_max_cents / 100.0, 'FM$999,990.00');
  end if;

  update orders set status = 'confirmed', pay_at_pickup = true where id = o.id;
  insert into order_status_events (tenant_id, order_id, from_status, to_status) values (o.tenant_id, o.id, o.status, 'confirmed');
  return public.order_receipt(o.id);
end $$;

-- ---------------------------------------------------------------------------
-- record_manual_payment: staff mark an order paid by cash, check, Zelle or
-- card on the counter (Square). Safe to tap twice.
-- ---------------------------------------------------------------------------
create or replace function public.record_manual_payment(p_order uuid, p_method text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  o orders;
  s tenant_settings;
begin
  if p_method not in ('cash', 'check', 'zelle', 'square') then raise exception 'BAD_METHOD'; end if;
  select * into o from orders where id = p_order for update;
  if o.id is null or not public.is_staff(o.tenant_id) then raise exception 'NOT_ALLOWED'; end if;
  if o.payment_status = 'paid' then
    return jsonb_build_object('orderNumber', o.order_number, 'alreadyPaid', true);
  end if;
  if o.status in ('pending_payment', 'cancelled', 'refunded') or o.payment_status <> 'unpaid' then
    raise exception 'NOT_PAYABLE';
  end if;
  select * into s from tenant_settings where tenant_id = o.tenant_id;

  update orders set payment_status = 'paid', paid_at = now() where id = o.id;
  insert into payments (tenant_id, order_id, method, amount_cents, recorded_by)
    values (o.tenant_id, o.id, p_method::pay_method, o.total_cents, auth.uid());
  insert into platform_fee_ledger (tenant_id, order_id, fee_base_cents, fee_cents, collected_via, period)
    values (o.tenant_id, o.id, o.subtotal_cents - o.discount_cents, o.platform_fee_cents, 'invoice',
            date_trunc('month', now() at time zone s.timezone)::date)
    on conflict (order_id) do nothing;
  insert into audit_log (tenant_id, actor_id, actor_email, entity, entity_id, action, old_value, new_value)
    values (o.tenant_id, auth.uid(), public.audit_actor_email(), 'order', o.id, 'mark_paid',
            jsonb_build_object('paymentStatus', 'unpaid'),
            jsonb_build_object('orderNumber', o.order_number, 'method', p_method, 'amountCents', o.total_cents));
  return jsonb_build_object('orderNumber', o.order_number, 'alreadyPaid', false, 'method', p_method);
end $$;

-- ---------------------------------------------------------------------------
-- undo_manual_payment: a manager reverses a wrong "Mark paid" tap.
-- Only manual payments, and only before the order is picked up.
-- ---------------------------------------------------------------------------
create or replace function public.undo_manual_payment(p_order uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  o orders;
  pay payments;
begin
  select * into o from orders where id = p_order for update;
  if o.id is null or not public.is_manager(o.tenant_id) then raise exception 'NOT_ALLOWED'; end if;
  if o.status = 'completed' then raise exception 'ALREADY_PICKED_UP'; end if;
  select * into pay from payments where order_id = o.id order by created_at desc limit 1;
  if pay.id is null or pay.method in ('stripe', 'external') or o.payment_status <> 'paid' then
    raise exception 'NOT_MANUAL';
  end if;

  delete from payments where id = pay.id;
  delete from platform_fee_ledger where order_id = o.id and collected_via = 'invoice';
  update orders set payment_status = 'unpaid', paid_at = null where id = o.id;
  insert into audit_log (tenant_id, actor_id, actor_email, entity, entity_id, action, old_value, new_value)
    values (o.tenant_id, auth.uid(), public.audit_actor_email(), 'order', o.id, 'undo_paid',
            jsonb_build_object('orderNumber', o.order_number, 'method', pay.method, 'amountCents', pay.amount_cents),
            jsonb_build_object('paymentStatus', 'unpaid'));
  return jsonb_build_object('orderNumber', o.order_number);
end $$;

-- ---------------------------------------------------------------------------
-- advance_order: an unpaid order can't be marked Picked up
-- ---------------------------------------------------------------------------
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
  if p_to = 'completed' and o.payment_status <> 'paid' then raise exception 'NOT_PAID'; end if;
  update orders set status = p_to where id = o.id;
  insert into order_status_events (tenant_id, order_id, from_status, to_status, actor)
    values (o.tenant_id, o.id, o.status, p_to, auth.uid());
  return jsonb_build_object('orderId', o.id, 'orderNumber', o.order_number, 'from', o.status, 'to', p_to);
end $$;

-- ---------------------------------------------------------------------------
-- Kitchen board: adds payment state, and the amount to collect on unpaid orders
-- (no other money fields; kitchen staff still can't read prices or contact details)
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
        'paymentStatus', o.payment_status, 'payAtPickup', o.pay_at_pickup,
        'amountDueCents', case when o.payment_status = 'unpaid' then o.total_cents end,
        'paidMethod', (select p.method from payments p where p.order_id = o.id order by p.created_at desc limit 1),
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

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke execute on function public.confirm_pay_at_pickup(uuid)       from public, anon, authenticated;
revoke execute on function public.record_manual_payment(uuid, text) from public, anon;
revoke execute on function public.undo_manual_payment(uuid)         from public, anon;
revoke execute on function public.order_receipt(uuid)               from public, anon, authenticated;
revoke execute on function public.advance_order(uuid, public.order_status) from public, anon;
revoke execute on function public.kitchen_board(uuid)               from public, anon;
revoke execute on function public.storefront_config(text, text)     from public;

grant execute on function public.storefront_config(text, text)      to anon, authenticated;
grant execute on function public.kitchen_board(uuid)                to authenticated;
grant execute on function public.advance_order(uuid, public.order_status) to authenticated;
grant execute on function public.record_manual_payment(uuid, text)  to authenticated;
grant execute on function public.undo_manual_payment(uuid)          to authenticated;
grant execute on function public.confirm_pay_at_pickup(uuid)        to service_role;
grant execute on function public.order_receipt(uuid)                to service_role;
