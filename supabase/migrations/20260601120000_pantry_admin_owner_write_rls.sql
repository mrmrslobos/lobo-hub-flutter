-- Pantry writes: family owner or admin (matches meal-planning household editors).

DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'pantry_items'
  ) THEN
    DROP POLICY IF EXISTS "pantry_items_insert" ON public.pantry_items;
    DROP POLICY IF EXISTS "pantry_items_update" ON public.pantry_items;
    DROP POLICY IF EXISTS "pantry_items_delete" ON public.pantry_items;

    CREATE POLICY "pantry_items_insert" ON public.pantry_items
      FOR INSERT WITH CHECK (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_admin_or_owner(family_id)
      );

    CREATE POLICY "pantry_items_update" ON public.pantry_items
      FOR UPDATE USING (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_admin_or_owner(family_id)
      )
      WITH CHECK (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_admin_or_owner(family_id)
      );

    CREATE POLICY "pantry_items_delete" ON public.pantry_items
      FOR DELETE USING (
        public.auth_is_member_of(family_id)
        AND public.auth_is_family_admin_or_owner(family_id)
      );
  END IF;
END
$body$;
