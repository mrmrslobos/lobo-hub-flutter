-- Pantry: any family member can manage items (matches Meals hub family pantry UI).
-- Replaces owner-only write policies from migration 33.

DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'pantry_items'
  ) THEN
    DROP POLICY IF EXISTS "pantry_items_select" ON public.pantry_items;
    DROP POLICY IF EXISTS "pantry_items_insert" ON public.pantry_items;
    DROP POLICY IF EXISTS "pantry_items_update" ON public.pantry_items;
    DROP POLICY IF EXISTS "pantry_items_delete" ON public.pantry_items;

    CREATE POLICY "pantry_items_select" ON public.pantry_items
      FOR SELECT USING (public.auth_is_member_of(family_id));

    CREATE POLICY "pantry_items_insert" ON public.pantry_items
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));

    CREATE POLICY "pantry_items_update" ON public.pantry_items
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));

    CREATE POLICY "pantry_items_delete" ON public.pantry_items
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;
