-- =============================================================================
-- Lobo Hub — Complete Fresh Database Setup
-- =============================================================================
-- Run this ONCE on a brand-new Supabase project (SQL Editor → Run).
--
-- What this does:
--   1. Creates all tables with every column the app needs
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
  id                       text PRIMARY KEY,
  name                     text NOT NULL,
  owner_id                 text NOT NULL,
  join_code                text NOT NULL UNIQUE,
  announcement             text,
  announcement_author      text,
  subscription_tier        text,
  enabled_modules          jsonb NOT NULL DEFAULT '[]'::jsonb,
  settings                 jsonb,
  created_at               text,
  welcome_dismissed        boolean NOT NULL DEFAULT false,
  weekly_digest            boolean DEFAULT true,
  weekly_digest_day        smallint DEFAULT 0,
  weekly_digest_hour       smallint DEFAULT 8,
  daily_devotional_enabled boolean NOT NULL DEFAULT false,
  daily_devotional_hour    smallint NOT NULL DEFAULT 7,
  daily_devotional_minute  smallint NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS family_members (
  user_id       text NOT NULL,
  family_id     text NOT NULL,
  role          text NOT NULL,
  module_access jsonb,
  display_name  text,
  PRIMARY KEY (user_id, family_id)
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
    WHERE family_id = fid
      AND user_id = auth.uid()::text
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
  SELECT * FROM families WHERE join_code = code LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Recovery: migrate all Supabase rows from a legacy random-ID profile to the
-- caller's Supabase Auth UUID.  SECURITY DEFINER lets this run as postgres
-- (bypasses RLS) so it can update rows that the caller cannot access directly
-- because the owner_id/user_id still holds the old random ID.
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

  UPDATE users            SET id       = new_id WHERE id       = old_id;
  UPDATE families         SET owner_id = new_id WHERE owner_id = old_id;
  UPDATE family_members   SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE fitness          SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE fitness_plans    SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE daily_habits     SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE daily_habit_completions SET user_id = new_id WHERE user_id = old_id;
  UPDATE device_tokens    SET user_id  = new_id WHERE user_id  = old_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- tasks
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tasks (
  id               text PRIMARY KEY,
  family_id        text NOT NULL,
  creator_id       text NOT NULL,
  title            text NOT NULL,
  notes            text,
  due_date         text NOT NULL DEFAULT '',
  due_time         text,
  reminder_minutes integer,
  priority         text NOT NULL,
  completed        boolean NOT NULL DEFAULT false,
  completed_by     text,
  updated_by       text,
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
  family_id            text NOT NULL,
  creator_id           text NOT NULL DEFAULT '',
  title                text NOT NULL,
  description          text,
  location             text,
  start                text NOT NULL,
  "end"                text NOT NULL,
  visibility           text NOT NULL DEFAULT 'FAMILY',
  shared_with          jsonb NOT NULL DEFAULT '[]'::jsonb,
  checklist            jsonb NOT NULL DEFAULT '[]'::jsonb,
  budget_estimate      numeric,
  external_calendar_id text,
  external_uid         text,
  recurrence           text DEFAULT 'NONE'
);

-- ---------------------------------------------------------------------------
-- recipes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recipes (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
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
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  date        text NOT NULL,
  meal_type   text NOT NULL,
  recipe_id   text,
  custom_meal text
);

-- ---------------------------------------------------------------------------
-- lists
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lists (
  id         text PRIMARY KEY,
  family_id  text NOT NULL,
  creator_id text NOT NULL DEFAULT '',
  title      text NOT NULL,
  items      jsonb NOT NULL DEFAULT '[]'::jsonb,
  category   text NOT NULL,
  visibility text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- devotionals
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS devotionals (
  id                 text PRIMARY KEY,
  family_id          text NOT NULL DEFAULT '',
  creator_id         text NOT NULL DEFAULT '',
  title              text NOT NULL,
  scripture          text NOT NULL,
  content            text NOT NULL,
  reflection_prompts jsonb NOT NULL DEFAULT '[]'::jsonb,
  prayer             text,
  user_prayer        text,
  tags               jsonb NOT NULL DEFAULT '[]'::jsonb,
  date               text NOT NULL,
  visibility         text NOT NULL DEFAULT 'FAMILY',
  is_favorited       boolean NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------------------
-- fitness (personal metrics: weight, steps, workouts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fitness (
  id      text PRIMARY KEY,
  user_id text NOT NULL,
  type    text NOT NULL,
  value   numeric NOT NULL,
  date    text NOT NULL,
  notes   text
);

-- ---------------------------------------------------------------------------
-- fitness_plans (AI-generated personal workout plans)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fitness_plans (
  id          text PRIMARY KEY,
  user_id     text NOT NULL,
  summary     text NOT NULL,
  weekly_plan jsonb NOT NULL DEFAULT '[]'::jsonb,
  tips        jsonb NOT NULL DEFAULT '[]'::jsonb,
  profile     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- fitness_logs (personal workout logs)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fitness_logs (
  id               text PRIMARY KEY,
  family_id       text NOT NULL,
  user_id         text NOT NULL,
  activity        text NOT NULL,
  duration_minutes text NOT NULL,
  calories_burned  text,
  notes            text,
  date             text NOT NULL
);

-- ---------------------------------------------------------------------------
-- workout_sessions / workout_exercises / workout_sets (Strong integration)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workout_sessions (
  id                 text PRIMARY KEY,
  family_id         text NOT NULL,
  user_id           text NOT NULL,
  title             text NOT NULL,
  date              text NOT NULL,
  duration_minutes  integer NOT NULL DEFAULT 0,
  notes             text,
  created_at        text NOT NULL
);

CREATE TABLE IF NOT EXISTS workout_exercises (
  id              text PRIMARY KEY,
  family_id      text NOT NULL,
  user_id        text NOT NULL,
  session_id     text NOT NULL,
  exercise_name  text NOT NULL,
  "order"        integer NOT NULL DEFAULT 0,
  rest_seconds   integer NOT NULL DEFAULT 60,
  notes          text,
  created_at     text NOT NULL
);

CREATE TABLE IF NOT EXISTS workout_sets (
  id           text PRIMARY KEY,
  family_id   text NOT NULL,
  user_id     text NOT NULL,
  exercise_id text NOT NULL,
  set_number  integer NOT NULL,
  reps         text NOT NULL,
  weight       text,
  completed    boolean NOT NULL DEFAULT false,
  notes        text,
  created_at   text NOT NULL
);

-- ---------------------------------------------------------------------------
-- budget_categories
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS budget_categories (
  id         text PRIMARY KEY,
  family_id  text NOT NULL,
  creator_id text NOT NULL DEFAULT '',
  name       text NOT NULL,
  "limit"    numeric NOT NULL,
  color      text NOT NULL,
  visibility text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  creator_id  text NOT NULL DEFAULT '',
  category_id text NOT NULL,
  amount      numeric NOT NULL,
  type        text NOT NULL,
  date        text NOT NULL,
  description text NOT NULL,
  visibility  text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- ai_history
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_history (
  id         text PRIMARY KEY,
  user_id    text NOT NULL,
  family_id  text NOT NULL,
  module     text NOT NULL,
  prompt     text NOT NULL,
  response   text NOT NULL,
  created_at text NOT NULL
);

-- ---------------------------------------------------------------------------
-- daily_habits (personal habit tracker)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_habits (
  id           text PRIMARY KEY,
  user_id      text NOT NULL,
  family_id    text,
  label        text NOT NULL,
  icon         text NOT NULL DEFAULT '',
  color        text NOT NULL DEFAULT '#6366f1',
  description  text,
  is_shared    boolean NOT NULL DEFAULT false,
  frequency    text,
  target_value numeric,
  target_unit  text,
  created_at   text NOT NULL,
  "order"      integer NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- daily_habit_completions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_habit_completions (
  id           text PRIMARY KEY,
  habit_id     text NOT NULL,
  user_id      text NOT NULL,
  date         text NOT NULL,
  completed_at text NOT NULL
);

-- ---------------------------------------------------------------------------
-- chores
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chores (
  id                text PRIMARY KEY,
  family_id         text NOT NULL,
  creator_id        text NOT NULL,
  title             text NOT NULL,
  description       text,
  icon              text NOT NULL DEFAULT '🧹',
  points            integer NOT NULL DEFAULT 10,
  reward            numeric,
  frequency         text NOT NULL DEFAULT 'DAILY',
  days_of_week      jsonb NOT NULL DEFAULT '[]'::jsonb,
  assignees         jsonb NOT NULL DEFAULT '[]'::jsonb,
  color             text NOT NULL DEFAULT '#6366f1',
  visibility        text NOT NULL DEFAULT 'FAMILY',
  requires_approval boolean,
  created_at        text NOT NULL
);

-- ---------------------------------------------------------------------------
-- chore_completions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chore_completions (
  id              text PRIMARY KEY,
  chore_id        text NOT NULL,
  user_id         text NOT NULL,
  family_id       text NOT NULL,
  date            text NOT NULL,
  completed_at    text NOT NULL,
  approval_status text,
  approved_by     text,
  approved_at     text
);

-- ---------------------------------------------------------------------------
-- polls
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS polls (
  id             text PRIMARY KEY,
  family_id      text NOT NULL,
  creator_id     text NOT NULL,
  question       text NOT NULL,
  options        jsonb NOT NULL DEFAULT '[]'::jsonb,
  allow_multiple boolean NOT NULL DEFAULT false,
  anonymous      boolean NOT NULL DEFAULT false,
  status         text NOT NULL DEFAULT 'OPEN',
  deadline       text,
  visibility     text NOT NULL DEFAULT 'FAMILY',
  created_at     text NOT NULL
);

-- ---------------------------------------------------------------------------
-- poll_votes
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poll_votes (
  id        text PRIMARY KEY,
  poll_id   text NOT NULL,
  option_id text NOT NULL,
  user_id   text NOT NULL,
  family_id text NOT NULL,
  voted_at  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- external_calendars
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS external_calendars (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  creator_id  text NOT NULL,
  name        text NOT NULL,
  url         text,
  color       text NOT NULL DEFAULT '#6366f1',
  type        text NOT NULL DEFAULT 'OTHER',
  enabled     boolean NOT NULL DEFAULT true,
  last_synced text,
  created_at  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- rewards (family rewards catalogue)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rewards (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  title       text NOT NULL,
  point_cost  int NOT NULL DEFAULT 0,
  description text,
  redeemed_by jsonb NOT NULL DEFAULT '[]'::jsonb
);

-- ---------------------------------------------------------------------------
-- reward_items (chore reward store)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reward_items (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  creator_id  text NOT NULL,
  title       text NOT NULL,
  description text,
  cost        numeric NOT NULL,
  icon        text NOT NULL,
  active      boolean NOT NULL DEFAULT true,
  created_at  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- reward_redemptions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reward_redemptions (
  id           text PRIMARY KEY,
  family_id    text NOT NULL,
  user_id      text NOT NULL,
  reward_id    text,
  reward_title text NOT NULL,
  amount       numeric NOT NULL,
  status       text NOT NULL DEFAULT 'PENDING',
  requested_at text NOT NULL,
  resolved_at  text,
  resolved_by  text
);

-- ---------------------------------------------------------------------------
-- savings_goals
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS savings_goals (
  id            text PRIMARY KEY,
  family_id     text NOT NULL,
  user_id       text NOT NULL,
  title         text NOT NULL,
  icon          text NOT NULL,
  image_url     text,
  target_amount numeric NOT NULL,
  saved_amount  numeric NOT NULL DEFAULT 0,
  created_at    text NOT NULL,
  completed_at  text
);

-- ---------------------------------------------------------------------------
-- prayer_wall
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS prayer_wall (
  id                  text PRIMARY KEY,
  family_id           text NOT NULL,
  creator_id          text NOT NULL,
  type                text NOT NULL,
  text                text NOT NULL,
  original_request_id text,
  reactions           jsonb NOT NULL DEFAULT '[]'::jsonb,
  prayed_by_ids       jsonb NOT NULL DEFAULT '[]'::jsonb,
  date                text NOT NULL,
  answered_at         text,
  visibility          text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- reading_plans
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reading_plans (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  creator_id  text NOT NULL,
  title       text NOT NULL,
  description text NOT NULL,
  total_days  integer NOT NULL,
  days        jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at  text NOT NULL
);

-- ---------------------------------------------------------------------------
-- reading_plan_progress
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reading_plan_progress (
  id                text PRIMARY KEY,
  plan_id           text NOT NULL,
  user_id           text NOT NULL,
  family_id         text NOT NULL,
  completed_days    jsonb NOT NULL DEFAULT '[]'::jsonb,
  current_streak    integer NOT NULL DEFAULT 0,
  longest_streak    integer NOT NULL DEFAULT 0,
  started_at        text NOT NULL,
  last_completed_at text
);

-- ---------------------------------------------------------------------------
-- period_cycles
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS period_cycles (
  id         text PRIMARY KEY,
  user_id    text NOT NULL,
  family_id  text NOT NULL,
  start_date timestamptz NOT NULL,
  end_date   timestamptz,
  flow_level text NOT NULL DEFAULT 'MEDIUM',
  notes      text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS period_cycles_user_idx ON period_cycles (user_id);
CREATE INDEX IF NOT EXISTS period_cycles_family_idx ON period_cycles (family_id);

-- ---------------------------------------------------------------------------
-- period_symptoms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS period_symptoms (
  id         text PRIMARY KEY,
  user_id    text NOT NULL,
  family_id  text NOT NULL,
  date       timestamptz NOT NULL,
  symptoms   jsonb NOT NULL DEFAULT '[]'::jsonb,
  mood       text,
  pain_level int,
  notes      text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS period_symptoms_user_idx ON period_symptoms (user_id);
CREATE INDEX IF NOT EXISTS period_symptoms_family_idx ON period_symptoms (family_id);

-- ---------------------------------------------------------------------------
-- device_tokens (push notifications — one row per user per platform)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_tokens (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    text NOT NULL,
  family_id  text NOT NULL,
  token      text NOT NULL,
  platform   text NOT NULL CHECK (platform IN ('ios', 'android')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, platform)
);

CREATE INDEX IF NOT EXISTS device_tokens_family_idx ON device_tokens (family_id);

-- ---------------------------------------------------------------------------
-- web_push_subscriptions (Browser PWA push subscriptions)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS web_push_subscriptions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    text NOT NULL,
  family_id  text NOT NULL,
  endpoint   text NOT NULL UNIQUE,
  p256dh     text NOT NULL,
  auth       text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS web_push_family_idx ON web_push_subscriptions (family_id);

-- ---------------------------------------------------------------------------
-- special_dates (birthdays, anniversaries, etc.)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS special_dates (
  id            text PRIMARY KEY,
  family_id     text NOT NULL,
  creator_id    text NOT NULL,
  name          text NOT NULL,
  type          text NOT NULL CHECK (type IN ('BIRTHDAY','ANNIVERSARY','MEMORIAL','OTHER')),
  month         smallint NOT NULL,
  day           smallint NOT NULL,
  year          smallint,
  emoji         text NOT NULL,
  notes         text,
  reminder_days jsonb NOT NULL DEFAULT '[]'::jsonb,
  visibility    text NOT NULL DEFAULT 'FAMILY',
  created_at    text NOT NULL
);

-- ---------------------------------------------------------------------------
-- family_photos
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS family_photos (
  id           text PRIMARY KEY,
  family_id    text NOT NULL,
  uploader_id  text NOT NULL,
  url          text NOT NULL,
  caption      text,
  taken_at     text NOT NULL,
  created_at   text NOT NULL,
  reactions    jsonb NOT NULL DEFAULT '[]'::jsonb,
  milestone_id text,
  tags         jsonb NOT NULL DEFAULT '[]'::jsonb,
  visibility   text NOT NULL DEFAULT 'FAMILY'
);

-- ---------------------------------------------------------------------------
-- milestones (child development milestones)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS milestones (
  id         text PRIMARY KEY,
  family_id  text NOT NULL,
  child_id   text NOT NULL,
  title      text NOT NULL,
  emoji      text NOT NULL,
  category   text NOT NULL,
  date       text NOT NULL,
  notes      text,
  photo_ids  jsonb NOT NULL DEFAULT '[]'::jsonb,
  age_label  text,
  created_at text NOT NULL
);

-- ---------------------------------------------------------------------------
-- saved_places (location sharing)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS saved_places (
  id            text PRIMARY KEY,
  family_id     text NOT NULL,
  creator_id    text NOT NULL,
  name          text NOT NULL,
  emoji         text NOT NULL,
  latitude      numeric NOT NULL,
  longitude     numeric NOT NULL,
  radius_metres numeric NOT NULL DEFAULT 200,
  created_at    text NOT NULL
);

-- ---------------------------------------------------------------------------
-- user_locations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_locations (
  id         text PRIMARY KEY,
  family_id  text NOT NULL,
  user_id    text NOT NULL,
  latitude   numeric NOT NULL,
  longitude  numeric NOT NULL,
  accuracy   numeric,
  place_name text,
  near_place text,
  is_sharing boolean NOT NULL DEFAULT false,
  updated_at text NOT NULL
);

-- ---------------------------------------------------------------------------
-- health_records
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS health_records (
  id                      text PRIMARY KEY,
  family_id               text NOT NULL,
  member_id               text NOT NULL,
  updated_by              text NOT NULL,
  blood_type              text NOT NULL DEFAULT 'Unknown',
  allergies               jsonb NOT NULL DEFAULT '[]'::jsonb,
  medications             jsonb NOT NULL DEFAULT '[]'::jsonb,
  conditions              jsonb NOT NULL DEFAULT '[]'::jsonb,
  immunizations           jsonb NOT NULL DEFAULT '[]'::jsonb,
  emergency_contacts      jsonb NOT NULL DEFAULT '[]'::jsonb,
  doctor_name             text,
  doctor_phone            text,
  insurance_provider      text,
  insurance_policy_number text,
  notes                   text,
  updated_at              text NOT NULL,
  UNIQUE (family_id, member_id)
);

CREATE INDEX IF NOT EXISTS health_records_family_idx ON health_records (family_id);

-- ---------------------------------------------------------------------------
-- messages (family chat)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  user_id     text NOT NULL,
  text        text NOT NULL,
  reply_to_id text,
  reactions   jsonb NOT NULL DEFAULT '{}'::jsonb,
  edited_at   text,
  created_at  text NOT NULL
);

CREATE INDEX IF NOT EXISTS messages_family_idx ON messages (family_id);
CREATE INDEX IF NOT EXISTS special_dates_family_idx ON special_dates (family_id);
CREATE INDEX IF NOT EXISTS family_photos_family_idx ON family_photos (family_id);
CREATE INDEX IF NOT EXISTS milestones_family_idx ON milestones (family_id);
CREATE INDEX IF NOT EXISTS saved_places_family_idx ON saved_places (family_id);
CREATE INDEX IF NOT EXISTS user_locations_family_idx ON user_locations (family_id);


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
      JOIN family_members fm2 ON fm1.family_id = fm2.family_id
      WHERE fm1.user_id = auth.uid()::text
        AND fm2.user_id = users.id
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
  USING (owner_id = auth.uid()::text)
  WITH CHECK (owner_id = auth.uid()::text);

CREATE POLICY "families_delete" ON families FOR DELETE
  USING (owner_id = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "family_members_select" ON family_members FOR SELECT
  USING (auth_is_member_of(family_id));

CREATE POLICY "family_members_insert" ON family_members FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.family_id = family_members.family_id
        AND fm.user_id = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  );

CREATE POLICY "family_members_update" ON family_members FOR UPDATE
  USING (
    user_id = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.family_id = family_members.family_id
        AND fm.user_id = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  )
  WITH CHECK (
    user_id = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.family_id = family_members.family_id
        AND fm.user_id = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  );

CREATE POLICY "family_members_delete" ON family_members FOR DELETE
  USING (
    user_id = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.family_id = family_members.family_id
        AND fm.user_id = auth.uid()::text
        AND fm.role IN ('OWNER', 'ADMIN')
    )
  );

-- ---------------------------------------------------------------------------
-- Family-scoped tables — any family member can read/write
-- ---------------------------------------------------------------------------
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tasks_all" ON tasks FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "events_all" ON events FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "recipes_all" ON recipes FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE meal_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "meal_plans_all" ON meal_plans FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "lists_all" ON lists FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE devotionals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "devotionals_all" ON devotionals FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE budget_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "budget_categories_all" ON budget_categories FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "transactions_all" ON transactions FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE ai_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ai_history_all" ON ai_history FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE chores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "chores_all" ON chores FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE chore_completions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "chore_completions_all" ON chore_completions FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "polls_all" ON polls FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "poll_votes_all" ON poll_votes FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE external_calendars ENABLE ROW LEVEL SECURITY;
CREATE POLICY "external_calendars_all" ON external_calendars FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rewards_all" ON rewards FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE reward_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reward_items_all" ON reward_items FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE reward_redemptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reward_redemptions_all" ON reward_redemptions FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE savings_goals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "savings_goals_all" ON savings_goals FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE prayer_wall ENABLE ROW LEVEL SECURITY;
CREATE POLICY "prayer_wall_all" ON prayer_wall FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE reading_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reading_plans_all" ON reading_plans FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

ALTER TABLE reading_plan_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reading_plan_progress_all" ON reading_plan_progress FOR ALL
  USING (auth_is_member_of(family_id))
  WITH CHECK (auth_is_member_of(family_id));

-- New-module tables
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'special_dates','family_photos','milestones','saved_places',
    'user_locations','health_records','messages'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "%s_all" ON %I FOR ALL USING (auth_is_member_of(family_id)) WITH CHECK (auth_is_member_of(family_id))', t, t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Personal tables (no family_id scope) — each user sees only their own rows
-- ---------------------------------------------------------------------------
ALTER TABLE fitness ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fitness_all" ON fitness FOR ALL
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

ALTER TABLE fitness_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fitness_plans_all" ON fitness_plans FOR ALL
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

ALTER TABLE fitness_logs ENABLE ROW LEVEL SECURITY;
-- Family members can READ all logs for their family.
CREATE POLICY "fitness_logs_select_family" ON fitness_logs FOR SELECT
  USING (auth_is_member_of(family_id));

-- Only the owner can INSERT/UPDATE/DELETE their own logs.
CREATE POLICY "fitness_logs_insert_own" ON fitness_logs FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "fitness_logs_update_own" ON fitness_logs FOR UPDATE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "fitness_logs_delete_own" ON fitness_logs FOR DELETE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

-- workout_sessions / workout_exercises / workout_sets — Strong integration
ALTER TABLE workout_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "workout_sessions_select_family" ON workout_sessions FOR SELECT
USING (auth_is_member_of(family_id));
CREATE POLICY "workout_sessions_insert_own" ON workout_sessions FOR INSERT
WITH CHECK (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);
CREATE POLICY "workout_sessions_update_own" ON workout_sessions FOR UPDATE
USING (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
)
WITH CHECK (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);
CREATE POLICY "workout_sessions_delete_own" ON workout_sessions FOR DELETE
USING (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);

ALTER TABLE workout_exercises ENABLE ROW LEVEL SECURITY;
CREATE POLICY "workout_exercises_select_family" ON workout_exercises FOR SELECT
USING (auth_is_member_of(family_id));
CREATE POLICY "workout_exercises_insert_own" ON workout_exercises FOR INSERT
WITH CHECK (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);
CREATE POLICY "workout_exercises_update_own" ON workout_exercises FOR UPDATE
USING (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
)
WITH CHECK (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);
CREATE POLICY "workout_exercises_delete_own" ON workout_exercises FOR DELETE
USING (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);

ALTER TABLE workout_sets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "workout_sets_select_family" ON workout_sets FOR SELECT
USING (auth_is_member_of(family_id));
CREATE POLICY "workout_sets_insert_own" ON workout_sets FOR INSERT
WITH CHECK (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);
CREATE POLICY "workout_sets_update_own" ON workout_sets FOR UPDATE
USING (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
)
WITH CHECK (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);
CREATE POLICY "workout_sets_delete_own" ON workout_sets FOR DELETE
USING (
  user_id = auth.uid()::text
  AND auth_is_member_of(family_id)
);

ALTER TABLE daily_habits ENABLE ROW LEVEL SECURITY;
CREATE POLICY "daily_habits_all" ON daily_habits FOR ALL
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

ALTER TABLE daily_habit_completions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "daily_habit_completions_all" ON daily_habit_completions FOR ALL
  USING (
    user_id = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM daily_habits dh
      WHERE dh.id = daily_habit_completions.habit_id
        AND dh.user_id = auth.uid()::text
    )
  )
  WITH CHECK (
    user_id = auth.uid()::text
  );

-- period_cycles — users manage only their own rows
ALTER TABLE period_cycles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "period_cycles_all" ON period_cycles FOR ALL
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

-- period_symptoms — users manage only their own rows
ALTER TABLE period_symptoms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "period_symptoms_all" ON period_symptoms FOR ALL
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

-- device_tokens — users manage only their own tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own tokens" ON device_tokens FOR ALL
  USING  (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- web_push_subscriptions — users manage only their own subscriptions
ALTER TABLE web_push_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own web push subscriptions" ON web_push_subscriptions FOR ALL
  USING  (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);


-- =============================================================================
-- PERMISSIONS
-- =============================================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon;

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
