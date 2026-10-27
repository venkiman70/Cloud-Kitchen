-- Menu manager: photo upload is tenant-scoped to owners/managers; price changes and remove/restore are audited.
-- Run after the shim, migrations and seed (see README).
\set ON_ERROR_STOP on
begin;
do $$
declare
  t_aryas uuid := (select id from tenants where slug = 'aryas');
  t_other uuid := gen_random_uuid();
  mgr uuid := gen_random_uuid();
  cook uuid := gen_random_uuid();
  v item_variants;
  i menu_items;
  n int;
begin
  insert into tenants (id, slug, name) values (t_other, 'other-kitchen', 'Other Kitchen');
  insert into auth.users values (mgr, 'mgr@test'), (cook, 'cook@test');
  insert into tenant_members values (t_aryas, mgr, 'manager'), (t_aryas, cook, 'kitchen_staff');
  select * into v from item_variants where tenant_id = t_aryas and deleted_at is null limit 1;
  select * into i from menu_items where id = v.item_id;

  -- manager: price change + remove + restore, all audited
  perform set_config('request.jwt.claim.sub', mgr::text, true);
  set local role authenticated;
  update item_variants set price_cents = price_cents + 100 where id = v.id;
  update menu_items set deleted_at = now() where id = i.id;
  update menu_items set deleted_at = null where id = i.id;
  select count(*) into n from audit_log where tenant_id = t_aryas and actor_id = mgr;
  if n <> 3 then raise exception 'expected 3 audit rows, got %', n; end if;
  if not exists (select 1 from audit_log where action = 'price_change' and (new_value->>'price_cents')::int = v.price_cents + 100
                   and (old_value->>'price_cents')::int = v.price_cents and actor_email = 'mgr@test') then
    raise exception 'price audit row wrong'; end if;

  -- manager: may upload into own tenant folder, not another tenant's or a junk path
  insert into storage.objects (bucket_id, name) values ('menu', 'tenant/' || t_aryas || '/menu/' || i.id || '.webp');
  begin
    insert into storage.objects (bucket_id, name) values ('menu', 'tenant/' || t_other || '/menu/x.webp');
    raise exception 'LEAK: manager wrote to another tenant folder';
  exception when insufficient_privilege then null; end;
  begin
    insert into storage.objects (bucket_id, name) values ('menu', 'tenant/not-a-uuid/menu/x.webp');
    raise exception 'LEAK: junk path accepted';
  exception when insufficient_privilege then null; end;
  begin
    insert into audit_log (tenant_id, entity, entity_id, action) values (t_aryas, 'x', gen_random_uuid(), 'fake');
    raise exception 'LEAK: app can write audit_log';
  exception when insufficient_privilege then null; end;

  -- kitchen staff: no photo upload, no audit read, no item writes
  reset role;
  perform set_config('request.jwt.claim.sub', cook::text, true);
  set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name) values ('menu', 'tenant/' || t_aryas || '/menu/y.webp');
    raise exception 'LEAK: kitchen staff uploaded a photo';
  exception when insufficient_privilege then null; end;
  select count(*) into n from audit_log;
  if n <> 0 then raise exception 'LEAK: kitchen staff can read audit_log'; end if;
  update menu_items set deleted_at = now() where id = i.id;
  if exists (select 1 from menu_items where id = i.id and deleted_at is not null) then
    raise exception 'LEAK: kitchen staff removed an item'; end if;
  reset role;
  raise notice 'MENU MANAGER TESTS PASSED';
end $$;
rollback;
