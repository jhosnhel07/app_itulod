-- =============================================================================
-- iTULOD mobile — migration 009b: automatic booking expiration
-- Run AFTER 20260914000001 (which adds the 'expired' / 'no_show' statuses).
-- Idempotent / safe to re-run.
--
-- This app books on demand — there is no separate "scheduled date/time"
-- field, a booking is always "now". So the two grace-period clocks map onto
-- the two moments an on-demand booking actually commits to a time:
--   * Pending  — the clock starts at created_at (the instant the customer
--     asked for a ride/delivery). If no rider claims it within 15 minutes,
--     it expires.
--   * Accepted — the clock restarts at accepted_at (the instant a rider
--     confirmed). If the trip never starts or finishes within 15 minutes of
--     that confirmation, it expires — this is the "Confirmed" grace period
--     from the spec, anchored to the actual commitment time this app has.
--
-- 'ongoing' / 'completed' / 'cancelled' / 'expired' / 'no_show' bookings are
-- never touched by the sweep — a trip in progress, or one already finished,
-- can never be auto-expired.
--
-- Server time (Postgres `now()`, always UTC internally) is the only clock
-- used — never a client-supplied timestamp — so nobody can manipulate it by
-- changing their device clock. A pg_cron job re-runs the sweep every minute
-- so this works even with the app fully closed, and survives restarts since
-- it's database state, not in-process memory. Every dashboard also calls the
-- same function defensively on open (see RealtimeRefreshMixin in the app),
-- so it still works even if pg_cron isn't available on this project's plan.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. accepted_at — stamped the moment a rider is confirmed onto a booking.
-- ---------------------------------------------------------------------------
alter table public.transport_bookings add column if not exists accepted_at timestamptz;
alter table public.food_deliveries    add column if not exists accepted_at timestamptz;
alter table public.parcel_deliveries  add column if not exists accepted_at timestamptz;

-- Backfill rows accepted before this migration existed, so they don't read
-- as "accepted since the epoch" and get swept immediately.
update public.transport_bookings set accepted_at = created_at where rider_id is not null and accepted_at is null;
update public.food_deliveries    set accepted_at = created_at where rider_id is not null and accepted_at is null;
update public.parcel_deliveries  set accepted_at = created_at where rider_id is not null and accepted_at is null;

-- ---------------------------------------------------------------------------
-- 2. is_trusted_writer(): also trust the expiration sweep itself, so it can
--    flip any customer's/rider's booking regardless of who (or what — pg_cron
--    has no caller identity at all) invoked it. The flag is transaction-local
--    (set_config's 3rd arg = true) so it can never leak into an unrelated
--    request.
-- ---------------------------------------------------------------------------
create or replace function public.is_trusted_writer()
returns boolean as $$
  select coalesce(auth.role(), '') = 'service_role'
      or auth.jwt() ->> 'role' = 'service_role'
      or public.is_admin()
      or coalesce(current_setting('itulod.system_sweep', true), '') = 'on';
$$ language sql security definer stable;

-- ---------------------------------------------------------------------------
-- 3. booking_before_update: freeze terminal bookings, and stamp accepted_at.
--    (Same function as migration 005 / 008's later edits — replaced whole so
--    the diff is easy to read; behaviour is additive, nothing removed.)
-- ---------------------------------------------------------------------------
create or replace function public.booking_before_update()
returns trigger as $$
declare
  kind        text := tg_argv[0];               -- 'transport' | 'food' | 'parcel'
  uid         uuid := auth.uid();
  cfg         public.platform_config%rowtype;
  fare        numeric(10,2);
  commission  numeric(10,2);
  min_fare    numeric(10,2);
begin
  -- A terminal booking is frozen for everyone except the system itself —
  -- "expired bookings should no longer be editable, confirmed, or used", and
  -- the same protection now also covers completed/cancelled/no_show, which
  -- were previously (harmlessly, but incorrectly) still writable.
  if not public.is_trusted_writer()
     and old.status in ('completed', 'cancelled', 'expired', 'no_show') then
    raise exception 'this booking is % and can no longer be changed', old.status;
  end if;

  -- Stamp the confirmation moment — the anchor for the "accepted" grace
  -- period below. Applies no matter who performs the assignment.
  if old.rider_id is null and new.rider_id is not null and new.accepted_at is null then
    new.accepted_at := now();
  end if;

  -- ---- client-write guard --------------------------------------------------
  if not public.is_trusted_writer() then
    if new.estimated_fare is distinct from old.estimated_fare then
      raise exception 'estimated_fare is immutable';
    end if;
    if new.final_fare is distinct from old.final_fare then
      raise exception 'final_fare is set by the system';
    end if;
    if new.customer_id is distinct from old.customer_id then
      raise exception 'customer_id is immutable';
    end if;

    if uid = old.customer_id then
      -- customer: may cancel, and may set payment fields while still pending
      if new.status is distinct from old.status
         and new.status <> 'cancelled' then
        raise exception 'customers can only cancel a booking';
      end if;
      if new.rider_id is distinct from old.rider_id then
        raise exception 'customers cannot assign a rider';
      end if;
      if new.payment_status is distinct from old.payment_status then
        raise exception 'payment_status is set by the payment system';
      end if;
      if (new.payment_method is distinct from old.payment_method
          or new.paymongo_reference is distinct from old.paymongo_reference)
         and old.status <> 'pending' then
        raise exception 'payment method can only change while the booking is pending';
      end if;

    elsif old.rider_id is null and new.rider_id = uid then
      -- rider claiming an open job
      if not public.is_approved_rider() then
        raise exception 'only an approved rider can accept bookings';
      end if;
      if old.status <> 'pending' then
        raise exception 'this booking is no longer available';
      end if;
      if new.status <> 'accepted' then
        raise exception 'a claimed booking must move to "accepted"';
      end if;
      if new.payment_status is distinct from old.payment_status
         or new.payment_method is distinct from old.payment_method then
        raise exception 'riders cannot change payment fields';
      end if;

    elsif uid = old.rider_id then
      -- assigned rider advancing the job
      if new.rider_id is distinct from old.rider_id then
        raise exception 'riders cannot reassign a booking';
      end if;
      if new.status not in ('accepted', 'ongoing', 'completed', 'cancelled', 'no_show') then
        raise exception 'invalid status transition';
      end if;
      if new.payment_status is distinct from old.payment_status then
        raise exception 'payment_status is set by the system';
      end if;

    else
      raise exception 'not allowed to update this booking';
    end if;
  end if;

  -- ---- on completion: lock the fare + create the payout -------------------
  if new.status = 'completed' and old.status is distinct from 'completed' then
    select * into cfg from public.platform_config where id;

    fare := coalesce(new.final_fare, new.estimated_fare);
    if fare is null or fare <= 0 then
      raise exception 'cannot complete a booking with no fare';
    end if;

    if kind <> 'transport' and new.estimated_fare is not null then
      if fare > new.estimated_fare * cfg.fare_max_multiplier then
        raise exception 'final fare % is more than %x the % estimate',
          fare, cfg.fare_max_multiplier, new.estimated_fare;
      end if;
      min_fare := greatest(cfg.fare_min, round(new.estimated_fare * 0.5, 2));
      if fare < min_fare then
        raise exception 'final fare % is below the minimum %', fare, min_fare;
      end if;
    end if;

    new.final_fare := fare;
    commission := round(fare * cfg.commission_rate, 2);

    if coalesce(new.payment_method, 'cash') = 'cash' then
      new.payment_status := 'paid';
    end if;

    insert into public.payments
      (customer_id, rider_id, booking_type, booking_id, amount,
       platform_commission, rider_payout, method, status)
    values
      (new.customer_id, new.rider_id, kind, new.id, fare,
       commission, fare - commission, coalesce(new.payment_method, 'cash'),
       case when coalesce(new.payment_method, 'cash') = 'cash'
            then 'paid' else new.payment_status end)
    on conflict (booking_type, booking_id) do nothing;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- ---------------------------------------------------------------------------
-- 4. expire_stale_bookings() — the sweep. Only ever moves a row forward to
--    'expired' under the exact time rules above; takes no parameters, so
--    there is nothing a caller can direct at a specific booking.
-- ---------------------------------------------------------------------------
create or replace function public.expire_stale_bookings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  total integer := 0;
  hit   integer;
begin
  -- Mark this transaction as a trusted system sweep (auto-clears at commit).
  perform set_config('itulod.system_sweep', 'on', true);

  update public.transport_bookings
    set status = 'expired'
    where status = 'pending' and rider_id is null
      and created_at < now() - interval '15 minutes';
  get diagnostics hit = row_count; total := total + hit;

  update public.food_deliveries
    set status = 'expired'
    where status = 'pending' and rider_id is null
      and created_at < now() - interval '15 minutes';
  get diagnostics hit = row_count; total := total + hit;

  update public.parcel_deliveries
    set status = 'expired'
    where status = 'pending' and rider_id is null
      and created_at < now() - interval '15 minutes';
  get diagnostics hit = row_count; total := total + hit;

  update public.transport_bookings
    set status = 'expired'
    where status = 'accepted' and accepted_at is not null
      and accepted_at < now() - interval '15 minutes';
  get diagnostics hit = row_count; total := total + hit;

  update public.food_deliveries
    set status = 'expired'
    where status = 'accepted' and accepted_at is not null
      and accepted_at < now() - interval '15 minutes';
  get diagnostics hit = row_count; total := total + hit;

  update public.parcel_deliveries
    set status = 'expired'
    where status = 'accepted' and accepted_at is not null
      and accepted_at < now() - interval '15 minutes';
  get diagnostics hit = row_count; total := total + hit;

  return total;
end;
$$;

-- Any signed-in user may trigger a sweep — it only ever expires objectively
-- stale rows by server time, with no caller-supplied target, so it's safe to
-- call from any dashboard as a defensive fallback alongside pg_cron.
grant execute on function public.expire_stale_bookings() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Lifecycle notification for the customer when their booking expires.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_booking_change()
returns trigger as $$
declare
  kind text := tg_argv[0];                      -- 'ride' | 'food' | 'parcel'
begin
  if old.rider_id is null and new.rider_id is not null then
    insert into public.notifications (user_id, title, message)
    values (new.customer_id, 'Rider assigned',
            'A rider accepted your ' || kind || ' booking.');
  end if;

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
    elsif new.status = 'expired' then
      insert into public.notifications (user_id, title, message)
      values (new.customer_id, 'Booking expired',
              'Your ' || kind || ' booking expired because it was not '
              || case when old.rider_id is null then 'accepted by a rider' else 'completed' end
              || ' within the 15-minute grace period.');
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- ---------------------------------------------------------------------------
-- 6. Background sweep every minute via pg_cron — a true server-side timer,
--    independent of the app and of any single user having it open, and it
--    survives app/server restarts because it's scheduled inside the database
--    itself. If pg_cron isn't available on this project, these blocks quietly
--    no-op and the client-triggered sweep (dashboards call this function on
--    open — see RealtimeRefreshMixin) keeps things correct instead.
-- ---------------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron unavailable on this project (%), skipping schedule.', sqlerrm;
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'itulod-expire-bookings';
    perform cron.schedule('itulod-expire-bookings', '* * * * *',
      'select public.expire_stale_bookings();');
  end if;
exception when others then
  raise notice 'Could not schedule the pg_cron job (%).', sqlerrm;
end $$;
