-- Isolated test database ONLY. This models Supabase JWT helpers, not its Auth service.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.role',true),'');
$$;
GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION auth.uid(),auth.role() TO anon,authenticated,service_role;
