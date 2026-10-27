-- Dish photos for the Aryas menu (files in public/menu/aryas/). Paste into Supabase → SQL Editor → Run.
-- Safe to run more than once.
update menu_items i set image_url = p.url
  from (values
    ('Golden Crisps (Samosa)',  '/menu/aryas/samosa.webp'),
    ('Paneer Puff Balls',       '/menu/aryas/paneer-puff-balls.webp'),
    ('Thava Fish',              '/menu/aryas/thava-fish.webp'),
    ('Papdi Chaat',             '/menu/aryas/papdi-chaat.webp'),
    ('Chicken Biryani',         '/menu/aryas/chicken-biryani.webp'),
    ('Garden Fresh Pulav',      '/menu/aryas/garden-fresh-pulav.webp'),
    ('Paneer Kathi Roll',       '/menu/aryas/paneer-kathi-roll.webp'),
    ('Chicken Kathi Roll',      '/menu/aryas/chicken-kathi-roll.webp'),
    ('Crisp ''N'' Roll Veggies', '/menu/aryas/veg-rolls.webp'),
    ('Sev Puri',                '/menu/aryas/sev-puri.webp'),
    ('Ragada Chaat',            '/menu/aryas/ragada-pattice.webp'),
    ('Crunchy Podi Rice',       '/menu/aryas/podi-rice.webp'),
    ('Egg Kathi Roll',          '/menu/aryas/egg-kathi-roll.webp')
  ) as p(name, url)
 where i.name = p.name and i.deleted_at is null
   and i.brand_id = (select b.id from brands b join tenants t on t.id = b.tenant_id where t.slug = 'aryas' and b.slug = 'aryas');

-- Dishes still without a photo
select b.name as brand, i.name as dish
  from menu_items i join brands b on b.id = i.brand_id
 where i.deleted_at is null and i.image_url is null
 order by b.sort, i.name;
