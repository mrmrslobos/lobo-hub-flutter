-- Allow any family member to update list metadata (items live in list_items).
-- Safe to re-run.

DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'lists'
  ) THEN
    DROP POLICY IF EXISTS "lists_update" ON public.lists;
    CREATE POLICY "lists_update" ON public.lists
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
  END IF;
END
$body$;
