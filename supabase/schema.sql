-- Run this in Supabase SQL editor before using cloud sync from the web app.
-- If migrating from a previous version, see the ALTER TABLE statements at the bottom.

create table if not exists users (
  id text primary key,
  name text not null,
  email text not null unique,
  password text,
  avatar text
);

create table if not exists families (
  id text primary key,
  name text not null,
  owner_id text not null,
  join_code text not null unique
);

create table if not exists family_members (
  user_id text not null,
  family_id text not null,
  role text not null,
  module_access jsonb,
  display_name text,
  primary key (user_id, family_id)
);

create table if not exists tasks (
  id text primary key,
  family_id text not null,
  creator_id text not null,
  title text not null,
  notes text,
  due_date text not null,
  due_time text,
  reminder_minutes integer,
  priority text not null,
  completed boolean not null default false,
  completed_by text,
  updated_by text,
  visibility text not null default 'FAMILY',
  assignees jsonb not null default '[]'::jsonb,
  tags jsonb not null default '[]'::jsonb,
  recurrence text default 'NONE'
);

create table if not exists events (
  id text primary key,
  family_id text not null,
  creator_id text not null default '',
  title text not null,
  description text,
  location text,
  start text not null,
  "end" text not null,
  visibility text not null default 'FAMILY',
  shared_with jsonb not null default '[]'::jsonb,
  checklist jsonb not null default '[]'::jsonb,
  budget_estimate numeric,
  recurrence text default 'NONE'
);

create table if not exists recipes (
  id text primary key,
  family_id text not null,
  title text not null,
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  servings integer not null,
  tags jsonb not null default '[]'::jsonb,
  image text
);

create table if not exists meal_plans (
  id text primary key,
  family_id text not null,
  date text not null,
  meal_type text not null,
  recipe_id text,
  custom_meal text
);

create table if not exists lists (
  id text primary key,
  family_id text not null,
  creator_id text not null default '',
  title text not null,
  items jsonb not null default '[]'::jsonb,
  category text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists devotionals (
  id text primary key,
  family_id text not null default '',
  creator_id text not null default '',
  title text not null,
  scripture text not null,
  content text not null,
  reflection_prompts jsonb not null default '[]'::jsonb,
  prayer text,
  tags jsonb not null default '[]'::jsonb,
  date text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists fitness (
  id text primary key,
  user_id text not null,
  type text not null,
  value numeric not null,
  date text not null,
  notes text
);

create table if not exists budget_categories (
  id text primary key,
  family_id text not null,
  creator_id text not null default '',
  name text not null,
  "limit" numeric not null,
  color text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists transactions (
  id text primary key,
  family_id text not null,
  creator_id text not null default '',
  category_id text not null,
  amount numeric not null,
  type text not null,
  date text not null,
  description text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists ai_history (
  id text primary key,
  user_id text not null,
  family_id text not null,
  module text not null,
  prompt text not null,
  response text not null,
  created_at text not null
);

create table if not exists daily_habits (
  id text primary key,
  user_id text not null,
  family_id text,
  label text not null,
  icon text not null default '',
  color text not null default '#6366f1',
  description text,
  is_shared boolean not null default false,
  frequency text,
  target_value numeric,
  target_unit text,
  created_at text not null,
  "order" integer not null default 0
);

create table if not exists daily_habit_completions (
  id text primary key,
  habit_id text not null,
  user_id text not null,
  date text not null,
  completed_at text not null
);

create table if not exists chores (
  id text primary key,
  family_id text not null,
  creator_id text not null,
  title text not null,
  description text,
  icon text not null default '🧹',
  points integer not null default 10,
  reward numeric,
  frequency text not null default 'DAILY',
  days_of_week jsonb not null default '[]'::jsonb,
  assignees jsonb not null default '[]'::jsonb,
  color text not null default '#6366f1',
  visibility text not null default 'FAMILY',
  created_at text not null
);

create table if not exists chore_completions (
  id text primary key,
  chore_id text not null,
  user_id text not null,
  family_id text not null,
  date text not null,
  completed_at text not null
);

create table if not exists polls (
  id text primary key,
  family_id text not null,
  creator_id text not null,
  question text not null,
  options jsonb not null default '[]'::jsonb,
  allow_multiple boolean not null default false,
  anonymous boolean not null default false,
  status text not null default 'OPEN',
  deadline text,
  visibility text not null default 'FAMILY',
  created_at text not null
);

create table if not exists poll_votes (
  id text primary key,
  poll_id text not null,
  option_id text not null,
  user_id text not null,
  family_id text not null,
  voted_at text not null
);

create table if not exists external_calendars (
  id text primary key,
  family_id text not null,
  creator_id text not null,
  name text not null,
  url text,
  color text not null default '#6366f1',
  type text not null default 'OTHER',
  enabled boolean not null default true,
  last_synced text,
  created_at text not null
);

-- Migrate events table to support external calendar fields (safe to run multiple times)
alter table events add column if not exists external_calendar_id text;
alter table events add column if not exists external_uid text;

-- Migrate tasks and events to support recurrence (safe to run multiple times)
alter table tasks add column if not exists recurrence text default 'NONE';
alter table events add column if not exists recurrence text default 'NONE';

-- Tables added after initial deployment (safe to run on existing schemas)
create table if not exists fitness_plans (
  id           text primary key,
  user_id      text not null,
  summary      text not null,
  weekly_plan  jsonb not null default '[]'::jsonb,
  tips         jsonb not null default '[]'::jsonb,
  profile      jsonb not null default '{}'::jsonb,
  created_at   text not null
);

create table if not exists reward_items (
  id          text primary key,
  family_id   text not null,
  creator_id  text not null,
  title       text not null,
  description text,
  cost        numeric not null,
  icon        text not null,
  active      boolean not null default true,
  created_at  text not null
);

create table if not exists rewards (
  id            text primary key,
  family_id     text not null,
  title         text not null,
  point_cost    int not null default 0,
  description   text,
  redeemed_by   jsonb not null default '[]'::jsonb
);

create table if not exists reward_redemptions (
  id            text primary key,
  family_id     text not null,
  user_id       text not null,
  reward_id     text,
  reward_title  text not null,
  amount        numeric not null,
  status        text not null default 'PENDING',
  requested_at  text not null,
  resolved_at   text,
  resolved_by   text
);

create table if not exists savings_goals (
  id             text primary key,
  family_id      text not null,
  user_id        text not null,
  title          text not null,
  icon           text not null,
  image_url      text,
  target_amount  numeric not null,
  saved_amount   numeric not null default 0,
  created_at     text not null,
  completed_at   text
);

create table if not exists prayer_wall (
  id                  text primary key,
  family_id           text not null,
  creator_id          text not null,
  type                text not null,
  text                text not null,
  original_request_id text,
  reactions           jsonb not null default '[]'::jsonb,
  prayed_by_ids       jsonb not null default '[]'::jsonb,
  date                text not null,
  answered_at         text,
  visibility          text not null default 'FAMILY'
);

create table if not exists reading_plans (
  id          text primary key,
  family_id   text not null,
  creator_id  text not null,
  title       text not null,
  description text not null,
  total_days  integer not null,
  days        jsonb not null default '[]'::jsonb,
  created_at  text not null
);

create table if not exists reading_plan_progress (
  id                text primary key,
  plan_id           text not null,
  user_id           text not null,
  family_id         text not null,
  completed_days    jsonb not null default '[]'::jsonb,
  current_streak    integer not null default 0,
  longest_streak    integer not null default 0,
  started_at        text not null,
  last_completed_at text
);

-- Enable RLS with permissive policies for anon/authenticated roles.
do $$
declare
  t text;
begin
  foreach t in array array[
    'users','families','family_members','tasks','events','recipes','meal_plans',
    'lists','devotionals','fitness','fitness_plans','budget_categories','transactions','ai_history',
    'daily_habits','daily_habit_completions','chores','chore_completions','polls','poll_votes',
    'external_calendars','rewards','reward_items','reward_redemptions','savings_goals',
    'prayer_wall','reading_plans','reading_plan_progress'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    -- Drop old overly-permissive anon policy
    execute format('drop policy if exists "%s_rw_anon" on %I', t, t);
    -- Authenticated users: full access (app enforces family-scoping client-side)
    execute format('drop policy if exists "%s_rw_auth" on %I', t, t);
    execute format('create policy "%s_rw_auth" on %I for all to authenticated using (true) with check (true)', t, t);
    -- Anon users: read-only (needed for join-by-code lookup before sign-in)
    execute format('drop policy if exists "%s_ro_anon" on %I', t, t);
    execute format('create policy "%s_ro_anon" on %I for select to anon using (true)', t, t);
  end loop;
end $$;

-- ============================================================
-- Migration helpers: run these if upgrading from a previous schema.
-- They are safe to re-run (IF NOT EXISTS / column checks).
-- ============================================================
do $$
begin
  -- events
  if not exists (select 1 from information_schema.columns where table_name='events' and column_name='creator_id') then
    alter table events add column creator_id text not null default '';
  end if;
  -- lists
  if not exists (select 1 from information_schema.columns where table_name='lists' and column_name='creator_id') then
    alter table lists add column creator_id text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='lists' and column_name='visibility') then
    alter table lists add column visibility text not null default 'FAMILY';
  end if;
  -- devotionals
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='family_id') then
    alter table devotionals add column family_id text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='creator_id') then
    alter table devotionals add column creator_id text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='visibility') then
    alter table devotionals add column visibility text not null default 'FAMILY';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='prayer') then
    alter table devotionals add column prayer text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='user_prayer') then
    alter table devotionals add column user_prayer text;
  end if;
  -- budget_categories
  if not exists (select 1 from information_schema.columns where table_name='budget_categories' and column_name='creator_id') then
    alter table budget_categories add column creator_id text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='budget_categories' and column_name='visibility') then
    alter table budget_categories add column visibility text not null default 'FAMILY';
  end if;
  -- transactions
  if not exists (select 1 from information_schema.columns where table_name='transactions' and column_name='creator_id') then
    alter table transactions add column creator_id text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='transactions' and column_name='visibility') then
    alter table transactions add column visibility text not null default 'FAMILY';
  end if;
end $$;

-- families: add columns that the Family model requires but were not in the
-- original minimal CREATE TABLE (safe to re-run).
alter table families add column if not exists announcement text;
alter table families add column if not exists announcement_author text;
alter table families add column if not exists subscription_tier text;
alter table families add column if not exists enabled_modules jsonb not null default '[]'::jsonb;
alter table families add column if not exists created_at text;
alter table families add column if not exists welcome_dismissed boolean not null default false;
alter table families add column if not exists settings jsonb;

-- family_members: ensure columns added after initial create exist.
alter table family_members add column if not exists module_access jsonb;
alter table family_members add column if not exists display_name text;

-- =============================================================================
-- Push Notification device tokens
-- =============================================================================
create table if not exists device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     text not null,
  family_id   text not null,
  token       text not null,
  platform    text not null check (platform in ('ios', 'android')),
  updated_at  timestamptz not null default now(),
  unique (user_id, platform)
);

create index if not exists device_tokens_family_idx on device_tokens (family_id);

-- Weekly digest opt-out flag and schedule on families
alter table families add column if not exists weekly_digest boolean;
-- UTC day-of-week (0=Sun … 6=Sat) and hour (0–23); NULL = defaults (Sunday 08:00 UTC)
alter table families add column if not exists weekly_digest_day smallint;
alter table families add column if not exists weekly_digest_hour smallint;

alter table device_tokens enable row level security;

create policy "Users manage own tokens"
  on device_tokens
  for all
  using  (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);

-- =============================================================================
-- New modules: Birthdays, Photos, Location (added with competitive feature set)
-- =============================================================================

create table if not exists special_dates (
  id              text primary key,
  family_id       text not null,
  creator_id      text not null,
  name            text not null,
  type            text not null check (type in ('BIRTHDAY','ANNIVERSARY','MEMORIAL','OTHER')),
  month           smallint not null,
  day             smallint not null,
  year            smallint,
  emoji           text not null,
  notes           text,
  reminder_days   jsonb not null default '[]'::jsonb,
  visibility      text not null default 'FAMILY',
  created_at      text not null
);

create table if not exists family_photos (
  id            text primary key,
  family_id     text not null,
  uploader_id   text not null,
  url           text not null,
  caption       text,
  taken_at      text not null,
  created_at    text not null,
  reactions     jsonb not null default '[]'::jsonb,
  milestone_id  text,
  tags          jsonb not null default '[]'::jsonb,
  visibility    text not null default 'FAMILY'
);

create table if not exists milestones (
  id          text primary key,
  family_id   text not null,
  child_id    text not null,
  title       text not null,
  emoji       text not null,
  category    text not null,
  date        text not null,
  notes       text,
  photo_ids   jsonb not null default '[]'::jsonb,
  age_label   text,
  created_at  text not null
);

create table if not exists saved_places (
  id              text primary key,
  family_id       text not null,
  creator_id      text not null,
  name            text not null,
  emoji           text not null,
  latitude        numeric not null,
  longitude       numeric not null,
  radius_metres   numeric not null default 200,
  created_at      text not null
);

create table if not exists user_locations (
  id           text primary key,
  family_id    text not null,
  user_id      text not null,
  latitude     numeric not null,
  longitude    numeric not null,
  accuracy     numeric,
  place_name   text,
  near_place   text,
  is_sharing   boolean not null default false,
  updated_at   text not null
);

create table if not exists health_records (
  id                      text primary key,
  family_id               text not null,
  member_id               text not null,
  updated_by              text not null,
  blood_type              text not null default 'Unknown',
  allergies               jsonb not null default '[]'::jsonb,
  medications             jsonb not null default '[]'::jsonb,
  conditions              jsonb not null default '[]'::jsonb,
  immunizations           jsonb not null default '[]'::jsonb,
  emergency_contacts      jsonb not null default '[]'::jsonb,
  doctor_name             text,
  doctor_phone            text,
  insurance_provider      text,
  insurance_policy_number text,
  notes                   text,
  updated_at              text not null,
  unique (family_id, member_id)
);

-- Add approval fields to chore_completions (safe to run multiple times)
alter table chore_completions add column if not exists approval_status text;
alter table chore_completions add column if not exists approved_by text;
alter table chore_completions add column if not exists approved_at text;

-- Add requiresApproval to chores (safe to run multiple times)
alter table chores add column if not exists requires_approval boolean;

create index if not exists health_records_family_idx on health_records (family_id);

-- =============================================================================
-- Family Chat Messages
-- Full message history persisted in Supabase; local state is capped at 500.
-- =============================================================================
create table if not exists messages (
  id           text primary key,
  family_id    text not null,
  user_id      text not null,
  text         text not null,
  reply_to_id  text,
  reactions    jsonb not null default '{}'::jsonb,
  edited_at    text,
  created_at   text not null
);

create index if not exists messages_family_idx on messages (family_id);

create index if not exists special_dates_family_idx    on special_dates (family_id);
create index if not exists family_photos_family_idx    on family_photos (family_id);
create index if not exists milestones_family_idx       on milestones (family_id);
create index if not exists saved_places_family_idx     on saved_places (family_id);
create index if not exists user_locations_family_idx   on user_locations (family_id);

-- Enable RLS for new tables
do $$
declare
  t text;
begin
  foreach t in array array[
    'special_dates','family_photos','milestones','saved_places','user_locations','health_records','messages'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    -- Drop old overly-permissive anon policy
    execute format('drop policy if exists "%s_rw_anon" on %I', t, t);
    -- Authenticated users: full access (app enforces family-scoping client-side)
    execute format('drop policy if exists "%s_rw_auth" on %I', t, t);
    execute format('create policy "%s_rw_auth" on %I for all to authenticated using (true) with check (true)', t, t);
    -- Anon users: read-only (needed for join-by-code lookup before sign-in)
    execute format('drop policy if exists "%s_ro_anon" on %I', t, t);
    execute format('create policy "%s_ro_anon" on %I for select to anon using (true)', t, t);
  end loop;
end $$;

-- =============================================================================
-- Web Push Subscriptions (VAPID / PWA)
-- Stores browser PushSubscription data so the notify-family Edge Function
-- can deliver server-sent push notifications to PWA / browser users.
-- Requires VAPID keys: generate with `npx web-push generate-vapid-keys`
--   Set VITE_VAPID_PUBLIC_KEY in .env and VAPID_PRIVATE_KEY as a Supabase secret.
-- =============================================================================
create table if not exists web_push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     text not null,
  family_id   text not null,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  updated_at  timestamptz not null default now()
);

create index if not exists web_push_family_idx on web_push_subscriptions (family_id);

alter table web_push_subscriptions enable row level security;

create policy "Users manage own web push subscriptions"
  on web_push_subscriptions
  for all
  using  (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);

-- =============================================================================
-- Period Cycles
-- =============================================================================
create table if not exists period_cycles (
  id          text primary key,
  user_id     text not null,
  family_id   text not null,
  start_date  timestamptz not null,
  end_date    timestamptz,
  flow_level  text not null default 'MEDIUM',
  notes       text,
  created_at  timestamptz not null default now()
);

create index if not exists period_cycles_user_idx on period_cycles (user_id);
create index if not exists period_cycles_family_idx on period_cycles (family_id);

alter table period_cycles enable row level security;

create policy "Users manage own period cycles"
  on period_cycles
  for all
  using  (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);

-- =============================================================================
-- Period Symptoms
-- =============================================================================
create table if not exists period_symptoms (
  id          text primary key,
  user_id     text not null,
  family_id   text not null,
  date        timestamptz not null,
  symptoms    jsonb not null default '[]'::jsonb,
  mood        text,
  pain_level  int,
  notes       text,
  created_at  timestamptz not null default now()
);

create index if not exists period_symptoms_user_idx on period_symptoms (user_id);
create index if not exists period_symptoms_family_idx on period_symptoms (family_id);

alter table period_symptoms enable row level security;

create policy "Users manage own period symptoms"
  on period_symptoms
  for all
  using  (auth.uid()::text = user_id)
  with check (auth.uid()::text = user_id);

-- =============================================================================
-- Daily Devotional scheduling columns on families
-- =============================================================================
alter table families add column if not exists daily_devotional_enabled boolean not null default false;
alter table families add column if not exists daily_devotional_hour smallint not null default 7;
alter table families add column if not exists daily_devotional_minute smallint not null default 0;

-- Devotional favorites (per-entry, local-first but synced)
alter table devotionals add column if not exists is_favorited boolean not null default false;

-- =============================================================================
-- Enable Postgres Realtime on all family-scoped tables so the Flutter app
-- receives change events in real time (inserts from edge functions/cron,
-- updates from other family members, etc.)
-- =============================================================================
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE tasks;              EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE events;             EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE recipes;            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE meal_plans;         EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE lists;              EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE devotionals;        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE budget_categories;  EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE transactions;       EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE chores;             EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE chore_completions;  EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE polls;              EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE poll_votes;         EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE reward_items;       EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE reward_redemptions; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE savings_goals;      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE prayer_wall;        EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE special_dates;      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE family_photos;      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE milestones;         EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE saved_places;       EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE messages;           EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE health_records;     EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE reading_plans;      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE rewards;            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
