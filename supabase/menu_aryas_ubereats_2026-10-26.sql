-- Replace the Aryas SAMPLE dishes with the real menu as listed on Uber Eats/Postmates (26 Oct 2026).
-- Paste into Supabase → SQL Editor → Run. Safe to run once.
--
-- Notes
--  * Prices are the marketplace prices. Many kitchens price their own site lower; edit them in /admin → Menu.
--  * Uber's separate "Veg" / "Non Veg" sections are merged into one section each; the app's veg marks and
--    "Veg only" filter do that job.
--  * Allergens are only filled where certain (paneer = dairy). Ask the owner to add the rest.
--  * Breads, curries (16 oz), desserts and drinks were listed on Uber with no items, so they're not here yet.
--  * Sample dishes are soft-deleted (hidden, kept for history), not erased.

begin;

-- 1. Hide the sample dishes
update menu_items set deleted_at = now()
 where is_sample and brand_id = (select b.id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas');

-- 2. Categories
with b as (select b.id as brand_id, b.tenant_id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas')
insert into menu_categories (tenant_id, brand_id, name, sort)
select b.tenant_id, b.brand_id, c.name, c.sort from b,
  (values ('Appetizers', 1), ('Chaat Corner', 2), ('Rice & Biryani', 3), ('Kathi Rolls', 4)) as c(name, sort)
on conflict (brand_id, name) do update set sort = excluded.sort;

-- 3. Dishes and prices
create temp table _m (cat text, name text, descr text, diet diet_type, protein text, allergens text[], station text, sort int, variants jsonb) on commit drop;
insert into _m values
 ('Appetizers', 'Golden Crisps (Samosa)', 'Crispy pastry with spiced potato and peas.', 'veg', null, '{}', 'Fryer/Snacks', 1, '[{"label":"2 pcs","qty":2,"unit":"pcs","cents":499}]'),
 ('Appetizers', 'Naan Munchies', 'Mini flatbread bites served with hummus.', 'veg', null, '{}', 'Tandoor', 2, '[{"label":"4 pcs","qty":4,"unit":"pcs","cents":499}]'),
 ('Appetizers', 'Crisp ''N'' Roll Veggies', 'Fried rolls with seasoned vegetables and a tangy dipping sauce.', 'veg', null, '{}', 'Fryer/Snacks', 3, '[{"label":"2 pcs","qty":2,"unit":"pcs","cents":499}]'),
 ('Appetizers', 'Paneer Puff Balls', 'Fried bites of paneer and vegetables with mild spices.', 'veg', null, '{dairy}', 'Fryer/Snacks', 4, '[{"label":"3 pcs","qty":3,"unit":"pcs","cents":569}]'),
 ('Appetizers', 'Egg Zing 65', 'Spiced, fried egg with a yogurt dip.', 'egg', 'egg', '{dairy}', 'Fryer/Snacks', 5, '[{"label":"Regular","qty":1,"unit":"plate","cents":569}]'),
 ('Appetizers', 'Egg Omelette', 'Herb-seasoned omelette with your choice of fillings.', 'egg', 'egg', '{}', 'Dosa tawa', 6, '[{"label":"Regular","qty":1,"unit":"each","cents":689}]'),
 ('Appetizers', 'Crisp ''N'' Roll Chicken', 'Spiced chicken in fried pastry rolls, served with dipping sauce.', 'non_veg', 'chicken', '{}', 'Fryer/Snacks', 7, '[{"label":"2 pcs","qty":2,"unit":"pcs","cents":949}]'),
 ('Appetizers', 'Flame-kissed Chicken', 'Shredded chicken in spices and herbs, with some heat.', 'non_veg', 'chicken', '{}', 'Curry', 8, '[{"label":"Regular","qty":1,"unit":"plate","cents":949}]'),
 ('Appetizers', 'Thava Fish', 'Tawa-fried fish bites with a zesty dipping sauce.', 'non_veg', 'fish', '{}', 'Dosa tawa', 9, '[{"label":"Regular","qty":1,"unit":"plate","cents":949}]'),
 ('Chaat Corner', 'Sev Puri', 'Puris with spicy potatoes or guacamole, chutneys and sev.', 'veg', null, '{}', 'Fryer/Snacks', 1, '[{"label":"Potato","qty":1,"unit":"plate","cents":649},{"label":"Guac","qty":1,"unit":"plate","cents":649}]'),
 ('Chaat Corner', 'Papdi Chaat', 'Crispy papdi with potatoes, yogurt, tamarind chutney and sev.', 'veg', null, '{dairy}', 'Fryer/Snacks', 2, '[{"label":"Regular","qty":1,"unit":"plate","cents":649}]'),
 ('Chaat Corner', 'Ragada Chaat', 'Ragda with crispy puris, chutneys, onions and coriander.', 'veg', null, '{}', 'Fryer/Snacks', 3, '[{"label":"Regular","qty":1,"unit":"plate","cents":649}]'),
 ('Rice & Biryani', 'Garden Fresh Pulav', 'Aromatic rice with fresh vegetables.', 'veg', null, '{}', 'Curry', 1, '[{"label":"Regular","qty":1,"unit":"each","cents":1099}]'),
 ('Rice & Biryani', 'Crunchy Podi Rice', 'Rice seasoned with podi spices and a crunchy finish.', 'veg', null, '{}', 'Curry', 2, '[{"label":"Regular","qty":1,"unit":"each","cents":1099}]'),
 ('Rice & Biryani', 'Vegetable Fried Rice', 'Fried rice with fresh vegetables.', 'veg', null, '{}', 'Curry', 3, '[{"label":"Regular","qty":1,"unit":"each","cents":1099}]'),
 ('Rice & Biryani', 'Chicken Biryani', 'Spiced chicken and rice.', 'non_veg', 'chicken', '{}', 'Curry', 4, '[{"label":"Regular","qty":1,"unit":"each","cents":1399}]'),
 ('Kathi Rolls', 'Paneer Kathi Roll', 'Tangy paneer curry in paratha with house-made sauce.', 'veg', null, '{dairy}', 'Dosa tawa', 1, '[{"label":"Regular","qty":1,"unit":"each","cents":1399}]'),
 ('Kathi Rolls', 'Mixed Vegetable Kathi Roll', 'Spiced mixed vegetables in paratha with house-made sauce.', 'veg', null, '{}', 'Dosa tawa', 2, '[{"label":"Regular","qty":1,"unit":"each","cents":1399}]'),
 ('Kathi Rolls', 'Egg Kathi Roll', 'Egg burji in paratha with chutney.', 'egg', 'egg', '{}', 'Dosa tawa', 3, '[{"label":"Regular","qty":1,"unit":"each","cents":1199}]'),
 ('Kathi Rolls', 'Chicken Kathi Roll', 'Spiced shredded chicken in paratha with house-made sauce.', 'non_veg', 'chicken', '{}', 'Dosa tawa', 4, '[{"label":"Regular","qty":1,"unit":"each","cents":1399}]');

with b as (select b.id as brand_id, b.tenant_id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas'),
ins as (
  insert into menu_items (tenant_id, brand_id, category_id, name, description, diet, protein, allergens, station, sort, is_sample)
  select b.tenant_id, b.brand_id, c.id, m.name, m.descr, m.diet, m.protein, m.allergens, m.station, m.sort, false
    from _m m cross join b join menu_categories c on c.brand_id = b.brand_id and c.name = m.cat
  returning id, tenant_id, name
)
insert into item_variants (tenant_id, item_id, label, pack_qty, pack_unit, price_cents, sort)
select ins.tenant_id, ins.id, v->>'label', (v->>'qty')::numeric, v->>'unit', (v->>'cents')::int, (o - 1)::int
  from ins join _m m on m.name = ins.name
  cross join lateral jsonb_array_elements(m.variants) with ordinality as x(v, o);

-- 4. Remove now-empty sample categories (Dosas, Idli & Vada, ...)
delete from menu_categories c
 where c.brand_id = (select b.id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas')
   and not exists (select 1 from menu_items i where i.category_id = c.id and i.deleted_at is null);

commit;

select c.name as section, count(i.id) as dishes
  from menu_categories c join menu_items i on i.category_id = c.id and i.deleted_at is null
 where c.brand_id = (select b.id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas')
 group by c.name, c.sort order by c.sort;
