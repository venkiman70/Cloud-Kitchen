-- Hours, closures and "Pause online ordering": who can change them, validation, audit,
-- and web orders refused while paused or on a closure date.
-- Run after the shim, migrations and seed (see README). Rolls back; leaves no data.
\set ON_ERROR_STOP on
begin;
do $$
declare
  t_aryas uuid := (select id from tenants where slug = 'aryas');
  mgr  uuid := gen_random_uuid();
  cook uuid := gen_random_uuid();
  v_variant uuid;
  v_tomorrow date := (now() at time zone 'America/Chicago')::date + 1;
  v_pickup timestamptz := ((((now() at time zone 'America/Chicago')::date + 1) + time '12:30') at time zone 'America/Chicago');
  r jsonb;
  n int;
  ok boolean;
  v_order jsonb;
begin
  insert into auth.users values (mgr, 'mgr@test'), (cook, 'cook@test');
  insert into tenant_members values (t_aryas, mgr, 'manager'), (t_aryas, cook, 'kitchen_staff');
  update tenant_settings set slot_capacity = 1000, lead_time_minutes = 20, pickup_hours = '{}'::jsonb where tenant_id = t_aryas;
  select v.id into v_variant from item_variants v join menu_items i on i.id = v.item_id
    join brands b on b.id = i.brand_id
   where v.tenant_id = t_aryas and b.slug = 'aryas' and v.deleted_at is null and i.deleted_at is null
     and i.is_available and not i.is_catering_only and i.collection_id is null and i.daily_limit is null
   limit 1;

  -- Kitchen staff: can pause, cannot change hours
  perform set_config('request.jwt.claim.sub', cook::text, true);
  set local role authenticated;
  ok := false;
  begin perform update_store_hours(t_aryas, '{"mon":["10:00","17:00"]}', '[]'); exception when others then ok := sqlerrm = 'NOT_ALLOWED'; end;
  if not ok then raise exception 'kitchen staff must not change hours'; end if;
  ok := false;
  begin update tenant_settings set pickup_hours = '{}' where tenant_id = t_aryas; exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'pickup_hours must not be directly updatable'; end if;
  r := set_online_ordering(t_aryas, true, 'Power cut', now() + interval '2 hours');
  if not (r->>'paused')::boolean or r->>'reason' <> 'Power cut' then raise exception 'pause failed: %', r; end if;
  reset role;

  -- Storefront sees the pause; web orders refused
  r := storefront_config('aryas', null);
  if not (r->'settings'->>'orderingPaused')::boolean or r->'settings'->>'pausedReason' <> 'Power cut' then
    raise exception 'storefront should show pause: %', r->'settings';
  end if;
  ok := false;
  begin
    perform create_order(jsonb_build_object('tenant','aryas','brand','aryas','pickupAt', v_pickup,
      'customer', jsonb_build_object('name','Test','phone','2145550123'),
      'items', jsonb_build_array(jsonb_build_object('variantId', v_variant, 'quantity', 1))));
  exception when others then ok := sqlerrm = 'ORDERING_PAUSED';
  end;
  if not ok then raise exception 'order should be refused while paused'; end if;

  -- Pause that has passed its resume time no longer blocks
  update tenant_settings set paused_until = now() - interval '1 minute' where tenant_id = t_aryas;
  if (storefront_config('aryas', null)->'settings'->>'orderingPaused')::boolean then raise exception 'auto-resume not respected'; end if;

  -- Resume (kitchen staff)
  perform set_config('request.jwt.claim.sub', cook::text, true);
  set local role authenticated;
  r := set_online_ordering(t_aryas, false);
  if (r->>'paused')::boolean then raise exception 'resume failed'; end if;
  ok := false;
  begin perform set_online_ordering(t_aryas, true, null, now() - interval '1 hour'); exception when others then ok := sqlerrm = 'BAD_RESUME_TIME'; end;
  if not ok then raise exception 'resume time in the past should be refused'; end if;
  reset role;

  -- Manager: hours validation
  perform set_config('request.jwt.claim.sub', mgr::text, true);
  set local role authenticated;
  ok := false;
  begin perform update_store_hours(t_aryas, '{"mon":["17:00","10:00"]}', '[]'); exception when others then ok := sqlerrm = 'BAD_HOURS:mon'; end;
  if not ok then raise exception 'close before open should be refused'; end if;
  ok := false;
  begin perform update_store_hours(t_aryas, '{"mon":["10:00","25:00"]}', '[]'); exception when others then ok := sqlerrm = 'BAD_HOURS:mon'; end;
  if not ok then raise exception 'bad time should be refused'; end if;
  ok := false;
  begin perform update_store_hours(t_aryas, '{}', '[{"date":"tomorrow"}]'); exception when others then ok := sqlerrm = 'BAD_CLOSURES'; end;
  if not ok then raise exception 'bad closure date should be refused'; end if;

  -- Manager: save hours (missing days become closed) and closures (past dates dropped, duplicates merged)
  r := update_store_hours(t_aryas,
    '{"mon":["10:00","17:00"],"tue":["10:00","17:00"],"wed":["10:00","17:00"],"thu":["10:00","17:00"],"fri":["10:00","17:00"],"sat":["10:00","16:45"],"sun":["10:00","16:00"]}',
    jsonb_build_array(jsonb_build_object('date', v_tomorrow::text, 'note', 'Staff day off'),
                      jsonb_build_object('date', v_tomorrow::text, 'note', 'dup'),
                      jsonb_build_object('date', '2020-01-01', 'note', 'old')));
  if r->'pickupHours'->'sun' <> '["10:00","16:00"]'::jsonb then raise exception 'hours not saved: %', r; end if;
  if jsonb_array_length(r->'closures') <> 1 or r->'closures'->0->>'date' <> v_tomorrow::text then
    raise exception 'closures not cleaned: %', r->'closures';
  end if;
  reset role;

  select count(*) into n from audit_log where tenant_id = t_aryas and entity = 'tenant_settings';
  if n <> 3 then raise exception 'expected 3 audit rows (pause, resume, hours), got %', n; end if;
  if not exists (select 1 from audit_log where action = 'hours_change' and actor_email = 'mgr@test') then raise exception 'hours change not audited'; end if;
  if not exists (select 1 from audit_log where action = 'pause_online_ordering' and actor_email = 'cook@test') then raise exception 'pause not audited'; end if;

  -- Web order on a closure date refused; the day after is fine
  ok := false;
  begin
    perform create_order(jsonb_build_object('tenant','aryas','brand','aryas','pickupAt', v_pickup,
      'customer', jsonb_build_object('name','Test','phone','2145550123'),
      'items', jsonb_build_array(jsonb_build_object('variantId', v_variant, 'quantity', 1))));
  exception when others then ok := sqlerrm = 'CLOSED_THAT_DAY';
  end;
  if not ok then raise exception 'order on a closure date should be refused'; end if;
  v_order := create_order(jsonb_build_object('tenant','aryas','brand','aryas','pickupAt', v_pickup + interval '1 day',
      'customer', jsonb_build_object('name','Test','phone','2145550123'),
      'items', jsonb_build_array(jsonb_build_object('variantId', v_variant, 'quantity', 1))));
  if v_order->>'orderNumber' is null then raise exception 'order the day after a closure should work'; end if;

  -- Anonymous visitors can't call the staff functions
  set local role anon;
  ok := false;
  begin perform set_online_ordering(t_aryas, true); exception when insufficient_privilege then ok := true; end;
  if not ok then raise exception 'anon must not pause ordering'; end if;
  reset role;

  raise notice 'HOURS AND PAUSE TESTS PASSED';
end $$;
rollback;
