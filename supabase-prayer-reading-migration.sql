-- =============================================================================
-- Migration: Add Prayer Wall & Bible Reading Plans tables
-- =============================================================================
-- Run this in Supabase SQL Editor if you already have an existing deployment.
-- Safe to re-run (uses IF NOT EXISTS).
--
-- If you're doing a FRESH setup, use supabase/fresh-setup.sql instead —
-- these tables are already included there.
-- =============================================================================

-- 1. Create tables
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS prayer_wall (
  id                  text PRIMARY KEY,
  "familyId"          text NOT NULL,
  "creatorId"         text NOT NULL,
  type                text NOT NULL,        -- GRATITUDE | REQUEST | ANSWERED
  text                text NOT NULL,
  "originalRequestId" text,                 -- links ANSWERED → original REQUEST
  reactions           jsonb NOT NULL DEFAULT '[]'::jsonb,
  date                text NOT NULL,
  "answeredAt"        text,
  visibility          text NOT NULL DEFAULT 'FAMILY'
);

CREATE TABLE IF NOT EXISTS reading_plans (
  id          text PRIMARY KEY,
  "familyId"  text NOT NULL,
  "creatorId" text NOT NULL,
  title       text NOT NULL,
  description text NOT NULL,
  "totalDays" integer NOT NULL,
  days        jsonb NOT NULL DEFAULT '[]'::jsonb,
  "createdAt" text NOT NULL
);

CREATE TABLE IF NOT EXISTS reading_plan_progress (
  id                text PRIMARY KEY,
  "planId"          text NOT NULL,
  "userId"          text NOT NULL,
  "familyId"        text NOT NULL,
  "completedDays"   jsonb NOT NULL DEFAULT '[]'::jsonb,
  "currentStreak"   integer NOT NULL DEFAULT 0,
  "longestStreak"   integer NOT NULL DEFAULT 0,
  "startedAt"       text NOT NULL,
  "lastCompletedAt" text
);

-- 2. Enable RLS + policies (family-scoped access)
-- ---------------------------------------------------------------------------

ALTER TABLE prayer_wall ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "prayer_wall_all" ON prayer_wall;
CREATE POLICY "prayer_wall_all" ON prayer_wall FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reading_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reading_plans_all" ON reading_plans;
CREATE POLICY "reading_plans_all" ON reading_plans FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reading_plan_progress ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reading_plan_progress_all" ON reading_plan_progress;
CREATE POLICY "reading_plan_progress_all" ON reading_plan_progress FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- 3. Drop legacy permissive bootstrap policies (if schema.sql was run before)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  EXECUTE format('DROP POLICY IF EXISTS "prayer_wall_rw_anon" ON prayer_wall');
  EXECUTE format('DROP POLICY IF EXISTS "reading_plans_rw_anon" ON reading_plans');
  EXECUTE format('DROP POLICY IF EXISTS "reading_plan_progress_rw_anon" ON reading_plan_progress');
END $$;

-- Done! The app's syncToCloud will start syncing to these tables automatically.
