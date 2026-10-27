-- Branding: a home-page banner per kitchen, returned to the storefront.
alter table public.tenant_settings add column if not exists banner_url text;
grant update (banner_url) on public.tenant_settings to authenticated;

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
      'payAtPickup', s.pay_at_pickup, 'bannerUrl', s.banner_url),
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

grant execute on function public.storefront_config(text, text) to anon, authenticated;
