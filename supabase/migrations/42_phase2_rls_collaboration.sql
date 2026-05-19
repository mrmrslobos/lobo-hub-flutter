-- Phase 2: family-readable fitness plans; family-editable recipes (cookbook).

-- ─── fitness_plans: family can read plans scoped to family_id; writes stay per-user ───
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'fitness_plans'
  ) THEN
    DROP POLICY IF EXISTS "fitness_plans_all" ON public.fitness_plans;

    CREATE POLICY "fitness_plans_select_own" ON public.fitness_plans
      FOR SELECT USING (user_id = (SELECT auth.uid())::text);

    CREATE POLICY "fitness_plans_select_family" ON public.fitness_plans
      FOR SELECT USING (
        family_id IS NOT NULL
        AND family_id <> ''
        AND public.auth_is_member_of(family_id)
      );

    CREATE POLICY "fitness_plans_insert_own" ON public.fitness_plans
      FOR INSERT WITH CHECK (user_id = (SELECT auth.uid())::text);

    CREATE POLICY "fitness_plans_update_own" ON public.fitness_plans
      FOR UPDATE
      USING (user_id = (SELECT auth.uid())::text)
      WITH CHECK (user_id = (SELECT auth.uid())::text);

    CREATE POLICY "fitness_plans_delete_own" ON public.fitness_plans
      FOR DELETE USING (user_id = (SELECT auth.uid())::text);
  END IF;
END
$body$;

-- ─── recipes: any family member may edit/delete (matches shared meal hub) ───
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'recipes'
  ) THEN
    DROP POLICY IF EXISTS "recipes_update" ON public.recipes;
    DROP POLICY IF EXISTS "recipes_delete" ON public.recipes;

    CREATE POLICY "recipes_update" ON public.recipes
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));

    CREATE POLICY "recipes_delete" ON public.recipes
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;
