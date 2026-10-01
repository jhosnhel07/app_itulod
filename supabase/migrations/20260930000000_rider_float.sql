-- Migration: Rider Float (Capital on hand)
-- Allows the app to track how much cash a rider has, ensuring they aren't
-- matched with food or parcel concierge orders they can't afford upfront.

-- Add float_amount to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS float_amount NUMERIC NOT NULL DEFAULT 0.00;

-- Allow riders to update their own float_amount
DROP POLICY IF EXISTS "Users can update own float amount" ON public.profiles;
CREATE POLICY "Users can update own float amount"
ON public.profiles
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- (Optional but good) Trigger to ensure float_amount is not negative
CREATE OR REPLACE FUNCTION public.check_float_amount()
RETURNS trigger AS $$
BEGIN
    IF NEW.float_amount < 0 THEN
        NEW.float_amount = 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ensure_positive_float ON public.profiles;
CREATE TRIGGER ensure_positive_float
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.check_float_amount();
