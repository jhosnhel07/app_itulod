-- Phase 3: Out-of-Stock / Item Replacement Flow
ALTER TABLE food_order_items ADD COLUMN is_out_of_stock BOOLEAN DEFAULT FALSE;
