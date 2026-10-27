-- Dish photos for every Aryas and AHIL dish on the menu (files in public/menu/).
-- Paste into Supabase → SQL Editor → Run. Safe to run more than once.
update menu_items i set image_url = p.url
  from (values
    -- Aryas Cuisine
    ('aryas', 'Golden Crisps (Samosa)',       '/menu/aryas/samosa.webp'),
    ('aryas', 'Naan Munchies',                '/menu/aryas/naan-munchies.webp'),
    ('aryas', 'Crisp ''N'' Roll Veggies',     '/menu/aryas/veg-rolls.webp'),
    ('aryas', 'Paneer Puff Balls',            '/menu/aryas/paneer-puff-balls.webp'),
    ('aryas', 'Egg Zing 65',                  '/menu/aryas/egg-zing-65.webp'),
    ('aryas', 'Egg Omelette',                 '/menu/aryas/egg-omelette.webp'),
    ('aryas', 'Crisp ''N'' Roll Chicken',     '/menu/aryas/crisp-n-roll-chicken.webp'),
    ('aryas', 'Flame-kissed Chicken',         '/menu/aryas/flame-kissed-chicken.webp'),
    ('aryas', 'Thava Fish',                   '/menu/aryas/thava-fish.webp'),
    ('aryas', 'Sev Puri',                     '/menu/aryas/sev-puri.webp'),
    ('aryas', 'Papdi Chaat',                  '/menu/aryas/papdi-chaat.webp'),
    ('aryas', 'Ragada Chaat',                 '/menu/aryas/ragada-chaat.webp'),
    ('aryas', 'Garden Fresh Pulav',           '/menu/aryas/garden-fresh-pulav.webp'),
    ('aryas', 'Crunchy Podi Rice',            '/menu/aryas/podi-rice.webp'),
    ('aryas', 'Vegetable Fried Rice',         '/menu/aryas/veg-fried-rice.webp'),
    ('aryas', 'Chicken Biryani',              '/menu/aryas/chicken-biryani.webp'),
    ('aryas', 'Paneer Kathi Roll',            '/menu/aryas/paneer-kathi-roll.webp'),
    ('aryas', 'Mixed Vegetable Kathi Roll',   '/menu/aryas/mixed-veg-kathi-roll.webp'),
    ('aryas', 'Egg Kathi Roll',               '/menu/aryas/egg-kathi-roll.webp'),
    ('aryas', 'Chicken Kathi Roll',           '/menu/aryas/chicken-kathi-roll.webp'),
    -- AHIL Diwali sweets
    ('ahil',  'Boondhi Ladoo',                '/menu/ahil/boondhi-ladoo.webp'),
    ('ahil',  'Besan Ladoo',                  '/menu/ahil/besan-ladoo.webp'),
    ('ahil',  'Dates & Nut Cake',             '/menu/ahil/dates-nut-cake.webp'),
    ('ahil',  'Special Mysore Pak',           '/menu/ahil/mysore-pak.webp'),
    ('ahil',  'Coconut Barfi',                '/menu/ahil/coconut-barfi.webp'),
    ('ahil',  'Peda Malai',                   '/menu/ahil/peda-malai.webp'),
    ('ahil',  'Peda Kesar',                   '/menu/ahil/peda-kesar.webp'),
    ('ahil',  'Almond Halwa',                 '/menu/ahil/almond-halwa.webp'),
    ('ahil',  'Tirunelveli Halwa',            '/menu/ahil/tirunelveli-halwa.webp'),
    ('ahil',  'Palkova',                      '/menu/ahil/palkova.webp'),
    ('ahil',  'Ghee Adhirasam (big size)',    '/menu/ahil/ghee-adhirasam.webp'),
    -- AHIL Diwali savouries
    ('ahil',  'Tamil Nadu Mixture',           '/menu/ahil/tamil-nadu-mixture.webp'),
    ('ahil',  'Karasev',                      '/menu/ahil/karasev.webp'),
    ('ahil',  'Ribbon Pakoda',                '/menu/ahil/ribbon-pakoda.webp'),
    ('ahil',  'Mullu Murukku',                '/menu/ahil/mullu-murukku.webp'),
    ('ahil',  'Thenkuzhal',                   '/menu/ahil/thenkuzhal.webp'),
    ('ahil',  'Thattai',                      '/menu/ahil/thattai.webp')
  ) as p(brand, name, url),
  brands b, tenants t
 where t.slug = 'aryas' and b.tenant_id = t.id and b.slug = p.brand
   and i.brand_id = b.id and i.name = p.name and i.deleted_at is null;

-- Dishes still without a photo (should be none)
select b.name as brand, i.name as dish
  from menu_items i join brands b on b.id = i.brand_id
 where i.deleted_at is null and i.image_url is null
 order by b.sort, i.name;
