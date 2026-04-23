-- Track recipe author for RLS; legacy rows may have NULL/empty created_by (owner-only edits).

ALTER TABLE public.recipes ADD COLUMN IF NOT EXISTS created_by text;

CREATE OR REPLACE FUNCTION public.auth_is_family_owner(fid text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.families f
    WHERE f.id = fid AND f.owner_id = (SELECT auth.uid())::text
  );
$$;

DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'recipes'
  ) THEN
    DROP POLICY IF EXISTS "recipes_all" ON public.recipes;
    DROP POLICY IF EXISTS "recipes_select" ON public.recipes;
    DROP POLICY IF EXISTS "recipes_insert" ON public.recipes;
    DROP POLICY IF EXISTS "recipes_update" ON public.recipes;
    DROP POLICY IF EXISTS "recipes_delete" ON public.recipes;

    CREATE POLICY "recipes_select" ON public.recipes
      FOR SELECT USING (public.auth_is_member_of(family_id));

    CREATE POLICY "recipes_insert" ON public.recipes
      FOR INSERT WITH CHECK (
        public.auth_is_member_of(family_id)
        AND created_by = (SELECT auth.uid())::text
        AND created_by IS NOT NULL
        AND created_by <> ''
      );

    CREATE POLICY "recipes_update" ON public.recipes
      FOR UPDATE USING (
        public.auth_is_member_of(family_id)
        AND (
          created_by = (SELECT auth.uid())::text
          OR (created_by IS NULL AND public.auth_is_family_owner(family_id))
          OR (created_by = '' AND public.auth_is_family_owner(family_id))
        )
      )
      WITH CHECK (
        public.auth_is_member_of(family_id)
        AND (
          created_by = (SELECT auth.uid())::text
          OR (created_by IS NULL AND public.auth_is_family_owner(family_id))
          OR (created_by = '' AND public.auth_is_family_owner(family_id))
        )
      );

    CREATE POLICY "recipes_delete" ON public.recipes
      FOR DELETE USING (
        public.auth_is_member_of(family_id)
        AND (
          created_by = (SELECT auth.uid())::text
          OR (created_by IS NULL AND public.auth_is_family_owner(family_id))
          OR (created_by = '' AND public.auth_is_family_owner(family_id))
        )
      );
  END IF;
END
$body$;
