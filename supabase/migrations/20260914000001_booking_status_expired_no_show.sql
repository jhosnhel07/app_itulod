-- =============================================================================
-- iTULOD mobile — migration 009a: add 'expired' and 'no_show' booking statuses
--
-- Kept in its own migration and does nothing else: Postgres will not let a
-- freshly-added enum value be *used* (in an UPDATE/CHECK/etc.) inside the same
-- transaction it was added in, and each migration file runs as one
-- transaction. Migration 009b (next) does the actual expiration logic and
-- runs afterwards, in its own transaction, once these values are committed.
-- =============================================================================

alter type public.booking_status add value if not exists 'expired';
alter type public.booking_status add value if not exists 'no_show';
