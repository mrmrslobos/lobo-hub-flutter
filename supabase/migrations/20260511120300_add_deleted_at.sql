-- Soft-delete for family-scoped tables to prevent offline-resurrection.
--
-- Scenario this fixes: A deletes row R while B is offline holding a stale R.
-- Under hard-delete, B's reconnect upserts R back to life. With deleted_at:
--   A's "delete" sets deleted_at = now() (no DELETE statement)
--   B pulls → fetch filter `deleted_at IS NULL` hides R, B drops R locally
--   B's upsert payload does NOT include deleted_at, so server's value persists
--
-- Idempotent: ADD COLUMN IF NOT EXISTS + dynamic CREATE INDEX guards.

DO $m$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tasks','events','lists','recipes','meal_plans','chores','polls',
    'prayer_wall','devotionals','reading_plans','special_dates',
    'family_photos','saved_places','reward_items','savings_goals',
    'daily_habits','budget_categories','transactions','budget_entries',
    'milestones','external_calendars','health_records',
    'period_cycles','period_symptoms','rewards'
  ]
  LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = t
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS deleted_at timestamptz',
        t
      );
    END IF;
  END LOOP;
END
$m$;

-- Partial indexes on family_id for the alive subset on hot tables. CONCURRENTLY
-- so the migration doesn't lock writes on production.
-- (Wrapped one-by-one so a single failure doesn't stop the rest.)

CREATE INDEX CONCURRENTLY IF NOT EXISTS tasks_family_alive_idx
  ON public.tasks (family_id) WHERE deleted_at IS NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS events_family_alive_idx
  ON public.events (family_id) WHERE deleted_at IS NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS lists_family_alive_idx
  ON public.lists (family_id) WHERE deleted_at IS NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS recipes_family_alive_idx
  ON public.recipes (family_id) WHERE deleted_at IS NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS meal_plans_family_alive_idx
  ON public.meal_plans (family_id) WHERE deleted_at IS NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS chores_family_alive_idx
  ON public.chores (family_id) WHERE deleted_at IS NULL;
