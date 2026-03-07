-- =============================================================================
-- Lobo Hub — Supabase Row Level Security (RLS) Migration
-- =============================================================================
-- Run this entire script in the Supabase SQL Editor (Dashboard → SQL Editor).
--
-- What this does:
--   1. Enables RLS on every application table
--   2. Adds policies so each family can ONLY read/write their own data
--   3. Uses auth.uid() (Supabase Auth) — no plain-text passwords ever stored
--
-- IMPORTANT: Column names in this DB are camelCase (e.g. "familyId", "userId")
-- because they were created via the Supabase JS upsert with camelCase objects.
-- Quoted identifiers are used throughout to match exactly.
--
-- Tables that are personal (no familyId): fitness, fitness_plans,
-- daily_habits, daily_habit_completions — secured by userId = auth.uid() instead.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: is the currently-authenticated user a member of family `fid`?
-- SECURITY DEFINER bypasses RLS when checking family_members itself.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_is_member_of(fid text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM family_members
    WHERE "familyId" = fid
      AND "userId" = auth.uid()::text
  );
$$;

-- ---------------------------------------------------------------------------
-- Helper function: look up a family by join code (bypasses families_select RLS)
-- The families_select policy only lets existing members read their families.
-- A user trying to JOIN via code is not yet a member, so a direct table query
-- returns empty even for a valid code. Running as SECURITY DEFINER (postgres)
-- bypasses RLS for this single, safe operation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION find_family_by_join_code(code text)
RETURNS SETOF families
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT * FROM families WHERE "joinCode" = code LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Recovery: migrate all Supabase rows from a legacy random-ID profile to the
-- caller's Supabase Auth UUID.  SECURITY DEFINER lets this run as postgres
-- (bypasses RLS) so it can update rows that the caller cannot access directly
-- because the ownerId/userId still holds the old random ID.
--
-- This is idempotent: if no old profile with the same email exists, or if the
-- migration already ran, the function returns immediately without changes.
--
-- Called by the client:
--   1. In resolveUserProfile on every login (catches recovery cases where
--      the local migration ran but the Supabase rows were never updated).
--   2. As a recovery step in syncToCloud when RLS violations are detected
--      for the families or family_members tables.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS claim_owned_families();
CREATE OR REPLACE FUNCTION claim_owned_families()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_id    text := auth.uid()::text;
  old_id    text;
  usr_email text;
BEGIN
  IF new_id IS NULL THEN RETURN; END IF;

  -- Resolve the caller's email from Supabase Auth (requires SECURITY DEFINER)
  SELECT email INTO usr_email FROM auth.users WHERE id = auth.uid();
  IF usr_email IS NULL THEN RETURN; END IF;

  -- Find a legacy profile row with the same email but a different (old) ID
  SELECT id INTO old_id
  FROM users
  WHERE email = usr_email AND id <> new_id
  LIMIT 1;

  IF old_id IS NULL THEN RETURN; END IF; -- already up-to-date, nothing to do

  -- Migrate all rows that reference the old ID to the new UUID.
  -- Tables with userId-based RLS policies must be updated here;
  -- family-scoped tables (tasks, chores, etc.) will be re-synced automatically
  -- once family_members is corrected and auth_is_member_of() starts returning true.
  UPDATE users            SET id         = new_id WHERE id         = old_id;
  UPDATE families         SET "ownerId"  = new_id WHERE "ownerId"  = old_id;
  UPDATE family_members   SET "userId"   = new_id WHERE "userId"   = old_id;
  UPDATE fitness          SET "userId"   = new_id WHERE "userId"   = old_id;
  UPDATE fitness_plans    SET "userId"   = new_id WHERE "userId"   = old_id;
  UPDATE daily_habits     SET "userId"   = new_id WHERE "userId"   = old_id;
  UPDATE daily_habit_completions SET "userId" = new_id WHERE "userId" = old_id;
  UPDATE device_tokens    SET "userId"   = new_id WHERE "userId"   = old_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Newer tables that may not exist in older schema.sql deployments.
-- CREATE TABLE IF NOT EXISTS is safe to run even if the tables already exist.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS fitness_plans (
  id           text PRIMARY KEY,
  "userId"     text NOT NULL,
  summary      text NOT NULL,
  "weeklyPlan" jsonb NOT NULL DEFAULT '[]'::jsonb,
  tips         jsonb NOT NULL DEFAULT '[]'::jsonb,
  profile      jsonb NOT NULL DEFAULT '{}'::jsonb,
  "createdAt"  text NOT NULL
);

CREATE TABLE IF NOT EXISTS reward_items (
  id          text PRIMARY KEY,
  "familyId"  text NOT NULL,
  "creatorId" text NOT NULL,
  title       text NOT NULL,
  description text,
  cost        numeric NOT NULL,
  icon        text NOT NULL,
  active      boolean NOT NULL DEFAULT true,
  "createdAt" text NOT NULL
);

CREATE TABLE IF NOT EXISTS reward_redemptions (
  id            text PRIMARY KEY,
  "familyId"    text NOT NULL,
  "userId"      text NOT NULL,
  "rewardId"    text,
  "rewardTitle" text NOT NULL,
  amount        numeric NOT NULL,
  status        text NOT NULL DEFAULT 'PENDING',
  "requestedAt" text NOT NULL,
  "resolvedAt"  text,
  "resolvedBy"  text
);

CREATE TABLE IF NOT EXISTS savings_goals (
  id             text PRIMARY KEY,
  "familyId"     text NOT NULL,
  "userId"       text NOT NULL,
  title          text NOT NULL,
  icon           text NOT NULL,
  "imageUrl"     text,
  "targetAmount" numeric NOT NULL,
  "savedAmount"  numeric NOT NULL DEFAULT 0,
  "createdAt"    text NOT NULL,
  "completedAt"  text
);

CREATE TABLE IF NOT EXISTS prayer_wall (
  id                  text PRIMARY KEY,
  "familyId"          text NOT NULL,
  "creatorId"         text NOT NULL,
  type                text NOT NULL,
  text                text NOT NULL,
  "originalRequestId" text,
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

-- ---------------------------------------------------------------------------
-- Drop permissive bootstrap policies created by schema.sql so they don't
-- conflict with the stricter per-table policies below.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users','families','family_members','tasks','events','recipes','meal_plans',
    'lists','devotionals','fitness','fitness_plans','budget_categories','transactions',
    'ai_history','daily_habits','daily_habit_completions','chores','chore_completions',
    'polls','poll_votes','external_calendars','reward_items','reward_redemptions',
    'savings_goals','prayer_wall','reading_plans','reading_plan_progress'
  ]
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "%s_rw_anon" ON %I', t, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Own row, OR any co-family member
DROP POLICY IF EXISTS "users_select" ON users;
CREATE POLICY "users_select" ON users FOR SELECT
  USING (
    id = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm1
      JOIN family_members fm2 ON fm1."familyId" = fm2."familyId"
      WHERE fm1."userId" = auth.uid()::text
        AND fm2."userId" = users.id
    )
  );

DROP POLICY IF EXISTS "users_insert" ON users;
CREATE POLICY "users_insert" ON users FOR INSERT
  WITH CHECK (id = auth.uid()::text);

DROP POLICY IF EXISTS "users_update" ON users;
CREATE POLICY "users_update" ON users FOR UPDATE
  USING (id = auth.uid()::text)
  WITH CHECK (id = auth.uid()::text);

DROP POLICY IF EXISTS "users_delete" ON users;
CREATE POLICY "users_delete" ON users FOR DELETE
  USING (id = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- families
-- ---------------------------------------------------------------------------
ALTER TABLE families ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "families_select" ON families;
CREATE POLICY "families_select" ON families FOR SELECT
  USING (auth_is_member_of(id));

DROP POLICY IF EXISTS "families_insert" ON families;
CREATE POLICY "families_insert" ON families FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "families_update" ON families;
CREATE POLICY "families_update" ON families FOR UPDATE
  USING ("ownerId" = auth.uid()::text)
  WITH CHECK ("ownerId" = auth.uid()::text);

DROP POLICY IF EXISTS "families_delete" ON families;
CREATE POLICY "families_delete" ON families FOR DELETE
  USING ("ownerId" = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "family_members_select" ON family_members;
CREATE POLICY "family_members_select" ON family_members FOR SELECT
  USING (auth_is_member_of("familyId"));

-- A user may add themselves (join by code) OR owner/admin may add anyone
DROP POLICY IF EXISTS "family_members_insert" ON family_members;
CREATE POLICY "family_members_insert" ON family_members FOR INSERT
  WITH CHECK (
    "userId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm."familyId" = family_members."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  );

DROP POLICY IF EXISTS "family_members_update" ON family_members;
CREATE POLICY "family_members_update" ON family_members FOR UPDATE
  -- A user may update their OWN membership row (e.g. upsert during sync),
  -- OR an OWNER/ADMIN may update any member's row in their family.
  -- Without the self-update clause, upserts by regular MEMBERs fail:
  -- the first INSERT succeeds but subsequent upserts (ON CONFLICT → UPDATE)
  -- are blocked because only OWNER/ADMIN rows would pass the USING check.
  USING (
    "userId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm."familyId" = family_members."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  )
  WITH CHECK (
    "userId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm."familyId" = family_members."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  );

DROP POLICY IF EXISTS "family_members_delete" ON family_members;
CREATE POLICY "family_members_delete" ON family_members FOR DELETE
  USING (
    "userId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm."familyId" = family_members."familyId"
        AND fm."userId" = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  );

-- ---------------------------------------------------------------------------
-- Tables with familyId — members can do everything
-- ---------------------------------------------------------------------------
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tasks_all" ON tasks;
CREATE POLICY "tasks_all" ON tasks FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "events_all" ON events;
CREATE POLICY "events_all" ON events FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "recipes_all" ON recipes;
CREATE POLICY "recipes_all" ON recipes FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE meal_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "meal_plans_all" ON meal_plans;
CREATE POLICY "meal_plans_all" ON meal_plans FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE lists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "lists_all" ON lists;
CREATE POLICY "lists_all" ON lists FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE devotionals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "devotionals_all" ON devotionals;
CREATE POLICY "devotionals_all" ON devotionals FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE budget_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "budget_categories_all" ON budget_categories;
CREATE POLICY "budget_categories_all" ON budget_categories FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "transactions_all" ON transactions;
CREATE POLICY "transactions_all" ON transactions FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE ai_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ai_history_all" ON ai_history;
CREATE POLICY "ai_history_all" ON ai_history FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE chores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "chores_all" ON chores;
CREATE POLICY "chores_all" ON chores FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE chore_completions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "chore_completions_all" ON chore_completions;
CREATE POLICY "chore_completions_all" ON chore_completions FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "polls_all" ON polls;
CREATE POLICY "polls_all" ON polls FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "poll_votes_all" ON poll_votes;
CREATE POLICY "poll_votes_all" ON poll_votes FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE external_calendars ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "external_calendars_all" ON external_calendars;
CREATE POLICY "external_calendars_all" ON external_calendars FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reward_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reward_items_all" ON reward_items;
CREATE POLICY "reward_items_all" ON reward_items FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reward_redemptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reward_redemptions_all" ON reward_redemptions;
CREATE POLICY "reward_redemptions_all" ON reward_redemptions FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE savings_goals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "savings_goals_all" ON savings_goals;
CREATE POLICY "savings_goals_all" ON savings_goals FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

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

-- ---------------------------------------------------------------------------
-- Personal tables (no familyId) — secured by userId only
-- Each user can only read/write their own rows
-- ---------------------------------------------------------------------------

-- fitness metrics
ALTER TABLE fitness ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fitness_all" ON fitness;
CREATE POLICY "fitness_all" ON fitness FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- fitness plans
ALTER TABLE fitness_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fitness_plans_all" ON fitness_plans;
CREATE POLICY "fitness_plans_all" ON fitness_plans FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- daily habits
ALTER TABLE daily_habits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "daily_habits_all" ON daily_habits;
CREATE POLICY "daily_habits_all" ON daily_habits FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- daily habit completions — join back to daily_habits to check ownership
ALTER TABLE daily_habit_completions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "daily_habit_completions_all" ON daily_habit_completions;
CREATE POLICY "daily_habit_completions_all" ON daily_habit_completions FOR ALL
  USING (
    "userId" = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM daily_habits dh
      WHERE dh.id = daily_habit_completions."habitId"
        AND dh."userId" = auth.uid()::text
    )
  )
  WITH CHECK (
    "userId" = auth.uid()::text
  );

-- =============================================================================
-- PERMISSIONS
-- =============================================================================
-- Supabase's Table Editor auto-grants these, but tables created via the SQL
-- Editor don't always inherit them depending on project configuration.
-- Without these grants, Postgres denies access before RLS even evaluates,
-- so all reads and writes silently fail even with a valid auth session.
-- =============================================================================

-- Allow roles to use the public schema
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Authenticated users can read and write their own/family data (RLS limits rows)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- Anon users can only read (used for join-by-code lookup before auth)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;

-- Sequences (auto-increment PKs, e.g. device_tokens.id)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon;

-- Apply the same grants to any tables added in future migrations
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO authenticated, anon;

-- =============================================================================
-- DONE — next steps:
--
-- 1. Sign up fresh in the app — your Supabase Auth UUID becomes your user ID
-- 2. The app will auto-migrate your existing family data to the new UUID
--    (see the resolveUserProfile migration logic in App.tsx)
-- 3. Every family's data is now invisible to all other families
-- =============================================================================
