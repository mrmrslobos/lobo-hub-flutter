-- Lists: allow any family member to edit shared lists (matches app UI).
-- Adds shared_with for SPECIFIC visibility sync; keeps delete restricted to creator/owner.

ALTER TABLE public.lists
  ADD COLUMN IF NOT EXISTS shared_with jsonb NOT NULL DEFAULT '[]'::jsonb;

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
