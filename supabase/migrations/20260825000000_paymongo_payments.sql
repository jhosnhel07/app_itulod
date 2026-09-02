-- PayMongo GCash payment tracking for transport_bookings.
alter table transport_bookings
  add column if not exists payment_source_id text,
  add column if not exists payment_id text;

create index if not exists transport_bookings_payment_source_id_idx
  on transport_bookings (payment_source_id);

-- Raw audit trail of every PayMongo webhook event received.
create table if not exists payment_events (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references transport_bookings(id) on delete set null,
  event_type text not null,
  paymongo_id text,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table payment_events enable row level security;

-- Only the service role (used by the webhook edge function) may read/write this table.
create policy "service role manages payment_events"
  on payment_events
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');
