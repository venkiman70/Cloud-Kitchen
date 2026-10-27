-- 25 more Aryas dishes from the menu poster, photos already loaded (public/menu/aryas/).
--
-- HOW TO USE
--   1. Replace every 0.00 in the "price" column below with the real price (e.g. 7.99).
--      Delete any line for a dish Aryas doesn't sell.
--   2. Paste into Supabase → SQL Editor → Run.
--   The script refuses to run while any price is still 0.00, so no dish can go live for free.
--   Curries are listed as 16 oz (as on Uber Eats); change the size label if needed.

begin;

create temp table _new (cat text, name text, descr text, diet diet_type, protein text, allergens text[], station text, size text, unit text, price numeric, photo text) on commit drop;
insert into _new values
 -- category        dish                     description                                         diet      protein    allergens  station         size     unit     price  photo
 ('Appetizers',     'Corn Fritters',         'Crispy spiced sweet-corn fritters.',               'veg',    null,      '{}',      'Fryer/Snacks', 'Regular','plate', 0.00, 'corn-fritters'),
 ('Appetizers',     'Veg Pakora',            'Onion and vegetable fritters in gram-flour batter.','veg',   null,      '{}',      'Fryer/Snacks', 'Regular','plate', 0.00, 'veg-pakora'),
 ('Appetizers',     'Chicken 65',            'Spicy fried chicken with curry leaves.',           'non_veg','chicken', '{}',      'Fryer/Snacks', 'Regular','plate', 0.00, 'chicken-65'),
 ('Appetizers',     'Chicken Wings',         'Masala-glazed chicken wings.',                     'non_veg','chicken', '{}',      'Tandoor',      'Regular','plate', 0.00, 'chicken-wings'),
 ('Appetizers',     'Pepper Chicken',        'Chicken tossed with black pepper and onions.',     'non_veg','chicken', '{}',      'Curry',        'Regular','plate', 0.00, 'pepper-chicken'),
 ('Appetizers',     'Fish Fry',              'Spice-crusted pan-fried fish.',                    'non_veg','fish',    '{}',      'Dosa tawa',    'Regular','plate', 0.00, 'fish-fry'),
 ('Chaat Corner',   'Dahi Puri',             'Crisp puris with potato, yogurt and chutneys.',    'veg',    null,      '{dairy}', 'Fryer/Snacks', 'Regular','plate', 0.00, 'dahi-puri'),
 ('Chaat Corner',   'Bhel Puri',             'Puffed rice, sev, onion and tangy chutneys.',      'veg',    null,      '{}',      'Fryer/Snacks', 'Regular','plate', 0.00, 'bhel-puri'),
 ('Chaat Corner',   'Aloo Tikki Chaat',      'Potato patties with yogurt, chutneys and sev.',    'veg',    null,      '{dairy}', 'Fryer/Snacks', 'Regular','plate', 0.00, 'aloo-tikki-chaat'),
 ('Soups',          'Tomato Soup',           'Creamy spiced tomato soup.',                       'veg',    null,      '{dairy}', 'Curry',        'Bowl',   'cup',   0.00, 'tomato-soup'),
 ('Soups',          'Sweet Corn Soup',       'Sweet corn and vegetable soup.',                   'veg',    null,      '{}',      'Curry',        'Bowl',   'cup',   0.00, 'sweet-corn-soup'),
 ('Rice & Biryani', 'Vegetable Biryani',     'Basmati rice layered with vegetables and spices.', 'veg',    null,      '{}',      'Curry',        'Regular','each',  0.00, 'veg-biryani'),
 ('Rice & Biryani', 'Egg Biryani',           'Biryani rice with masala eggs.',                   'egg',    'egg',     '{}',      'Curry',        'Regular','each',  0.00, 'egg-biryani'),
 ('Rice & Biryani', 'Plain Rice',            'Steamed basmati rice.',                            'veg',    null,      '{}',      'Curry',        'Regular','each',  0.00, 'plain-rice'),
 ('Rice & Biryani', 'Lemon Rice',            'Tangy lemon rice with peanuts and curry leaves.',  'veg',    null,      '{nuts}',  'Curry',        'Regular','each',  0.00, 'lemon-rice'),
 ('Breads',         'Plain Naan',            'Soft tandoor-baked naan.',                         'veg',    null,      '{gluten,dairy}','Tandoor','1 pc',  'each',  0.00, 'plain-naan'),
 ('Breads',         'Garlic Naan',           'Naan with garlic and coriander.',                  'veg',    null,      '{gluten,dairy}','Tandoor','1 pc',  'each',  0.00, 'garlic-naan'),
 ('Breads',         'Chapati / Roti',        'Whole-wheat flatbread.',                           'veg',    null,      '{gluten}','Dosa tawa',    '1 pc',   'each',  0.00, 'chapati'),
 ('Veg Curries',    'Paneer Butter Masala',  'Paneer in a rich tomato-butter gravy.',            'veg',    null,      '{dairy}', 'Curry',        '16 oz',  'each',  0.00, 'paneer-butter-masala'),
 ('Veg Curries',    'Dal Tadka',             'Yellow lentils tempered with cumin and garlic.',   'veg',    null,      '{}',      'Curry',        '16 oz',  'each',  0.00, 'dal-tadka'),
 ('Veg Curries',    'Mixed Vegetable Curry', 'Seasonal vegetables in a spiced gravy.',           'veg',    null,      '{}',      'Curry',        '16 oz',  'each',  0.00, 'mixed-vegetable-curry'),
 ('Veg Curries',    'Chana Masala',          'Chickpeas in a tangy onion-tomato masala.',        'veg',    null,      '{}',      'Curry',        '16 oz',  'each',  0.00, 'chana-masala'),
 ('Non-Veg Curries','Butter Chicken',        'Tandoori chicken in a creamy tomato gravy.',       'non_veg','chicken', '{dairy}', 'Curry',        '16 oz',  'each',  0.00, 'butter-chicken'),
 ('Non-Veg Curries','Chicken Curry',         'Home-style chicken curry.',                        'non_veg','chicken', '{}',      'Curry',        '16 oz',  'each',  0.00, 'chicken-curry'),
 ('Non-Veg Curries','Egg Curry',             'Boiled eggs in an onion-tomato gravy.',            'egg',    'egg',     '{}',      'Curry',        '16 oz',  'each',  0.00, 'egg-curry');

-- Safety: stop if any price wasn't filled in
do $$ begin
  if exists (select 1 from _new where price is null or price <= 0) then
    raise exception 'Fill in every price first. Still at 0.00: %', (select string_agg(name, ', ') from _new where price is null or price <= 0);
  end if;
end $$;

-- Sections, in menu order
with b as (select b.id as brand_id, b.tenant_id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas')
insert into menu_categories (tenant_id, brand_id, name, sort)
select b.tenant_id, b.brand_id, c.name, c.sort from b,
  (values ('Appetizers',1),('Chaat Corner',2),('Soups',3),('Rice & Biryani',4),('Breads',5),('Veg Curries',6),('Non-Veg Curries',7),('Kathi Rolls',8)) as c(name, sort)
on conflict (brand_id, name) do update set sort = excluded.sort;

-- Dishes (skips any dish with the same name already on the menu)
with b as (select b.id as brand_id, b.tenant_id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas'),
ins as (
  insert into menu_items (tenant_id, brand_id, category_id, name, description, diet, protein, allergens, station, image_url, sort, is_sample)
  select b.tenant_id, b.brand_id, c.id, n.name, n.descr, n.diet, n.protein, n.allergens, n.station, '/menu/aryas/' || n.photo || '.webp',
         100 + row_number() over (), false
    from _new n cross join b join menu_categories c on c.brand_id = b.brand_id and c.name = n.cat
   where not exists (select 1 from menu_items m where m.brand_id = b.brand_id and m.name = n.name and m.deleted_at is null)
  returning id, tenant_id, name
)
insert into item_variants (tenant_id, item_id, label, pack_qty, pack_unit, price_cents)
select ins.tenant_id, ins.id, n.size, 1, n.unit, round(n.price * 100)::int
  from ins join _new n on n.name = ins.name;

commit;

select c.name as section, count(i.id) as dishes
  from menu_categories c left join menu_items i on i.category_id = c.id and i.deleted_at is null
 where c.brand_id = (select b.id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas')
 group by c.name, c.sort order by c.sort;
