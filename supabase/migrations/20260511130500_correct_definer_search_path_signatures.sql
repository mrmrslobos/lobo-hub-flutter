-- Correct search_path pinning for the actual function signatures deployed in this
-- repo. Migration 20260511120200 used wrong overload spellings on some setups
-- (`auth_is_member_of(uuid)`, `delete_family_cloud_data(uuid)`,
-- `sync_family_subscription_tier()`), so the ALTER never matched the real definitions.
--
-- Safe to apply when the originals already succeeded (idempotent ALTER ... SET).

DO $m$
BEGIN
  BEGIN
    ALTER FUNCTION public.auth_is_member_of(text)
      SET search_path = pg_catalog, public;
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  BEGIN
    ALTER FUNCTION public.delete_family_cloud_data(text)
      SET search_path = pg_catalog, public;
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  BEGIN
    ALTER FUNCTION public.sync_family_subscription_tier(text, text)
      SET search_path = pg_catalog, public;
  EXCEPTION WHEN undefined_function THEN NULL;
  END;
END
$m$;
