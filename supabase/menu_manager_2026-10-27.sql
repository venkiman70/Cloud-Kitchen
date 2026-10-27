-- Menu manager (27 Oct 2026). Paste into Supabase → SQL Editor → Run. Safe to run more than once.
-- Same as supabase/migrations/20261027000005_menu_manager.sql.

-- ---------------------------------------------------------------------------
-- Audit log (who changed what, when). Written only by triggers, never by the app.
-- ---------------------------------------------------------------------------
create table if not exists public.audit_log (
  id          bigint generated always as identity primary key,
  tenant_id   uuid not null references public.tenants(id) on delete cascade,
  actor_id    uuid,
  actor_email text,
  entity      text not null,      -- 'menu_item' | 'item_variant'
  entity_id   uuid not null,
  action      text not null,      -- 'price_change' | 'remove' | 'restore'
  old_value   jsonb,
  new_value   jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists audit_log_tenant_time_idx on public.audit_log (tenant_id, created_at desc);

alter table public.audit_log enable row level security;
drop policy if exists audit_manager_read on public.audit_log;
create policy audit_manager_read on public.audit_log
  for select to authenticated using (public.is_manager(tenant_id));
revoke insert, update, delete on public.audit_log from anon, authenticated;

create or replace function public.audit_actor_email()
returns text language sql stable security definer set search_path = public, auth as $$
  select email from auth.users where id = auth.uid();
$$;

create or replace function public.audit_variant_price()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.price_cents is distinct from old.price_cents then
    insert into audit_log (tenant_id, actor_id, actor_email, entity, entity_id, action, old_value, new_value)
    values (new.tenant_id, auth.uid(), public.audit_actor_email(), 'item_variant', new.id, 'price_change',
            jsonb_build_object('item_id', old.item_id, 'label', old.label, 'price_cents', old.price_cents),
            jsonb_build_object('item_id', new.item_id, 'label', new.label, 'price_cents', new.price_cents));
  end if;
  return new;
end $$;

drop trigger if exists audit_variant_price on public.item_variants;
create trigger audit_variant_price after update of price_cents on public.item_variants
  for each row execute function public.audit_variant_price();

create or replace function public.audit_item_removal()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.deleted_at is null) <> (new.deleted_at is null) then
    insert into audit_log (tenant_id, actor_id, actor_email, entity, entity_id, action, old_value, new_value)
    values (new.tenant_id, auth.uid(), public.audit_actor_email(), 'menu_item', new.id,
            case when new.deleted_at is null then 'restore' else 'remove' end,
            jsonb_build_object('name', old.name, 'deleted_at', old.deleted_at),
            jsonb_build_object('name', new.name, 'deleted_at', new.deleted_at));
  end if;
  return new;
end $$;

drop trigger if exists audit_item_removal on public.menu_items;
create trigger audit_item_removal after update of deleted_at on public.menu_items
  for each row execute function public.audit_item_removal();

-- menu_items / item_variants writes: already owner + manager only
-- (items_manager_write / variants_manager_write use is_manager(tenant_id) in 0002_rls).

-- ---------------------------------------------------------------------------
-- Menu photos: public-read bucket, path tenant/{tenant_id}/menu/{item_id}.webp
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('menu', 'menu', true, 5242880, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Tenant id from "tenant/{uuid}/..."; null for any other shape (so a bad path is denied, not an error).
create or replace function public.storage_path_tenant(p text)
returns uuid language sql stable set search_path = public, storage as $$
  select case
    when (storage.foldername(p))[1] = 'tenant'
     and (storage.foldername(p))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((storage.foldername(p))[2])::uuid
  end
$$;
grant execute on function public.storage_path_tenant(text) to authenticated;

drop policy if exists menu_photos_manager_select on storage.objects;
drop policy if exists menu_photos_manager_insert on storage.objects;
drop policy if exists menu_photos_manager_update on storage.objects;
drop policy if exists menu_photos_manager_delete on storage.objects;

-- Upsert needs select + insert + update. Public URLs are served without a select policy.
create policy menu_photos_manager_select on storage.objects for select to authenticated
  using (bucket_id = 'menu' and public.auth_tenant_role(public.storage_path_tenant(name)) in ('owner', 'manager'));
create policy menu_photos_manager_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'menu' and public.auth_tenant_role(public.storage_path_tenant(name)) in ('owner', 'manager'));
create policy menu_photos_manager_update on storage.objects for update to authenticated
  using (bucket_id = 'menu' and public.auth_tenant_role(public.storage_path_tenant(name)) in ('owner', 'manager'))
  with check (bucket_id = 'menu' and public.auth_tenant_role(public.storage_path_tenant(name)) in ('owner', 'manager'));
create policy menu_photos_manager_delete on storage.objects for delete to authenticated
  using (bucket_id = 'menu' and public.auth_tenant_role(public.storage_path_tenant(name)) in ('owner', 'manager'));
