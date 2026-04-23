-- meal_plans: backfill legacy created_by from family owner; any member may
-- update/delete (shared meal board). Inserts still require created_by = auth.uid().
-- NOT NULL only when every row has a non-empty created_by (after backfill).

DO $body$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'meal_plans'
  ) THEN
    RETURN;
  END IF;

  ALTER TABLE public.meal_plans ADD COLUMN IF NOT EXISTS created_by text;

  UPDATE public.meal_plans mp
  SET created_by = f.owner_id
  FROM public.families f
  WHERE mp.family_id = f.id
    AND (mp.created_by IS NULL OR mp.created_by = '');

  IF EXISTS (
    SELECT 1 FROM public.meal_plans mp
    WHERE NOT EXISTS (SELECT 1 FROM public.families fam WHERE fam.id = mp.family_id)
  ) THEN
    RAISE NOTICE
      'meal_plans: rows reference missing families; skipping NOT NULL on created_by.';
  ELSIF EXISTS (
    SELECT 1 FROM public.meal_plans WHERE created_by IS NULL OR created_by = ''
  ) THEN
    RAISE NOTICE
      'meal_plans: some rows still have empty created_by; skipping NOT NULL.';
  ELSE
    ALTER TABLE public.meal_plans ALTER COLUMN created_by SET NOT NULL;
  END IF;

  DROP POLICY IF EXISTS "meal_plans_select" ON public.meal_plans;
  DROP POLICY IF EXISTS "meal_plans_insert" ON public.meal_plans;
  DROP POLICY IF EXISTS "meal_plans_update" ON public.meal_plans;
  DROP POLICY IF EXISTS "meal_plans_delete" ON public.meal_plans;

  CREATE POLICY "meal_plans_select" ON public.meal_plans
    FOR SELECT USING (public.auth_is_member_of(family_id));

  CREATE POLICY "meal_plans_insert" ON public.meal_plans
    FOR INSERT WITH CHECK (
      public.auth_is_member_of(family_id)
      AND created_by = (SELECT auth.uid())::text
      AND created_by IS NOT NULL
      AND created_by <> ''
    );

  CREATE POLICY "meal_plans_update" ON public.meal_plans
    FOR UPDATE USING (public.auth_is_member_of(family_id))
    WITH CHECK (public.auth_is_member_of(family_id));

  CREATE POLICY "meal_plans_delete" ON public.meal_plans
    FOR DELETE USING (public.auth_is_member_of(family_id));
END
$body$ LANGUAGE plpgsql;
