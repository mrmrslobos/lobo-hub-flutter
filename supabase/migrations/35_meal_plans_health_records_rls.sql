-- meal_plans: optional created_by for new rows; RLS tightens inserts, legacy rows stay editable by any member until backfilled.
-- health_records: writes limited to the record subject, family owner, or family admin.

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

CREATE OR REPLACE FUNCTION public.auth_is_family_admin_or_owner(fid text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.auth_is_family_owner(fid)
  OR EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE fm.family_id = fid
      AND fm.user_id = (SELECT auth.uid())::text
      AND COALESCE(fm.role, 'MEMBER') IN ('OWNER', 'ADMIN')
  );
$$;

CREATE OR REPLACE FUNCTION public.auth_can_write_health_record(p_family_id text, p_member_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.auth_is_member_of(p_family_id)
  AND (
    p_member_id = (SELECT auth.uid())::text
    OR public.auth_is_family_admin_or_owner(p_family_id)
  );
$$;

-- ─── meal_plans ───────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'meal_plans'
  ) THEN
    ALTER TABLE public.meal_plans ADD COLUMN IF NOT EXISTS created_by text;

    DROP POLICY IF EXISTS "meal_plans_all" ON public.meal_plans;
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
      FOR UPDATE USING (
        public.auth_is_member_of(family_id)
        AND (
          created_by = (SELECT auth.uid())::text
          OR created_by IS NULL
          OR created_by = ''
          OR public.auth_is_family_owner(family_id)
        )
      )
      WITH CHECK (public.auth_is_member_of(family_id));

    CREATE POLICY "meal_plans_delete" ON public.meal_plans
      FOR DELETE USING (
        public.auth_is_member_of(family_id)
        AND (
          created_by = (SELECT auth.uid())::text
          OR created_by IS NULL
          OR created_by = ''
          OR public.auth_is_family_owner(family_id)
        )
      );
  END IF;
END
$body$;

-- ─── health_records ───────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'health_records'
  ) THEN
    DROP POLICY IF EXISTS "health_records_all" ON public.health_records;
    DROP POLICY IF EXISTS "health_records_select" ON public.health_records;
    DROP POLICY IF EXISTS "health_records_insert" ON public.health_records;
    DROP POLICY IF EXISTS "health_records_update" ON public.health_records;
    DROP POLICY IF EXISTS "health_records_delete" ON public.health_records;

    CREATE POLICY "health_records_select" ON public.health_records
      FOR SELECT USING (public.auth_is_member_of(family_id));

    CREATE POLICY "health_records_insert" ON public.health_records
      FOR INSERT WITH CHECK (
        public.auth_can_write_health_record(family_id, member_id)
      );

    CREATE POLICY "health_records_update" ON public.health_records
      FOR UPDATE USING (
        public.auth_can_write_health_record(family_id, member_id)
      )
      WITH CHECK (
        public.auth_can_write_health_record(family_id, member_id)
      );

    CREATE POLICY "health_records_delete" ON public.health_records
      FOR DELETE USING (
        public.auth_can_write_health_record(family_id, member_id)
      );
  END IF;
END
$body$;
