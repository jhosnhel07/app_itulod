CREATE OR REPLACE FUNCTION public.check_email_exists(lookup_email text)
RETURNS boolean AS $$$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM auth.users WHERE email = lookup_email
  );
END;
$$$ LANGUAGE plpgsql SECURITY DEFINER;