-- =============================================================================
-- iTULOD mobile — migration 008: server-authoritative fares + notifications
-- Run AFTER 005. Idempotent.
--
--   1. estimated_fare is recomputed from the vehicle's rate card on INSERT so
--      the client can no longer choose its own fare. distance_km is clamped to
--      a sane ceiling. (005 already locks the fare against later edits.)
--   2. Booking-lifecycle notifications ("rider accepted", "trip started",
--      "completed", "cancelled") are written by a database trigger instead of
--      the client — 005 removed the client's INSERT privilege on notifications.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. recompute estimated_fare on insert
-- ---------------------------------------------------------------------------
create or replace function public.booking_recompute_fare()
returns trigger as $$
declare
  v_base numeric(10,2);
  v_rate numeric(10,2);
  km     numeric(10,2);
begin
  -- Trust nothing the client sent for money. Cap an implausible distance so a
  -- tampered request can't bill a cross-country trip.
  km := least(greatest(coalesce(new.distance_km, 1), 0.1), 200);
  new.distance_km := km;

  if new.vehicle_id is not null then
    select base_fare, per_km_rate into v_base, v_rate
    from public.vehicles where id = new.vehicle_id;

    if v_base is not null then
      new.estimated_fare := round(v_base + v_rate * km, 2);
    end if;
  end if;

  -- final_fare is never set at creation time.
  new.final_fare := null;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_transport_recompute_fare on public.transport_bookings;
create trigger trg_transport_recompute_fare before insert on public.transport_bookings
  for each row execute function public.booking_recompute_fare();

drop trigger if exists trg_food_recompute_fare on public.food_deliveries;
create trigger trg_food_recompute_fare before insert on public.food_deliveries
  for each row execute function public.booking_recompute_fare();

drop trigger if exists trg_parcel_recompute_fare on public.parcel_deliveries;
create trigger trg_parcel_recompute_fare before insert on public.parcel_deliveries
  for each row execute function public.booking_recompute_fare();

-- ---------------------------------------------------------------------------
-- 2. lifecycle notifications
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_booking_change()
returns trigger as $$
declare
  kind text := tg_argv[0];                      -- 'ride' | 'food' | 'parcel'
begin
  -- rider assigned
  if old.rider_id is null and new.rider_id is not null then
    insert into public.notifications (user_id, title, message)
    values (new.customer_id, 'Rider assigned',
            'A rider accepted your ' || kind || ' booking.');
  end if;

  -- status transitions
  if new.status is distinct from old.status then
    if new.status = 'ongoing' then
      insert into public.notifications (user_id, title, message)
      values (new.customer_id, 'Trip started',
              'Your rider has started your ' || kind || ' booking.');
    elsif new.status = 'completed' then
      insert into public.notifications (user_id, title, message)
      values (new.customer_id, 'Booking completed',
              'Your ' || kind || ' booking is complete. Thanks for choosing iTULOD!');
    elsif new.status = 'cancelled' and auth.uid() is distinct from new.customer_id then
      insert into public.notifications (user_id, title, message)
      values (new.customer_id, 'Booking cancelled',
              'Your ' || kind || ' booking was cancelled by the rider.');
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_transport_notify on public.transport_bookings;
create trigger trg_transport_notify after update on public.transport_bookings
  for each row execute function public.notify_on_booking_change('ride');

drop trigger if exists trg_food_notify on public.food_deliveries;
create trigger trg_food_notify after update on public.food_deliveries
  for each row execute function public.notify_on_booking_change('food');

drop trigger if exists trg_parcel_notify on public.parcel_deliveries;
create trigger trg_parcel_notify after update on public.parcel_deliveries
  for each row execute function public.notify_on_booking_change('parcel');

do $$
begin
  execute 'alter publication supabase_realtime add table public.notifications';
exception when duplicate_object then null;
end $$;
