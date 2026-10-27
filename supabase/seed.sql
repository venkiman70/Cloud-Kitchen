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
update public.tenant_settings set banner_url = '/brand/banner.webp' where tenant_id = (select id from public.tenants where slug = 'aryas');
insert into public.brands (id, tenant_id, slug, name, tagline, theme, order_prefix, sort) values
  ('25c78a6d-48b6-5b28-85b4-bcaf19af08c9', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'aryas', 'Aryas Cuisine', 'Indian soul food, made with love', '{"accent":"#1E6B33","accentInk":"#FFFFFF","accentDark":"#7CC98C","accentInkDark":"#10230F","logo":"/brand/aryas-logo.webp","logoStacked":"/brand/aryas-logo.webp","hero":"/brand/aryas-card.webp"}', 'AC', 1),
  ('0bc8d28a-dd02-5760-89c1-4af7fc872363', '0fb0f7f5-15f9-5968-88e5-76377bd2ed13', 'ahil', 'AHIL', 'Bringing joy in every bite', '{"accent":"#2B7BBF","accentInk":"#FFFFFF","accentDark":"#8CC4F0","accentInkDark":"#0C2033","logo":"/brand/ahil-logo.webp","logoStacked":"/brand/ahil-logo.webp","hero":"/brand/ahil-card.webp"}', 'AH', 2)
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
