-- Lock down SECURITY DEFINER functions to authenticated users only.
--
-- The Supabase advisor flags these (advisor `0028`) because anon can RPC
-- them. None of them are part of an anonymous-user flow:
--   * auth_is_member_of: read-only helper used by RLS policies; the RLS
--     evaluator runs as the calling role, so authenticated callers can
--     still use it transitively even after we revoke from anon.
--   * claim_owned_families: relinks rows to the current auth UUID — runs
--     post-sign-in.
--   * delete_family_cloud_data: destructive; must require a session.
--   * find_family_by_join_code: join-family flow happens after sign-in.
--   * sync_family_subscription_tier: subscription update, server- or
--     authenticated-only.
--
-- We revoke from PUBLIC and anon; authenticated keeps EXECUTE. Wrapping
-- each in a guarded DO block so a missing function doesn't fail the rest.

DO $m$
DECLARE
  fns text[] := ARRAY[
    'public.auth_is_member_of(text)',
    'public.claim_owned_families()',
    'public.delete_family_cloud_data(text)',
    'public.find_family_by_join_code(text)',
    'public.sync_family_subscription_tier(text, text)'
  ];
  f text;
BEGIN
  FOREACH f IN ARRAY fns
  LOOP
    BEGIN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', f);
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', f);
      EXECUTE format('GRANT  EXECUTE ON FUNCTION %s TO authenticated', f);
    EXCEPTION WHEN undefined_function THEN
      -- Different env / not deployed yet — skip.
      NULL;
    END;
  END LOOP;
END
$m$;
