-- Phase 2: visibility RLS for transactions + prayer_wall (P0 follow-up).

-- ─── transactions ────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'transactions'
  ) THEN
    DROP POLICY IF EXISTS "transactions_all" ON public.transactions;
    DROP POLICY IF EXISTS "transactions_select" ON public.transactions;
    DROP POLICY IF EXISTS "transactions_insert" ON public.transactions;
    DROP POLICY IF EXISTS "transactions_update" ON public.transactions;
    DROP POLICY IF EXISTS "transactions_delete" ON public.transactions;

    CREATE POLICY "transactions_select" ON public.transactions
      FOR SELECT USING (
        public.auth_can_read_visibility_row(family_id, visibility, creator_id, NULL)
      );
    CREATE POLICY "transactions_insert" ON public.transactions
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "transactions_update" ON public.transactions
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "transactions_delete" ON public.transactions
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;

-- ─── prayer_wall ─────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'prayer_wall'
  ) THEN
    DROP POLICY IF EXISTS "prayer_wall_all" ON public.prayer_wall;
    DROP POLICY IF EXISTS "prayer_wall_select" ON public.prayer_wall;
    DROP POLICY IF EXISTS "prayer_wall_insert" ON public.prayer_wall;
    DROP POLICY IF EXISTS "prayer_wall_update" ON public.prayer_wall;
    DROP POLICY IF EXISTS "prayer_wall_delete" ON public.prayer_wall;

    CREATE POLICY "prayer_wall_select" ON public.prayer_wall
      FOR SELECT USING (
        public.auth_can_read_visibility_row(family_id, visibility, creator_id, NULL)
      );
    CREATE POLICY "prayer_wall_insert" ON public.prayer_wall
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "prayer_wall_update" ON public.prayer_wall
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "prayer_wall_delete" ON public.prayer_wall
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;
