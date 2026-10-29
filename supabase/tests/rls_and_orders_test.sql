-- Tenant isolation + order flow test.
-- Runs inside one transaction and rolls back, so it leaves no data behind.
-- Usage (local Postgres with the shim):  psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_and_orders_test.sql
-- Usage (Supabase): paste into SQL Editor and click Run. If asked about RLS, choose "Run without RLS"
--                   (the only new table is a temporary one that is thrown away).
begin;

create or replace function pg_temp.assert(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'ASSERTION FAILED: %', msg; end if; end $$;

create or replace function pg_temp.expect_error(stmt text, pattern text) returns void language plpgsql as $$
begin
  execute stmt;
  raise exception 'ASSERTION FAILED: expected error matching % from: %', pattern, stmt;
exception when others then
  if sqlerrm like 'ASSERTION FAILED%' then raise; end if;
  if sqlerrm not like pattern then raise exception 'ASSERTION FAILED: got "%" expected %', sqlerrm, pattern; end if;
end $$;

grant execute on function pg_temp.assert(boolean, text) to anon, authenticated, service_role;
grant execute on function pg_temp.expect_error(text, text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------- fixtures
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@aryas.test'),
  ('00000000-0000-0000-0000-0000000000a2', 'kitchen@aryas.test'),
  ('00000000-0000-0000-0000-0000000000b1', 'owner@friend.test');

insert into tenant_members (tenant_id, user_id, role)
select id, '00000000-0000-0000-0000-0000000000a1', 'owner' from tenants where slug = 'aryas';
insert into tenant_members (tenant_id, user_id, role)
select id, '00000000-0000-0000-0000-0000000000a2', 'kitchen_staff' from tenants where slug = 'aryas';

insert into tenants (id, slug, name) values ('11111111-1111-1111-1111-111111111111', 'friend', 'Friend''s Catering Co');
insert into tenant_settings (tenant_id) values ('11111111-1111-1111-1111-111111111111');
insert into brands (id, tenant_id, slug, name, order_prefix) values
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'friend', 'Friend''s Catering', 'FC');
insert into menu_items (id, tenant_id, brand_id, name, diet) values
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'Veg Thali', 'veg');
insert into item_variants (id, tenant_id, item_id, label, price_cents) values
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'Regular', 1500);
insert into tenant_members (tenant_id, user_id, role) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000b1', 'owner');

-- Test-only menu items and settings (rolled back at the end), so the test works on a live database
update tenant_settings set slot_capacity = 1000, pickup_hours = '{}'::jsonb, lead_time_minutes = 20, pay_at_pickup = true, pay_at_pickup_max_cents = 10000
 where tenant_id = (select id from tenants where slug = 'aryas');
update menu_collections set pickup_dates = array['2026-11-07']::date[], order_cutoff_at = '2026-11-08 12:00:00-06'
 where slug = 'diwali-2026';
insert into menu_items (id, tenant_id, brand_id, name, diet, protein)
select x.id::uuid, t.id, b.id, x.name, x.diet::diet_type, x.protein
  from tenants t join brands b on b.tenant_id = t.id and b.slug = 'aryas',
       (values ('55555555-0000-0000-0000-000000000001', 'Test Dosa', 'veg', null),
               ('55555555-0000-0000-0000-000000000002', 'Test Chicken Biryani', 'non_veg', 'chicken')) as x(id, name, diet, protein)
 where t.slug = 'aryas';
insert into item_variants (tenant_id, item_id, label, price_cents)
select tenant_id, id, 'Regular', case name when 'Test Dosa' then 1100 else 1600 end
  from menu_items where id in ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000002');

-- Pickup tomorrow at 12:30 Dallas time
create temp table _ctx as
select ((((now() at time zone 'America/Chicago')::date + 1) + time '12:30') at time zone 'America/Chicago') as pickup,
       (select v.id from item_variants v join menu_items i on i.id = v.item_id where i.name = 'Test Dosa') as dosa,
       (select v.id from item_variants v join menu_items i on i.id = v.item_id where i.name = 'Test Chicken Biryani') as biryani,
       (select v.id from item_variants v join menu_items i on i.id = v.item_id where i.name = 'Boondhi Ladoo' and i.deleted_at is null and v.deleted_at is null limit 1) as ladoo,
       null::jsonb as order_a, null::jsonb as order_b;
grant select, update on _ctx to anon, authenticated, service_role;

-- ---------------------------------------------------------------- create orders (service role)
set local role service_role;

update _ctx set order_a = create_order(jsonb_build_object(
  'tenant', 'aryas', 'brand', 'aryas', 'pickupAt', (select pickup from _ctx),
  'customer', jsonb_build_object('name', 'Priya Raman', 'phone', '(214) 555-0101', 'email', 'priya@example.com', 'optInEmail', true),
  'items', jsonb_build_array(
     jsonb_build_object('variantId', (select dosa from _ctx), 'quantity', 2),
     jsonb_build_object('variantId', (select biryani from _ctx), 'quantity', 1))));

select pg_temp.assert((select (order_a->>'subtotalCents')::int = 2*1100 + 1600 from _ctx), 'subtotal = 2 dosa + 1 biryani');
select pg_temp.assert((select (order_a->>'taxCents')::int = 314 from _ctx), 'tax 8.25% of $38.00 = $3.14 (half-up)');
select pg_temp.assert((select (order_a->>'platformFeeCents')::int = 152 from _ctx), 'fee 4% of food = $1.52');
select pg_temp.assert((select order_a->>'orderNumber' like 'AC-%' from _ctx), 'Aryas orders are numbered AC-');

update _ctx set order_b = create_order(jsonb_build_object(
  'tenant', 'friend', 'brand', 'friend', 'pickupAt', (select pickup from _ctx),
  'customer', jsonb_build_object('name', 'Ravi', 'phone', '+12145550199'),
  'items', jsonb_build_array(jsonb_build_object('variantId', '44444444-4444-4444-4444-444444444444', 'quantity', 1))));

-- Same phone again reuses the customer record
select create_order(jsonb_build_object(
  'tenant', 'aryas', 'brand', 'aryas', 'pickupAt', (select pickup from _ctx) + interval '15 minutes',
  'customer', jsonb_build_object('name', 'Priya Raman', 'phone', '214-555-0101'),
  'items', jsonb_build_array(jsonb_build_object('variantId', (select dosa from _ctx), 'quantity', 1))));
select pg_temp.assert((select count(*) = 1 from customers where phone = '+12145550101'), 'one customer per phone');

-- Validation errors
select pg_temp.expect_error(format($q$select create_order('{"tenant":"aryas","brand":"aryas","pickupAt":"%s","customer":{"name":"X","phone":"123"},"items":[{"variantId":"%s","quantity":1}]}')$q$, (select pickup from _ctx), (select dosa from _ctx)), 'BAD_PHONE%');
select pg_temp.expect_error(format($q$select create_order('{"tenant":"aryas","brand":"aryas","pickupAt":"%s","customer":{"name":"X","phone":"2145550111"},"items":[{"variantId":"%s","quantity":1}]}')$q$, now() + interval '5 minutes', (select dosa from _ctx)), 'PICKUP_TOO_SOON%');
select pg_temp.expect_error(format($q$select create_order('{"tenant":"aryas","brand":"aryas","pickupAt":"%s","customer":{"name":"X","phone":"2145550111"},"items":[{"variantId":"44444444-4444-4444-4444-444444444444","quantity":1}]}')$q$, (select pickup from _ctx)), 'ITEM_NOT_FOUND%');
-- Diwali item must be picked up on 6-8 Nov
select pg_temp.expect_error(format($q$select create_order('{"tenant":"aryas","brand":"ahil","pickupAt":"%s","customer":{"name":"X","phone":"2145550111"},"items":[{"variantId":"%s","quantity":1}]}')$q$, (select pickup from _ctx), (select ladoo from _ctx)), 'PICKUP_DATE_NOT_ALLOWED%');
select pg_temp.assert((select (create_order(jsonb_build_object('tenant','aryas','brand','ahil',
  'pickupAt', '2026-11-07 12:00:00-06', 'customer', jsonb_build_object('name','Priya','phone','2145550101'),
  'items', jsonb_build_array(jsonb_build_object('variantId',(select ladoo from _ctx),'quantity',8))))->>'orderNumber') like 'AH-%'), 'AHIL Diwali pre-order accepted, numbered AH-');

reset role;

-- ---------------------------------------------------------------- payment webhook path
update orders set stripe_checkout_session_id = 'cs_test_A' where id = (select (order_a->>'orderId')::uuid from _ctx);
set local role service_role;
select mark_order_paid('cs_test_A', 'pi_test_A', (select (order_a->>'totalCents')::int from _ctx));
select pg_temp.assert((select (mark_order_paid('cs_test_A', 'pi_test_A', 0)->>'alreadyPaid')::boolean), 'webhook replay is idempotent');
reset role;
select pg_temp.assert((select status = 'confirmed' and payment_status = 'paid' from orders where stripe_checkout_session_id = 'cs_test_A'), 'paid order is confirmed');
select pg_temp.assert((select fee_cents = 152 from platform_fee_ledger where order_id = (select (order_a->>'orderId')::uuid from _ctx)), 'fee ledger row written');

-- ---------------------------------------------------------------- anonymous visitor
set local role anon;
select pg_temp.assert((select count(*) = 0 from orders), 'anon cannot read orders');
select pg_temp.assert((select count(*) = 0 from customers), 'anon cannot read customers');
select pg_temp.assert((select count(*) >= 1 from menu_items), 'anon can read the menu');
select pg_temp.expect_error($q$select create_order('{}')$q$, 'permission denied%');
select pg_temp.expect_error($q$insert into orders (tenant_id, brand_id, order_number, pickup_at, subtotal_cents, tax_cents, total_cents) values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'X-1', now(), 0, 0, 0)$q$, '%row-level security%');
select pg_temp.assert((select order_status_public((select (order_a->>'publicToken')::uuid from _ctx))->>'orderNumber' = (select order_a->>'orderNumber' from _ctx)), 'status page works with the token');
select pg_temp.assert((select order_status_public((select (order_a->>'publicToken')::uuid from _ctx)) ? 'customerEmail' = false), 'status page hides email');
reset role;

-- ---------------------------------------------------------------- tenant B owner cannot see tenant A
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.assert((select count(*) = 1 from orders), 'tenant B owner sees only their 1 order');
select pg_temp.assert((select bool_and(tenant_id = '11111111-1111-1111-1111-111111111111') from orders), 'all visible orders belong to tenant B');
select pg_temp.assert((select count(*) = 0 from customers where phone = '+12145550101'), 'tenant B cannot see Aryas customers');
select pg_temp.expect_error($q$select kitchen_board((select id from tenants where slug = 'aryas'))$q$, 'NOT_ALLOWED%');
with u as (update menu_items set name = 'hacked' where name = 'Test Dosa' returning 1) select pg_temp.assert(count(*) = 0, 'tenant B cannot edit Aryas menu') from u;
reset role;

-- ---------------------------------------------------------------- Aryas kitchen staff
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
select pg_temp.assert((select count(*) = 0 from orders), 'kitchen staff cannot read money/contact columns (orders table)');
select pg_temp.assert((select kitchen_board((select id from tenants where slug = 'aryas')) @> jsonb_build_array(jsonb_build_object('orderNumber', (select order_a->>'orderNumber' from _ctx)))), 'kitchen board shows the paid order');
select pg_temp.assert((select not exists (select 1 from jsonb_array_elements(kitchen_board((select id from tenants where slug = 'aryas'))) e where e ? 'totalCents' or e ? 'customerEmail')), 'board has no money or email fields');
select pg_temp.assert((select count(*) >= 1 from order_signals), 'kitchen can read order signals for realtime');
select advance_order((select (order_a->>'orderId')::uuid from _ctx), 'preparing');
select advance_order((select (order_a->>'orderId')::uuid from _ctx), 'ready');
select pg_temp.expect_error(format('select advance_order(%L, %L)', (select order_a->>'orderId' from _ctx), 'confirmed'), 'BAD_TRANSITION%');
select pg_temp.expect_error(format('select advance_order(%L, %L)', (select order_a->>'orderId' from _ctx), 'cancelled'), 'BAD_TRANSITION%');
select set_item_availability('55555555-0000-0000-0000-000000000001', false);
with u as (update item_variants set price_cents = 1 returning 1) select pg_temp.assert(count(*) = 0, 'kitchen staff cannot change prices') from u;
select pg_temp.assert((select jsonb_typeof(prep_totals((select id from tenants where slug = 'aryas'), '2026-11-07')) = 'array'), 'kitchen can read prep totals');
reset role;
select pg_temp.assert((select not is_available from menu_items where id = '55555555-0000-0000-0000-000000000001'), 'kitchen sold out Test Dosa');

-- Sold-out item is refused at checkout
set local role service_role;
select pg_temp.expect_error(format($q$select create_order('{"tenant":"aryas","brand":"aryas","pickupAt":"%s","customer":{"name":"X","phone":"2145550111"},"items":[{"variantId":"%s","quantity":1}]}')$q$, (select pickup from _ctx) + interval '1 hour', (select dosa from _ctx)), 'ITEM_SOLD_OUT:Test Dosa%');
reset role;

-- ---------------------------------------------------------------- Aryas owner
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.assert((select count(*) >= 3 and bool_and(tenant_id = (select id from tenants where slug = 'aryas')) from orders), 'Aryas owner sees Aryas orders and none of tenant B');
select pg_temp.assert((select count(*) = 1 from customers where phone = '+12145550101'), 'Aryas owner sees Priya once');
select pg_temp.expect_error($q$update tenant_settings set platform_fee_bps = 0$q$, 'permission denied%');
with u as (update tenant_settings set tax_rate_bps = 825 returning 1) select pg_temp.assert(count(*) = 1, 'owner can update tax rate') from u;
reset role;

-- ---------------------------------------------------------------- pay at pickup
set local role service_role;
update _ctx set order_b = create_order(jsonb_build_object(
  'tenant', 'aryas', 'brand', 'aryas', 'pickupAt', (select pickup from _ctx) + interval '2 hours',
  'customer', jsonb_build_object('name', 'Anu K', 'phone', '2145550123'),
  'items', jsonb_build_array(jsonb_build_object('variantId', (select biryani from _ctx), 'quantity', 1))));
select pg_temp.assert((select (confirm_pay_at_pickup((order_b->>'orderId')::uuid)->>'paymentStatus') = 'unpaid' from _ctx), 'pay at pickup confirms the order unpaid');
select pg_temp.expect_error(format('select confirm_pay_at_pickup(%L)', (select order_b->>'orderId' from _ctx)), 'NOT_PAYABLE%');
reset role;
select pg_temp.assert((select status = 'confirmed' and payment_status = 'unpaid' and pay_at_pickup from orders where id = (select (order_b->>'orderId')::uuid from _ctx)), 'pay-at-pickup order is confirmed, unpaid');
-- Over the cap is refused
update tenant_settings set pay_at_pickup_max_cents = 1000 where tenant_id = (select id from tenants where slug = 'aryas');
set local role service_role;
select pg_temp.expect_error(format('select confirm_pay_at_pickup(%L)', (create_order(jsonb_build_object(
  'tenant', 'aryas', 'brand', 'aryas', 'pickupAt', (select pickup from _ctx) + interval '3 hours',
  'customer', jsonb_build_object('name', 'Big', 'phone', '2145550124'),
  'items', jsonb_build_array(jsonb_build_object('variantId', (select biryani from _ctx), 'quantity', 1))))->>'orderId')), 'PAY_AT_PICKUP_LIMIT:$10.00%');
reset role;
-- Turned off is refused
update tenant_settings set pay_at_pickup = false, pay_at_pickup_max_cents = 10000 where tenant_id = (select id from tenants where slug = 'aryas');
set local role service_role;
select pg_temp.expect_error(format('select confirm_pay_at_pickup(%L)', (create_order(jsonb_build_object(
  'tenant', 'aryas', 'brand', 'aryas', 'pickupAt', (select pickup from _ctx) + interval '4 hours',
  'customer', jsonb_build_object('name', 'Off', 'phone', '2145550125'),
  'items', jsonb_build_array(jsonb_build_object('variantId', (select biryani from _ctx), 'quantity', 1))))->>'orderId')), 'PAY_AT_PICKUP_OFF%');
reset role;

-- Kitchen staff: board shows amount due, can't hand over unpaid, mark paid by Zelle
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
select pg_temp.assert((select (e->>'amountDueCents')::int = 1600 + 132 and e->>'paymentStatus' = 'unpaid'
  from jsonb_array_elements(kitchen_board((select id from tenants where slug = 'aryas'))) e
  where e->>'orderNumber' = (select order_b->>'orderNumber' from _ctx)), 'board shows amount due on unpaid order');
select advance_order((select (order_b->>'orderId')::uuid from _ctx), 'ready');
select pg_temp.expect_error(format('select advance_order(%L, %L)', (select order_b->>'orderId' from _ctx), 'completed'), 'NOT_PAID%');
select pg_temp.expect_error(format('select record_manual_payment(%L, %L)', (select order_b->>'orderId' from _ctx), 'bitcoin'), 'BAD_METHOD%');
select pg_temp.assert((select (record_manual_payment((order_b->>'orderId')::uuid, 'zelle')->>'alreadyPaid')::boolean = false from _ctx), 'kitchen marks paid by Zelle');
select pg_temp.assert((select (record_manual_payment((order_b->>'orderId')::uuid, 'cash')->>'alreadyPaid')::boolean from _ctx), 'second tap is harmless');
select pg_temp.assert((select e->>'paidMethod' = 'zelle' and e->'amountDueCents' = 'null'::jsonb
  from jsonb_array_elements(kitchen_board((select id from tenants where slug = 'aryas'))) e
  where e->>'orderNumber' = (select order_b->>'orderNumber' from _ctx)), 'board shows paid by Zelle, nothing due');
select pg_temp.expect_error(format('select undo_manual_payment(%L)', (select order_b->>'orderId' from _ctx)), 'NOT_ALLOWED%');
reset role;
select pg_temp.assert((select count(*) = 1 from payments where order_id = (select (order_b->>'orderId')::uuid from _ctx) and method = 'zelle' and recorded_by = '00000000-0000-0000-0000-0000000000a2'), 'one Zelle payment recorded with who');
select pg_temp.assert((select collected_via = 'invoice' and fee_cents = 64 from platform_fee_ledger where order_id = (select (order_b->>'orderId')::uuid from _ctx)), '4% fee accrues as invoice');
select pg_temp.assert((select count(*) = 1 from audit_log where entity = 'order' and action = 'mark_paid' and actor_email = 'kitchen@aryas.test'), 'mark paid is in the audit log');

-- Owner undoes a wrong tap, then it's marked cash and handed over
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select undo_manual_payment((select (order_b->>'orderId')::uuid from _ctx));
reset role;
select pg_temp.assert((select payment_status = 'unpaid' from orders where id = (select (order_b->>'orderId')::uuid from _ctx)), 'undo makes it unpaid');
select pg_temp.assert((select count(*) = 0 from platform_fee_ledger where order_id = (select (order_b->>'orderId')::uuid from _ctx)), 'undo removes the fee row');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
select record_manual_payment((select (order_b->>'orderId')::uuid from _ctx), 'cash');
select advance_order((select (order_b->>'orderId')::uuid from _ctx), 'completed');
reset role;
select pg_temp.assert((select status = 'completed' and payment_status = 'paid' from orders where id = (select (order_b->>'orderId')::uuid from _ctx)), 'paid order handed over');

-- ---------------------------------------------------------------- refund
set local role service_role;
select mark_order_refunded('pi_test_A', (select (order_a->>'totalCents')::int from _ctx));
reset role;
select pg_temp.assert((select status = 'refunded' from orders where stripe_payment_intent_id = 'pi_test_A'), 'full refund marks order refunded');
select pg_temp.assert((select reversed_cents = 152 from platform_fee_ledger where order_id = (select (order_a->>'orderId')::uuid from _ctx)), 'platform fee reversed on full refund');

rollback;
-- Reached only if every assertion above passed (any failure stops the script with an error).
select 'ALL TESTS PASSED' as result;
