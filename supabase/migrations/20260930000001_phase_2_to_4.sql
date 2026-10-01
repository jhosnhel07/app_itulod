-- Phase 2: Dynamic Receipts & Price Adjustments
ALTER TABLE public.food_deliveries
ADD COLUMN IF NOT EXISTS actual_food_cost NUMERIC,
ADD COLUMN IF NOT EXISTS receipt_photo_url TEXT;

-- Phase 3: Out of Stock
-- We just use the chat system and let the customer cancel or rider adjust cost.
-- But to mark items specifically, maybe a JSON update. We can just use the items JSONB column.

-- Phase 4: Round-Trips & COD for Parcels
ALTER TABLE public.parcel_deliveries
ADD COLUMN IF NOT EXISTS is_round_trip BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS cod_amount NUMERIC NOT NULL DEFAULT 0.00;
