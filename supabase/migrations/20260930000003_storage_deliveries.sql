INSERT INTO storage.buckets (id, name, public) VALUES ('deliveries', 'deliveries', true);

CREATE POLICY "Anyone can view deliveries" ON storage.objects FOR SELECT USING (bucket_id = 'deliveries');
CREATE POLICY "Authenticated users can upload deliveries" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'deliveries');
