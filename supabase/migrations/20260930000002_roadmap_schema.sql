
-- #3 Tipping & #4 Cancellation fee
ALTER TABLE public.transport_bookings ADD COLUMN tip_amount numeric(10,2) DEFAULT 0;
ALTER TABLE public.food_deliveries ADD COLUMN tip_amount numeric(10,2) DEFAULT 0;
ALTER TABLE public.parcel_deliveries ADD COLUMN tip_amount numeric(10,2) DEFAULT 0;

ALTER TABLE public.transport_bookings ADD COLUMN cancellation_fee numeric(10,2) DEFAULT 0;
ALTER TABLE public.food_deliveries ADD COLUMN cancellation_fee numeric(10,2) DEFAULT 0;
ALTER TABLE public.parcel_deliveries ADD COLUMN cancellation_fee numeric(10,2) DEFAULT 0;

-- #6 Scheduled bookings
ALTER TABLE public.transport_bookings ADD COLUMN scheduled_for timestamp with time zone;
ALTER TABLE public.food_deliveries ADD COLUMN scheduled_for timestamp with time zone;
ALTER TABLE public.parcel_deliveries ADD COLUMN scheduled_for timestamp with time zone;

-- #7 In-app wallet
CREATE TABLE public.wallets (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  balance numeric(10,2) DEFAULT 0 NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own wallet" ON public.wallets FOR SELECT USING (auth.uid() = user_id);

CREATE TABLE public.wallet_transactions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES public.wallets(user_id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL,
  type text NOT NULL, -- 'topup', 'payment', 'refund'
  reference_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own transactions" ON public.wallet_transactions FOR SELECT USING (auth.uid() = user_id);

-- #8 Proof of delivery
ALTER TABLE public.food_deliveries ADD COLUMN dropoff_photo_url text;
ALTER TABLE public.parcel_deliveries ADD COLUMN dropoff_photo_url text;

-- #9 In-app chat
CREATE TABLE public.booking_messages (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id uuid NOT NULL,
  booking_type text NOT NULL, -- 'transport', 'food', 'parcel'
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.booking_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view messages they sent or received" 
  ON public.booking_messages FOR SELECT
  USING (
    sender_id = auth.uid() OR 
    EXISTS (
      SELECT 1 FROM public.transport_bookings tb WHERE tb.id = booking_id AND (tb.customer_id = auth.uid() OR tb.rider_id = auth.uid())
    ) OR
    EXISTS (
      SELECT 1 FROM public.food_deliveries fd WHERE fd.id = booking_id AND (fd.customer_id = auth.uid() OR fd.rider_id = auth.uid())
    ) OR
    EXISTS (
      SELECT 1 FROM public.parcel_deliveries pd WHERE pd.id = booking_id AND (pd.customer_id = auth.uid() OR pd.rider_id = auth.uid())
    )
  );
CREATE POLICY "Users can send messages" ON public.booking_messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- #10 Promo/discount codes
CREATE TABLE public.promo_codes (
  code text PRIMARY KEY,
  discount_amount numeric(10,2),
  discount_percent numeric(5,2),
  max_discount numeric(10,2),
  expires_at timestamp with time zone,
  is_active boolean DEFAULT true
);
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view active promos" ON public.promo_codes FOR SELECT USING (is_active = true);

ALTER TABLE public.transport_bookings ADD COLUMN promo_code text REFERENCES public.promo_codes(code);
ALTER TABLE public.food_deliveries ADD COLUMN promo_code text REFERENCES public.promo_codes(code);
ALTER TABLE public.parcel_deliveries ADD COLUMN promo_code text REFERENCES public.promo_codes(code);

-- #12 Loyalty points
ALTER TABLE public.profiles ADD COLUMN loyalty_points integer DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN referral_code text UNIQUE;

-- #11 Self-service refund/dispute request
CREATE TABLE public.disputes (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id uuid NOT NULL,
  booking_type text NOT NULL,
  customer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text NOT NULL,
  status text DEFAULT 'pending', -- 'pending', 'resolved', 'rejected'
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own disputes" ON public.disputes FOR SELECT USING (auth.uid() = customer_id);
CREATE POLICY "Users can create disputes" ON public.disputes FOR INSERT WITH CHECK (auth.uid() = customer_id);
