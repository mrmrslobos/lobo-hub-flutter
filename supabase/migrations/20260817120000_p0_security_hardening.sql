-- P0 security hardening: subscription tier guard, visibility RLS, private photos,
-- device_tokens family membership check.

-- ─── Visibility helper ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_uid_text()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (SELECT auth.uid())::text;
$$;

CREATE OR REPLACE FUNCTION public.auth_jsonb_contains_user_id(shared_with jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    shared_with @> jsonb_build_array(public.auth_uid_text()),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.auth_can_read_visibility_row(
  fid text,
  vis text,
  creator text,
  shared_with jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    public.auth_is_member_of(fid)
    AND (
      COALESCE(vis, 'FAMILY') = 'FAMILY'
      OR (
        vis = 'PRIVATE'
        AND creator = public.auth_uid_text()
      )
      OR (
        vis = 'SPECIFIC'
        AND (
          creator = public.auth_uid_text()
          OR public.auth_jsonb_contains_user_id(COALESCE(shared_with, '[]'::jsonb))
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.auth_can_read_task_row(
  fid text,
  vis text,
  creator text,
  assignees jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    public.auth_is_member_of(fid)
    AND (
      COALESCE(vis, 'FAMILY') = 'FAMILY'
      OR (
        vis = 'PRIVATE'
        AND creator = public.auth_uid_text()
      )
      OR (
        vis = 'SPECIFIC'
        AND (
          creator = public.auth_uid_text()
          OR public.auth_jsonb_contains_user_id(COALESCE(assignees, '[]'::jsonb))
        )
      )
    );
$$;

-- ─── Subscription tier: RPC allowlist + direct-update guard ───────────────────
CREATE OR REPLACE FUNCTION public.families_protect_subscription_tier()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier THEN
    IF current_setting('huddle.subscription_tier_sync', true) IS DISTINCT FROM '1' THEN
      RAISE EXCEPTION 'subscription_tier can only be updated via sync_family_subscription_tier';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS families_subscription_tier_guard ON public.families;
CREATE TRIGGER families_subscription_tier_guard
  BEFORE UPDATE ON public.families
  FOR EACH ROW
  EXECUTE FUNCTION public.families_protect_subscription_tier();

CREATE OR REPLACE FUNCTION public.sync_family_subscription_tier(p_family_id text, p_tier text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_family_id IS NULL OR p_family_id = '' THEN
    RAISE EXCEPTION 'invalid family id';
  END IF;
  IF p_tier IS NULL OR p_tier = '' THEN
    RAISE EXCEPTION 'invalid tier';
  END IF;
  IF p_tier NOT IN ('trial', 'base', 'ai', 'ai_family') THEN
    RAISE EXCEPTION 'invalid tier value';
  END IF;
  IF NOT public.auth_is_member_of(p_family_id) THEN
    RAISE EXCEPTION 'not a member of this family';
  END IF;

  PERFORM set_config('huddle.subscription_tier_sync', '1', true);
  UPDATE public.families
  SET subscription_tier = p_tier
  WHERE id = p_family_id;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_family_subscription_tier(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_family_subscription_tier(text, text) TO authenticated;

-- ─── lists ───────────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'lists'
  ) THEN
    DROP POLICY IF EXISTS "lists_select" ON public.lists;
    CREATE POLICY "lists_select" ON public.lists
      FOR SELECT USING (
        public.auth_can_read_visibility_row(
          family_id, visibility, creator_id, shared_with
        )
      );
  END IF;
END
$body$;

-- ─── list_items (inherit parent list visibility) ─────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'list_items'
  ) THEN
    DROP POLICY IF EXISTS "list_items_select" ON public.list_items;
    CREATE POLICY "list_items_select" ON public.list_items
      FOR SELECT USING (
        EXISTS (
          SELECT 1
          FROM public.lists l
          WHERE l.id = list_items.list_id
            AND public.auth_can_read_visibility_row(
              l.family_id, l.visibility, l.creator_id, l.shared_with
            )
        )
      );
  END IF;
END
$body$;

-- ─── tasks ───────────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'tasks'
  ) THEN
    DROP POLICY IF EXISTS "tasks_all" ON public.tasks;
    DROP POLICY IF EXISTS "tasks_select" ON public.tasks;
    DROP POLICY IF EXISTS "tasks_insert" ON public.tasks;
    DROP POLICY IF EXISTS "tasks_update" ON public.tasks;
    DROP POLICY IF EXISTS "tasks_delete" ON public.tasks;

    CREATE POLICY "tasks_select" ON public.tasks
      FOR SELECT USING (
        public.auth_can_read_task_row(family_id, visibility, creator_id, assignees)
      );
    CREATE POLICY "tasks_insert" ON public.tasks
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "tasks_update" ON public.tasks
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "tasks_delete" ON public.tasks
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;

-- ─── events ──────────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'events'
  ) THEN
    DROP POLICY IF EXISTS "events_all" ON public.events;
    DROP POLICY IF EXISTS "events_select" ON public.events;
    DROP POLICY IF EXISTS "events_insert" ON public.events;
    DROP POLICY IF EXISTS "events_update" ON public.events;
    DROP POLICY IF EXISTS "events_delete" ON public.events;

    CREATE POLICY "events_select" ON public.events
      FOR SELECT USING (
        public.auth_can_read_visibility_row(
          family_id, visibility, creator_id, shared_with
        )
      );
    CREATE POLICY "events_insert" ON public.events
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "events_update" ON public.events
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "events_delete" ON public.events
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;

-- ─── devotionals ─────────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'devotionals'
  ) THEN
    DROP POLICY IF EXISTS "devotionals_all" ON public.devotionals;
    DROP POLICY IF EXISTS "devotionals_select" ON public.devotionals;
    DROP POLICY IF EXISTS "devotionals_insert" ON public.devotionals;
    DROP POLICY IF EXISTS "devotionals_update" ON public.devotionals;
    DROP POLICY IF EXISTS "devotionals_delete" ON public.devotionals;

    CREATE POLICY "devotionals_select" ON public.devotionals
      FOR SELECT USING (
        public.auth_can_read_visibility_row(family_id, visibility, creator_id, NULL)
      );
    CREATE POLICY "devotionals_insert" ON public.devotionals
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "devotionals_update" ON public.devotionals
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "devotionals_delete" ON public.devotionals
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;

-- ─── family_photos ───────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'family_photos'
  ) THEN
    DROP POLICY IF EXISTS "family_photos_select" ON public.family_photos;
    CREATE POLICY "family_photos_select" ON public.family_photos
      FOR SELECT USING (
        public.auth_can_read_visibility_row(family_id, visibility, uploader_id, NULL)
      );
  END IF;
END
$body$;

-- ─── budget_entries ──────────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'budget_entries'
  ) THEN
    DROP POLICY IF EXISTS "budget_entries_family" ON public.budget_entries;
    DROP POLICY IF EXISTS "budget_entries_all" ON public.budget_entries;
    DROP POLICY IF EXISTS "budget_entries_select" ON public.budget_entries;

    CREATE POLICY "budget_entries_select" ON public.budget_entries
      FOR SELECT USING (
        public.auth_can_read_visibility_row(family_id, visibility, creator_id, NULL)
      );
    CREATE POLICY "budget_entries_insert" ON public.budget_entries
      FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "budget_entries_update" ON public.budget_entries
      FOR UPDATE
      USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));
    CREATE POLICY "budget_entries_delete" ON public.budget_entries
      FOR DELETE USING (public.auth_is_member_of(family_id));
  END IF;
END
$body$;

-- ─── budget_categories ───────────────────────────────────────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'budget_categories'
  ) THEN
    DROP POLICY IF EXISTS "budget_categories_all" ON public.budget_categories;
    DROP POLICY IF EXISTS "budget_categories_select" ON public.budget_categories;

    CREATE POLICY "budget_categories_select" ON public.budget_categories
      FOR SELECT USING (
        public.auth_can_read_visibility_row(family_id, visibility, creator_id, NULL)
      );
  END IF;
END
$body$;

-- ─── device_tokens: require family membership on write ───────────────────────
DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'device_tokens'
  ) THEN
    DROP POLICY IF EXISTS "Users manage own tokens" ON public.device_tokens;
    CREATE POLICY "Users manage own tokens" ON public.device_tokens
      FOR ALL
      USING (public.auth_uid_text() = user_id)
      WITH CHECK (
        public.auth_uid_text() = user_id
        AND public.auth_is_member_of(family_id)
      );
  END IF;
END
$body$;

-- ─── family-photos bucket: private (signed URLs required) ────────────────────
UPDATE storage.buckets
SET public = false
WHERE id = 'family-photos';
