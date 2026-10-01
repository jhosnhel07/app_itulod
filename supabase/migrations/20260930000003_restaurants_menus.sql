CREATE TABLE public.restaurants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  address text NOT NULL,
  image_url text,
  rating numeric(3,2) DEFAULT 0,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view restaurants" ON public.restaurants FOR SELECT USING (true);

CREATE TABLE public.menu_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  price numeric(10,2) NOT NULL,
  image_url text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view menu items" ON public.menu_items FOR SELECT USING (true);

ALTER TABLE public.food_deliveries ADD COLUMN restaurant_id uuid REFERENCES public.restaurants(id);
ALTER TABLE public.food_deliveries ADD COLUMN items jsonb;
ALTER TABLE public.food_deliveries ADD COLUMN total_items_price numeric(10,2) DEFAULT 0;
