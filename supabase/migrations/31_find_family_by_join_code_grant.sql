-- Join-by-code RPC must be callable by anon + authenticated JWTs.
-- Without GRANT EXECUTE, PostgREST returns permission denied; the app then
-- incorrectly showed "No family found with that code."
-- Also: case-insensitive + trimmed match; SET search_path for SECURITY DEFINER.

CREATE OR REPLACE FUNCTION public.find_family_by_join_code(code text)
RETURNS SETOF public.families
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT *
  FROM public.families
  WHERE upper(trim(both from join_code)) = upper(trim(both from code))
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.find_family_by_join_code(text) TO anon;
GRANT EXECUTE ON FUNCTION public.find_family_by_join_code(text) TO authenticated;

-- Often missing from older DBs; safe to repeat.
GRANT EXECUTE ON FUNCTION public.claim_owned_families() TO authenticated;
