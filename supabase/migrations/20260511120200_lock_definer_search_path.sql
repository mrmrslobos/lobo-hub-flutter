-- SECURITY DEFINER functions with a mutable search_path can be hijacked by a
-- caller setting search_path to point at a shadow schema before invocation.
-- Pin search_path to empty so every reference inside the function body must
-- be fully qualified (and resolve against the actual schemas).
--
-- Idempotent: ALTER FUNCTION ... SET search_path is safe to re-run.
-- Wrapped in DO blocks so missing functions don't fail the whole migration
-- (different envs may have applied different earlier migrations).

DO $m$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'auth_is_member_of'
  ) THEN
    EXECUTE 'ALTER FUNCTION public.auth_is_member_of(text) SET search_path = pg_catalog, public';
  END IF;
END
$m$;

DO $m$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'claim_owned_families'
  ) THEN
    EXECUTE 'ALTER FUNCTION public.claim_owned_families() SET search_path = pg_catalog, public';
  END IF;
END
$m$;

DO $m$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'delete_family_cloud_data'
  ) THEN
    EXECUTE 'ALTER FUNCTION public.delete_family_cloud_data(text) SET search_path = pg_catalog, public';
  END IF;
END
$m$;

DO $m$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'find_family_by_join_code'
  ) THEN
    EXECUTE 'ALTER FUNCTION public.find_family_by_join_code(text) SET search_path = pg_catalog, public';
  END IF;
END
$m$;

DO $m$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'sync_family_subscription_tier'
  ) THEN
    EXECUTE 'ALTER FUNCTION public.sync_family_subscription_tier(text, text) SET search_path = pg_catalog, public';
  END IF;
END
$m$;
