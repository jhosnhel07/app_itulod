-- =============================================================================
-- iTULOD mobile — ensure the PayMongo payment columns exist before migration
-- 005's booking-update trigger (which references `paymongo_reference`).
--
-- These columns are normally created by the web project's migration `002`.
-- This mirror keeps the mobile migration chain self-contained and idempotent
-- so `supabase db push` works from either repo against the shared project.
-- =============================================================================

alter table public.transport_bookings
  add column if not exists payment_method payment_method not null default 'cash',
  add column if not exists payment_status payment_status not null default 'pending',
  add column if not exists paymongo_reference text;

alter table public.food_deliveries
  add column if not exists payment_method payment_method not null default 'cash',
  add column if not exists payment_status payment_status not null default 'pending',
  add column if not exists paymongo_reference text;

alter table public.parcel_deliveries
  add column if not exists payment_method payment_method not null default 'cash',
  add column if not exists payment_status payment_status not null default 'pending',
  add column if not exists paymongo_reference text;

create index if not exists idx_transport_paymongo_ref
  on public.transport_bookings (paymongo_reference);
create index if not exists idx_food_paymongo_ref
  on public.food_deliveries (paymongo_reference);
create index if not exists idx_parcel_paymongo_ref
  on public.parcel_deliveries (paymongo_reference);
