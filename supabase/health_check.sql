-- HEALTH CHECK: paste into Supabase → SQL Editor → Run. Read-only; it changes nothing.
-- Every row should show ✅. For a ❌, the "fix" column says what to run or do.
with
  t as (select id from tenants where slug = 'aryas'),
  aryas as (select b.* from brands b join t on b.tenant_id = t.id where b.slug = 'aryas'),
  ahil  as (select b.* from brands b join t on b.tenant_id = t.id where b.slug = 'ahil'),
  live  as (select i.* from menu_items i join t on i.tenant_id = t.id where i.deleted_at is null),
  checks(n, step, ok, detail, fix) as (values
    (1, 'Database set up',
        exists (select 1 from t) and exists (select 1 from aryas) and exists (select 1 from ahil),
        (select count(*) from brands where tenant_id = (select id from t))::text || ' brands',
        'Run supabase/setup_all.sql (once, on an empty project)'),
    (2, 'Banner column added (branding)',
        exists (select 1 from information_schema.columns where table_name = 'tenant_settings' and column_name = 'banner_url'),
        null, 'Run supabase/branding_2026-10-26.sql'),
    (3, 'Real Aryas menu loaded',
        (select count(*) from live where brand_id = (select id from aryas) and not is_sample) >= 20
        and not exists (select 1 from live where is_sample),
        (select count(*) from live where brand_id = (select id from aryas))::text || ' Aryas dishes, '
          || (select count(*) from live where is_sample)::text || ' sample dishes still showing',
        'Run supabase/menu_aryas_ubereats_2026-10-26.sql'),
    (4, 'AHIL Diwali menu loaded',
        (select count(*) from live where brand_id = (select id from ahil)) >= 17,
        (select count(*) from live where brand_id = (select id from ahil))::text || ' AHIL items', 'Run supabase/setup_all.sql'),
    (5, 'Brand colours and logos',
        (select theme ? 'hero' from aryas) and (select theme ? 'hero' from ahil),
        (select theme->>'accent' from aryas) || ' / ' || (select theme->>'accent' from ahil),
        'Run supabase/branding_2026-10-26.sql'),
    (6, 'Home page banner',
        coalesce((select (to_jsonb(s) ->> 'banner_url') is not null from tenant_settings s where s.tenant_id = (select id from t)), false),
        null, 'Run supabase/branding_2026-10-26.sql'),
    (7, 'Every dish has a photo',
        not exists (select 1 from live where image_url is null),
        (select count(*) from live where image_url is null)::text || ' without a photo: '
          || coalesce((select string_agg(name, ', ' order by name) from (select name from live where image_url is null limit 5) x), '—'),
        'Run supabase/menu_photos_2026-10-26.sql'),
    (8, 'Diwali pre-order dates set',
        exists (select 1 from menu_collections c where c.brand_id = (select id from ahil) and c.slug = 'diwali-2026'),
        (select 'cutoff ' || to_char(order_cutoff_at at time zone 'America/Chicago', 'Dy DD Mon HH12:MI am')
              || ', pickup ' || coalesce(array_to_string(pickup_dates, ', '), 'any open day')
           from menu_collections where slug = 'diwali-2026' limit 1),
        'Run supabase/setup_all.sql'),
    (9, 'Staff login: an owner exists',
        exists (select 1 from tenant_members m where m.tenant_id = (select id from t) and m.role = 'owner'),
        (select string_agg(u.email || ' (' || m.role || ')', ', ') from tenant_members m join auth.users u on u.id = m.user_id where m.tenant_id = (select id from t)),
        'Create your user in Authentication → Users, then run the owner SQL from the chat'),
    (10, 'Platform admin (you)',
        exists (select 1 from platform_admins),
        (select string_agg(u.email, ', ') from platform_admins p join auth.users u on u.id = p.user_id),
        'Run the owner SQL from the chat'),
    (11, 'Stripe connected (payments)',
        exists (select 1 from orders where payment_status = 'paid'),
        (select count(*) from orders where payment_status = 'paid')::text || ' paid test orders',
        'Not yet: Stripe step comes next (needs the terminal)')
  )
select n as "#", step, case when ok then '✅' else '❌' end as status, detail, case when ok then '' else fix end as fix
  from checks order by n;
