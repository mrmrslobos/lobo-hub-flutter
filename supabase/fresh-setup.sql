-- =============================================================================
-- Lobo Hub — Complete Fresh Database Setup
-- =============================================================================
-- Run this ONCE on a brand-new Supabase project (SQL Editor → Run).
--
-- What this does:
--   1. Creates all 28 tables with every column the app needs
--   2. Adds indexes for performance
--   3. Creates the auth_is_member_of() helper function
--   4. Enables RLS with proper family/user-scoped policies
--
-- No ALTER TABLE migrations needed — everything is built in from scratch.
-- Passwords are NOT stored — Supabase Auth handles authentication.
-- =============================================================================


-- =============================================================================
-- TABLES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- users
-- NOTE: No password column — authentication is handled entirely by Supabase Auth.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id     text PRIMARY KEY,
  name   text NOT NULL,
  email  text NOT NULL UNIQUE,
  avatar text
);

-- ---------------------------------------------------------------------------
-- families
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS families (
  id                   text PRIMARY KEY,
  name                 text NOT NULL,
  "ownerId"            text NOT NULL,
  "joinCode"           text NOT NULL UNIQUE,
  announcement         text,
  "announcementAuthor" text,
  "subscriptionTier"   text,
  "enabledModules"     jsonb NOT NULL DEFAULT '[]'::jsonb,
  settings             jsonb,
  "createdAt"          text,
  "welcomeDismissed"   boolean NOT NULL DEFAULT false,
  "weeklyDigest"              boolean DEFAULT true,
  "weeklyDigestDay"           smallint DEFAULT 0,
  "weeklyDigestHour"          smallint DEFAULT 8,
  "dailyDevotionalEnabled"    boolean NOT NULL DEFAULT false,
  "dailyDevotionalHour"       smallint NOT NULL DEFAULT 7,
  "dailyDevotionalMinute"     smallint NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS family_members (
  "userId"       text NOT NULL,
  "familyId"     text NOT NULL,
  role           text NOT NULL,
  "moduleAccess" jsonb,
  "displayName"  text,
  PRIMARY KEY ("userId", "familyId")
);

-- ---------------------------------------------------------------------------
-- Helper function (defined here so family_members already exists)
-- Is the currently-authenticated user a member of family `fid`?
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
-- ---------------------------------------------------------------------------
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

  SELECT email INTO usr_email FROM auth.users WHERE id = auth.uid();
  IF usr_email IS NULL THEN RETURN; END IF;

  SELECT id INTO old_id
  FROM users
  WHERE email = usr_email AND id <> new_id
  LIMIT 1;

  IF old_id IS NULL THEN RETURN; END IF;

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
-- tasks
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tasks (
  id               text PRIMARY KEY,
  "familyId"       text NOT NULL,
  "creatorId"      text NOT NULL,
  title            text NOT NULL,
  notes            text,
  "dueDate"        text NOT NULL DEFAULT '',
  "dueTime"        text,
  "reminderMinutes" integer,
  priority         text NOT NULL,
  completed        boolean NOT NULL DEFAULT false,
  "completedBy"    text,
  "updatedBy"      text,
  visibility       text NOT NULL DEFAULT 'FAMILY',
  assignees        jsonb NOT NULL DEFAULT '[]'::jsonb,
  tags             jsonb NOT NULL DEFAULT '[]'::jsonb,
  recurrence       text DEFAULT 'NONE'
);

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
  id                   text PRIMARY KEY,
  "familyId"           text NOT NULL,
  "creatorId"          text NOT NULL DEFAULT '',
  title                text NOT NULL,
  description          text,
  location             text,
  start                text NOT NULL,
  "end"                text NOT NULL,
  visibility           text NOT NULL DEFAULT 'FAMILY',
  "sharedWith"         jsonb NOT NULL DEFAULT '[]'::jsonb,
  checklist            jsonb NOT NULL DEFAULT '[]'::jsonb,
  "budgetEstimate"     numeric,
  "externalCalendarId" text,
  "externalUid"        text,
  recurrence           text DEFAULT 'NONE'
);

-- ---------------------------------------------------------------------------
-- recipes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recipes (
  id          text PRIMARY KEY,
  "familyId"  text NOT NULL,
  title       text NOT NULL,
  ingredients jsonb NOT NULL DEFAULT '[]'::jsonb,
  steps       jsonb NOT NULL DEFAULT '[]'::jsonb,
  servings    integer NOT NULL,
  tags        jsonb NOT NULL DEFAULT '[]'::jsonb,
  image       text
);

-- ---------------------------------------------------------------------------
-- meal_plans
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS meal_plans (
  id           text PRIMARY KEY,
  "familyId"   text NOT NULL,
  date         text NOT NULL,
  "mealType"   text NOT NULL,
  "recipeId"   text,
  "customMeal" text
);

-- ---------------------------------------------------------------------------
-- lists
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lists (
  id          text PRIMARY KEY,
  "familyId"  text NOT NULL,
  "creatorId" text NOT NULL DEFAULT '',
  title       text NOT NULL,
  items       jsonb NOT NULL DEFAULT '[]'::jsonb,
  category    text NOT NULL,
  visibility  text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- devotionals
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS devotionals (
  id                  text PRIMARY KEY,
  "familyId"          text NOT NULL DEFAULT '',
  "creatorId"         text NOT NULL DEFAULT '',
  title               text NOT NULL,
  scripture           text NOT NULL,
  content             text NOT NULL,
  "reflectionPrompts" jsonb NOT NULL DEFAULT '[]'::jsonb,
  prayer              text,
  "userPrayer"        text,
  tags                jsonb NOT NULL DEFAULT '[]'::jsonb,
  date                text NOT NULL,
  visibility          text NOT NULL DEFAULT 'FAMILY',
  "isFavorited"       boolean NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------------------
-- fitness (personal metrics: weight, steps, workouts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fitness (
  id       text PRIMARY KEY,
  "userId" text NOT NULL,
  type     text NOT NULL,
  value    numeric NOT NULL,
  date     text NOT NULL,
  notes    text
);

-- ---------------------------------------------------------------------------
-- fitness_plans (AI-generated personal workout plans)
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

-- ---------------------------------------------------------------------------
-- budget_categories
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS budget_categories (
  id          text PRIMARY KEY,
  "familyId"  text NOT NULL,
  "creatorId" text NOT NULL DEFAULT '',
  name        text NOT NULL,
  "limit"     numeric NOT NULL,
  color       text NOT NULL,
  visibility  text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
  id           text PRIMARY KEY,
  "familyId"   text NOT NULL,
  "creatorId"  text NOT NULL DEFAULT '',
  "categoryId" text NOT NULL,
  amount       numeric NOT NULL,
  type         text NOT NULL,
  date         text NOT NULL,
  description  text NOT NULL,
  visibility   text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- ai_history
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_history (
  id          text PRIMARY KEY,
  "userId"    text NOT NULL,
  "familyId"  text NOT NULL,
  module      text NOT NULL,
  prompt      text NOT NULL,
  response    text NOT NULL,
  "createdAt" text NOT NULL
);

-- ---------------------------------------------------------------------------
-- daily_habits (personal habit tracker)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_habits (
  id          text PRIMARY KEY,
  "userId"    text NOT NULL,
  label       text NOT NULL,
  icon        text NOT NULL,
  color       text NOT NULL,
  "createdAt" text NOT NULL,
  "order"     integer NOT NULL
);

-- ---------------------------------------------------------------------------
-- daily_habit_completions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_habit_completions (
  id            text PRIMARY KEY,
  "habitId"     text NOT NULL,
  "userId"      text NOT NULL,
  date          text NOT NULL,
  "completedAt" text NOT NULL
);

-- ---------------------------------------------------------------------------
-- chores
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chores (
  id           text PRIMARY KEY,
  "familyId"   text NOT NULL,
  "creatorId"  text NOT NULL,
  title        text NOT NULL,
  description  text,
  icon         text NOT NULL DEFAULT '🧹',
  points       integer NOT NULL DEFAULT 10,
  reward       numeric,
  frequency    text NOT NULL DEFAULT 'DAILY',
  "daysOfWeek" jsonb NOT NULL DEFAULT '[]'::jsonb,
  assignees    jsonb NOT NULL DEFAULT '[]'::jsonb,
  color        text NOT NULL DEFAULT '#6366f1',
  visibility   text NOT NULL DEFAULT 'FAMILY',
  "createdAt"  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- chore_completions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chore_completions (
  id            text PRIMARY KEY,
  "choreId"     text NOT NULL,
  "userId"      text NOT NULL,
  "familyId"    text NOT NULL,
  date          text NOT NULL,
  "completedAt" text NOT NULL
);

-- ---------------------------------------------------------------------------
-- polls
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS polls (
  id              text PRIMARY KEY,
  "familyId"      text NOT NULL,
  "creatorId"     text NOT NULL,
  question        text NOT NULL,
  options         jsonb NOT NULL DEFAULT '[]'::jsonb,
  "allowMultiple" boolean NOT NULL DEFAULT false,
  anonymous       boolean NOT NULL DEFAULT false,
  status          text NOT NULL DEFAULT 'OPEN',
  deadline        text,
  visibility      text NOT NULL DEFAULT 'FAMILY',
  "createdAt"     text NOT NULL
);

-- ---------------------------------------------------------------------------
-- poll_votes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poll_votes (
  id         text PRIMARY KEY,
  "pollId"   text NOT NULL,
  "optionId" text NOT NULL,
  "userId"   text NOT NULL,
  "familyId" text NOT NULL,
  "votedAt"  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- external_calendars
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS external_calendars (
  id           text PRIMARY KEY,
  "familyId"   text NOT NULL,
  "creatorId"  text NOT NULL,
  name         text NOT NULL,
  url          text,
  color        text NOT NULL DEFAULT '#6366f1',
  type         text NOT NULL DEFAULT 'OTHER',
  enabled      boolean NOT NULL DEFAULT true,
  "lastSynced" text,
  "createdAt"  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- rewards (family rewards catalogue)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rewards (
  id            text PRIMARY KEY,
  "familyId"    text NOT NULL,
  title         text NOT NULL,
  "pointCost"   int NOT NULL DEFAULT 0,
  description   text,
  "redeemedBy"  jsonb NOT NULL DEFAULT '[]'::jsonb
);

-- ---------------------------------------------------------------------------
-- reward_items (chore reward store)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- reward_redemptions
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- savings_goals
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- prayer_wall
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prayer_wall (
  id                  text PRIMARY KEY,
  "familyId"          text NOT NULL,
  "creatorId"         text NOT NULL,
  type                text NOT NULL,
  text                text NOT NULL,
  "originalRequestId" text,
  reactions           jsonb NOT NULL DEFAULT '[]'::jsonb,
  "prayedByIds"       jsonb NOT NULL DEFAULT '[]'::jsonb,
  date                text NOT NULL,
  "answeredAt"        text,
  visibility          text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- reading_plans
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- reading_plan_progress
-- ---------------------------------------------------------------------------
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
-- period_cycles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS period_cycles (
  id          text PRIMARY KEY,
  "userId"    text NOT NULL,
  "familyId"  text NOT NULL,
  "startDate" timestamptz NOT NULL,
  "endDate"   timestamptz,
  "flowLevel" text NOT NULL DEFAULT 'MEDIUM',
  notes       text,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS period_cycles_user_idx ON period_cycles ("userId");
CREATE INDEX IF NOT EXISTS period_cycles_family_idx ON period_cycles ("familyId");

-- ---------------------------------------------------------------------------
-- period_symptoms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS period_symptoms (
  id          text PRIMARY KEY,
  "userId"    text NOT NULL,
  "familyId"  text NOT NULL,
  date        timestamptz NOT NULL,
  symptoms    jsonb NOT NULL DEFAULT '[]'::jsonb,
  mood        text,
  "painLevel" int,
  notes       text,
  "createdAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS period_symptoms_user_idx ON period_symptoms ("userId");
CREATE INDEX IF NOT EXISTS period_symptoms_family_idx ON period_symptoms ("familyId");

-- ---------------------------------------------------------------------------
-- device_tokens (push notifications — one row per user per platform)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "userId"    text NOT NULL,
  "familyId"  text NOT NULL,
  token       text NOT NULL,
  platform    text NOT NULL CHECK (platform IN ('ios', 'android')),
  "updatedAt" timestamptz NOT NULL DEFAULT now(),
  UNIQUE ("userId", platform)
);

CREATE INDEX IF NOT EXISTS device_tokens_family_idx ON device_tokens ("familyId");


-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- ---------------------------------------------------------------------------
-- users — own row, OR any co-family member can view
-- ---------------------------------------------------------------------------
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

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

CREATE POLICY "users_insert" ON users FOR INSERT
  WITH CHECK (id = auth.uid()::text);

CREATE POLICY "users_update" ON users FOR UPDATE
  USING (id = auth.uid()::text)
  WITH CHECK (id = auth.uid()::text);

CREATE POLICY "users_delete" ON users FOR DELETE
  USING (id = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- families
-- ---------------------------------------------------------------------------
ALTER TABLE families ENABLE ROW LEVEL SECURITY;

CREATE POLICY "families_select" ON families FOR SELECT
  USING (auth_is_member_of(id));

CREATE POLICY "families_insert" ON families FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "families_update" ON families FOR UPDATE
  USING ("ownerId" = auth.uid()::text)
  WITH CHECK ("ownerId" = auth.uid()::text);

CREATE POLICY "families_delete" ON families FOR DELETE
  USING ("ownerId" = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "family_members_select" ON family_members FOR SELECT
  USING (auth_is_member_of("familyId"));

-- A user may add themselves (join by code) OR owner/admin may add anyone
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
-- Family-scoped tables — any family member can read/write
-- ---------------------------------------------------------------------------
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tasks_all" ON tasks FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events_all" ON events FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "recipes_all" ON recipes FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE meal_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "meal_plans_all" ON meal_plans FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "lists_all" ON lists FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE devotionals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "devotionals_all" ON devotionals FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE budget_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "budget_categories_all" ON budget_categories FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "transactions_all" ON transactions FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE ai_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ai_history_all" ON ai_history FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE chores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "chores_all" ON chores FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE chore_completions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "chore_completions_all" ON chore_completions FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "polls_all" ON polls FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "poll_votes_all" ON poll_votes FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE external_calendars ENABLE ROW LEVEL SECURITY;
CREATE POLICY "external_calendars_all" ON external_calendars FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rewards_all" ON rewards FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reward_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reward_items_all" ON reward_items FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reward_redemptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reward_redemptions_all" ON reward_redemptions FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE savings_goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "savings_goals_all" ON savings_goals FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE prayer_wall ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prayer_wall_all" ON prayer_wall FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reading_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reading_plans_all" ON reading_plans FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

ALTER TABLE reading_plan_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reading_plan_progress_all" ON reading_plan_progress FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- ---------------------------------------------------------------------------
-- Personal tables (no familyId) — each user sees only their own rows
-- ---------------------------------------------------------------------------
ALTER TABLE fitness ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fitness_all" ON fitness FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

ALTER TABLE fitness_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fitness_plans_all" ON fitness_plans FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

ALTER TABLE daily_habits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "daily_habits_all" ON daily_habits FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

ALTER TABLE daily_habit_completions ENABLE ROW LEVEL SECURITY;
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

-- period_cycles — users manage only their own rows
ALTER TABLE period_cycles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "period_cycles_all" ON period_cycles FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- period_symptoms — users manage only their own rows
ALTER TABLE period_symptoms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "period_symptoms_all" ON period_symptoms FOR ALL
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

-- device_tokens — users manage only their own tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own tokens" ON device_tokens FOR ALL
  USING  (auth.uid()::text = "userId")
  WITH CHECK (auth.uid()::text = "userId");


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
-- DONE
-- =============================================================================
-- Next steps:
--   1. Copy your Supabase URL + anon key into .env (see .env.example)
--   2. Sign up in the app — your Supabase Auth UUID becomes your user ID
--   3. Create or join a family — all data syncs automatically
--   4. (Optional) Set up push notifications via Database Webhooks pointing to
--      the notify-family Edge Function (see supabase/functions/notify-family/)
-- =============================================================================
