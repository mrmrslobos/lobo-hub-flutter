-- Allow any authenticated family member to update only subscription_tier (for RevenueCat sync).
-- Owners already have full families UPDATE; this RPC is for non-owners after purchase.

CREATE OR REPLACE FUNCTION public.sync_family_subscription_tier(p_family_id text, p_tier text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_family_id IS NULL OR p_family_id = '' THEN
    RAISE EXCEPTION 'invalid family id';
  END IF;
  IF p_tier IS NULL OR p_tier = '' THEN
    RAISE EXCEPTION 'invalid tier';
  END IF;
  IF NOT auth_is_member_of(p_family_id) THEN
    RAISE EXCEPTION 'not a member of this family';
  END IF;

  UPDATE families
  SET subscription_tier = p_tier
  WHERE id = p_family_id;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_family_subscription_tier(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_family_subscription_tier(text, text) TO authenticated;
