CREATE TABLE public.online_riders (
  rider_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.online_riders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view online riders" ON public.online_riders FOR SELECT USING (true);
CREATE POLICY "Riders can update their own status" ON public.online_riders FOR INSERT WITH CHECK (auth.uid() = rider_id);
CREATE POLICY "Riders can update their own status (update)" ON public.online_riders FOR UPDATE USING (auth.uid() = rider_id);
CREATE POLICY "Riders can go offline" ON public.online_riders FOR DELETE USING (auth.uid() = rider_id);

-- Expose via realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.online_riders;
