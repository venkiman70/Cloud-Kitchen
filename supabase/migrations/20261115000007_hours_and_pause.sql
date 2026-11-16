-- Hours, closures and "Pause online ordering" (15 Nov 2026). Safe to run more than once.
--
-- * Owners and managers edit weekly pickup hours and closure dates from Admin → Hours
--   (no more SQL for hours). Every save is written to audit_log.
-- * Any staff member (kitchen staff too) can pause online ordering in an emergency and
--   turn it back on, with a reason and an optional automatic resume time. Audited.
-- * Web orders are refused in the database while paused or on a closure date, whatever the
--   browser shows.

-- ---------------------------------------------------------------------------
-- Settings columns
-- ---------------------------------------------------------------------------
-- closures: [{"date": "2026-11-26", "note": "Closed for Thanksgiving"}, ...]
alter table public.tenant_settings add column if not exists closures jsonb not null default '[]'::jsonb;
alter table public.tenant_settings add column if not exists ordering_paused boolean not null default false;
alter table public.tenant_settings add column if not exists paused_reason text;
alter table public.tenant_settings add column if not exists paused_until timestamptz;
alter table public.tenant_settings add column if not exists paused_at timestamptz;
alter table public.tenant_settings add column if not exists paused_by_email text;

alter table public.tenant_settings drop constraint if exists tenant_settings_closures_array;
alter table public.tenant_settings add constraint tenant_settings_closures_array check (jsonb_typeof(closures) = 'array');

-- Hours, closures and pause change only through the functions below (validated + audited).
revoke update (pickup_hours) on public.tenant_settings from authenticated;

-- ---------------------------------------------------------------------------
-- Is online ordering paused right now? (respects the automatic resume time)
-- ---------------------------------------------------------------------------
create or replace function public.ordering_paused_now(s public.tenant_settings)
returns boolean language sql stable as $$
  select coalesce(s.ordering_paused, false) and (s.paused_until is null or s.paused_until > now());
$$;

-- ---------------------------------------------------------------------------
-- Guard on every new web order: paused or closure date -> refused.
-- (create_order already checks weekly hours.)
-- ---------------------------------------------------------------------------
create or replace function public.guard_order_open()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  s tenant_settings;
  v_date text;
begin
  if new.channel <> 'web' then return new; end if;
  select * into s from tenant_settings where tenant_id = new.tenant_id;
  if s.tenant_id is null then return new; end if;
  if public.ordering_paused_now(s) then raise exception 'ORDERING_PAUSED'; end if;
  v_date := to_char(new.pickup_at at time zone s.timezone, 'YYYY-MM-DD');
  if exists (select 1 from jsonb_array_elements(s.closures) c where c->>'date' = v_date) then
    raise exception 'CLOSED_THAT_DAY';
  end if;
  return new;
end $$;

drop trigger if exists guard_order_open on public.orders;
create trigger guard_order_open before insert on public.orders
  for each row execute function public.guard_order_open();

-- ---------------------------------------------------------------------------
-- update_store_hours: owners / managers save weekly hours and closures.
--   p_hours:    {"mon": ["10:00","17:00"], ..., "sun": null}   (all 7 days; null = closed)
--   p_closures: [{"date": "2026-11-26", "note": "Thanksgiving"}]   (past dates are dropped)
-- ---------------------------------------------------------------------------
create or replace function public.update_store_hours(p_tenant uuid, p_hours jsonb, p_closures jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s        tenant_settings;
  v_day    text;
  v_win    jsonb;
  v_hours  jsonb := '{}'::jsonb;
  v_clos   jsonb;
  v_today  date;
begin
  if not public.is_manager(p_tenant) then raise exception 'NOT_ALLOWED'; end if;
  select * into s from tenant_settings where tenant_id = p_tenant for update;
  if s.tenant_id is null then raise exception 'TENANT_NOT_FOUND'; end if;
  v_today := (now() at time zone s.timezone)::date;

  if jsonb_typeof(p_hours) <> 'object' then raise exception 'BAD_HOURS'; end if;
  foreach v_day in array array['mon','tue','wed','thu','fri','sat','sun'] loop
    v_win := p_hours -> v_day;
    if v_win is null or jsonb_typeof(v_win) = 'null' then
      v_hours := v_hours || jsonb_build_object(v_day, null);
    elsif jsonb_typeof(v_win) = 'array' and jsonb_array_length(v_win) = 2
          and (v_win->>0) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          and (v_win->>1) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
          and (v_win->>0)::time < (v_win->>1)::time then
      v_hours := v_hours || jsonb_build_object(v_day, jsonb_build_array(v_win->>0, v_win->>1));
    else
      raise exception 'BAD_HOURS:%', v_day;
    end if;
  end loop;

  if p_closures is null then p_closures := '[]'::jsonb; end if;
  if jsonb_typeof(p_closures) <> 'array' or jsonb_array_length(p_closures) > 200 then raise exception 'BAD_CLOSURES'; end if;
  if exists (select 1 from jsonb_array_elements(p_closures) c
              where jsonb_typeof(c) <> 'object' or coalesce(c->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$') then
    raise exception 'BAD_CLOSURES';
  end if;
  begin
    select coalesce(jsonb_agg(jsonb_build_object('date', d, 'note', note) order by d), '[]'::jsonb) into v_clos
      from (select distinct on ((c->>'date')::date) (c->>'date')::date as d,
                   nullif(left(trim(coalesce(c->>'note', '')), 120), '') as note
              from jsonb_array_elements(p_closures) c
             order by (c->>'date')::date) x
     where d >= v_today;
  exception when others then raise exception 'BAD_CLOSURES';
  end;

  if v_hours is distinct from s.pickup_hours or v_clos is distinct from s.closures then
    update tenant_settings set pickup_hours = v_hours, closures = v_clos where tenant_id = p_tenant;
    insert into audit_log (tenant_id, actor_id, actor_email, entity, entity_id, action, old_value, new_value)
    values (p_tenant, auth.uid(), public.audit_actor_email(), 'tenant_settings', p_tenant, 'hours_change',
            jsonb_build_object('pickup_hours', s.pickup_hours, 'closures', s.closures),
            jsonb_build_object('pickup_hours', v_hours, 'closures', v_clos));
  end if;
  return jsonb_build_object('pickupHours', v_hours, 'closures', v_clos);
end $$;

-- ---------------------------------------------------------------------------
-- Online ordering status for the staff screens (any staff member)
-- ---------------------------------------------------------------------------
create or replace function public.online_ordering_status(p_tenant uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s tenant_settings;
begin
  if not public.is_staff(p_tenant) then raise exception 'NOT_ALLOWED'; end if;
  select * into s from tenant_settings where tenant_id = p_tenant;
  return jsonb_build_object(
    'paused', public.ordering_paused_now(s), 'reason', s.paused_reason,
    'until', case when public.ordering_paused_now(s) then s.paused_until end,
    'pausedAt', s.paused_at, 'pausedBy', s.paused_by_email,
    'pickupHours', s.pickup_hours, 'closures', s.closures, 'timezone', s.timezone);
end $$;

-- ---------------------------------------------------------------------------
-- set_online_ordering: pause (with reason, optional resume time) or resume.
-- Any staff member may do this; it's the emergency switch.
-- ---------------------------------------------------------------------------
create or replace function public.set_online_ordering(p_tenant uuid, p_paused boolean, p_reason text default null, p_until timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s tenant_settings;
  v_reason text := nullif(left(trim(coalesce(p_reason, '')), 200), '');
begin
  if not public.is_staff(p_tenant) then raise exception 'NOT_ALLOWED'; end if;
  select * into s from tenant_settings where tenant_id = p_tenant for update;
  if s.tenant_id is null then raise exception 'TENANT_NOT_FOUND'; end if;
  if p_paused and p_until is not null and p_until <= now() then raise exception 'BAD_RESUME_TIME'; end if;

  if p_paused then
    update tenant_settings set ordering_paused = true, paused_reason = v_reason, paused_until = p_until,
           paused_at = now(), paused_by_email = public.audit_actor_email()
     where tenant_id = p_tenant;
  else
    update tenant_settings set ordering_paused = false, paused_reason = null, paused_until = null,
           paused_at = null, paused_by_email = null
     where tenant_id = p_tenant;
  end if;

  insert into audit_log (tenant_id, actor_id, actor_email, entity, entity_id, action, old_value, new_value)
  values (p_tenant, auth.uid(), public.audit_actor_email(), 'tenant_settings', p_tenant,
          case when p_paused then 'pause_online_ordering' else 'resume_online_ordering' end,
          jsonb_build_object('paused', public.ordering_paused_now(s), 'reason', s.paused_reason, 'until', s.paused_until),
          jsonb_build_object('paused', p_paused, 'reason', case when p_paused then v_reason end, 'until', case when p_paused then p_until end));

  return public.online_ordering_status(p_tenant);
end $$;

-- ---------------------------------------------------------------------------
-- Storefront config: also returns closures and the pause state
-- ---------------------------------------------------------------------------
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
      'payAtPickup', s.pay_at_pickup, 'payAtPickupMaxCents', s.pay_at_pickup_max_cents,
      'bannerUrl', s.banner_url,
      'closures', s.closures,
      'orderingPaused', public.ordering_paused_now(s),
      'pausedReason', case when public.ordering_paused_now(s) then s.paused_reason end,
      'pausedUntil', case when public.ordering_paused_now(s) then s.paused_until end),
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

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke execute on function public.ordering_paused_now(public.tenant_settings)        from public, anon, authenticated;
revoke execute on function public.guard_order_open()                                 from public, anon, authenticated;
revoke execute on function public.update_store_hours(uuid, jsonb, jsonb)             from public, anon;
revoke execute on function public.online_ordering_status(uuid)                      from public, anon;
revoke execute on function public.set_online_ordering(uuid, boolean, text, timestamptz) from public, anon;
revoke execute on function public.storefront_config(text, text)                      from public;

grant execute on function public.update_store_hours(uuid, jsonb, jsonb)              to authenticated;
grant execute on function public.online_ordering_status(uuid)                       to authenticated;
grant execute on function public.set_online_ordering(uuid, boolean, text, timestamptz) to authenticated;
grant execute on function public.storefront_config(text, text)                       to anon, authenticated;
