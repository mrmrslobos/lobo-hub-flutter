-- Tighter RLS for lists (creator + owner) and pantry_items (owner writes).
-- Depends on public.auth_is_member_of (migration 02) and public.auth_is_family_owner (migration 32).

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

-- ─── lists ───────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'lists'
  ) THEN
    DROP POLICY IF EXISTS "lists_all" ON public.lists;
    DROP POLICY IF EXISTS "lists_select" ON public.lists;
    DROP POLICY IF EXISTS "lists_insert" ON public.lists;
    DROP POLICY IF EXISTS "lists_update" ON public.lists;
    DROP POLICY IF EXISTS "lists_delete" ON public.lists;

    CREATE POLICY "lists_select" ON public.lists
      FOR SELECT USING (public.auth_is_member_of(family_id));

    CREATE POLICY "lists_insert" ON public.lists
      FOR INSERT WITH CHECK (
        public.auth_is_member_of(family_id)
        AND creator_id = (SELECT auth.uid())::text
      );

    CREATE POLICY "lists_update" ON public.lists
      FOR UPDATE USING (
        public.auth_is_member_of(family_id)
        AND (
          creator_id = (SELECT auth.uid())::text
          OR (creator_id IS NULL AND public.auth_is_family_owner(family_id))
          OR (creator_id = '' AND public.auth_is_family_owner(family_id))
        )
      )
      WITH CHECK (
        public.auth_is_member_of(family_id)
        AND (
          creator_id = (SELECT auth.uid())::text
          OR (creator_id IS NULL AND public.auth_is_family_owner(family_id))
          OR (creator_id = '' AND public.auth_is_family_owner(family_id))
        )
      );

    CREATE POLICY "lists_delete" ON public.lists
      FOR DELETE USING (
        public.auth_is_member_of(family_id)
        AND (
          creator_id = (SELECT auth.uid())::text
          OR (creator_id IS NULL AND public.auth_is_family_owner(family_id))
          OR (creator_id = '' AND public.auth_is_family_owner(family_id))
        )
      );
  END IF;
END
$body$;

-- ─── pantry_items ─────────────────────────────────────────────────────────
DO $body$
DECLARE
  pol record;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'pantry_items'
  ) THEN
    FOR pol IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'pantry_items'
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.pantry_items', pol.policyname);
    END LOOP;

    CREATE POLICY "pantry_items_select" ON public.pantry_items
      FOR SELECT USING (public.auth_is_member_of(family_id));

    CREATE POLICY "pantry_items_insert" ON public.pantry_items
      FOR INSERT WITH CHECK (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_owner(family_id)
      );

    CREATE POLICY "pantry_items_update" ON public.pantry_items
      FOR UPDATE USING (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_owner(family_id)
      )
      WITH CHECK (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_owner(family_id)
      );

    CREATE POLICY "pantry_items_delete" ON public.pantry_items
      FOR DELETE USING (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_owner(family_id)
      );
  END IF;
END
$body$;
