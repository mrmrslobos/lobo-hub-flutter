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
  "ownerId" text not null,
  "joinCode" text not null unique
);

create table if not exists family_members (
  "userId" text not null,
  "familyId" text not null,
  role text not null,
  "moduleAccess" jsonb,
  primary key ("userId", "familyId")
);

create table if not exists tasks (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null,
  title text not null,
  notes text,
  "dueDate" text not null,
  priority text not null,
  completed boolean not null default false,
  visibility text not null default 'FAMILY',
  assignees jsonb not null default '[]'::jsonb,
  tags jsonb not null default '[]'::jsonb,
  recurrence text default 'NONE'
);

create table if not exists events (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null default '',
  title text not null,
  description text,
  location text,
  start text not null,
  "end" text not null,
  visibility text not null default 'FAMILY',
  checklist jsonb not null default '[]'::jsonb,
  "budgetEstimate" numeric,
  recurrence text default 'NONE'
);

create table if not exists recipes (
  id text primary key,
  "familyId" text not null,
  title text not null,
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  servings integer not null,
  tags jsonb not null default '[]'::jsonb,
  image text
);

create table if not exists meal_plans (
  id text primary key,
  "familyId" text not null,
  date text not null,
  "mealType" text not null,
  "recipeId" text,
  "customMeal" text
);

create table if not exists lists (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null default '',
  title text not null,
  items jsonb not null default '[]'::jsonb,
  category text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists devotionals (
  id text primary key,
  "familyId" text not null default '',
  "creatorId" text not null default '',
  title text not null,
  scripture text not null,
  content text not null,
  "reflectionPrompts" jsonb not null default '[]'::jsonb,
  prayer text,
  tags jsonb not null default '[]'::jsonb,
  date text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists fitness (
  id text primary key,
  "userId" text not null,
  type text not null,
  value numeric not null,
  date text not null,
  notes text
);

create table if not exists budget_categories (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null default '',
  name text not null,
  "limit" numeric not null,
  color text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists transactions (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null default '',
  "categoryId" text not null,
  amount numeric not null,
  type text not null,
  date text not null,
  description text not null,
  visibility text not null default 'FAMILY'
);

create table if not exists ai_history (
  id text primary key,
  "userId" text not null,
  "familyId" text not null,
  module text not null,
  prompt text not null,
  response text not null,
  "createdAt" text not null
);

create table if not exists daily_habits (
  id text primary key,
  "userId" text not null,
  label text not null,
  icon text not null,
  color text not null,
  "createdAt" text not null,
  "order" integer not null
);

create table if not exists daily_habit_completions (
  id text primary key,
  "habitId" text not null,
  "userId" text not null,
  date text not null,
  "completedAt" text not null
);

create table if not exists chores (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null,
  title text not null,
  description text,
  icon text not null default '🧹',
  points integer not null default 10,
  frequency text not null default 'DAILY',
  "daysOfWeek" jsonb not null default '[]'::jsonb,
  assignees jsonb not null default '[]'::jsonb,
  color text not null default '#6366f1',
  visibility text not null default 'FAMILY',
  "createdAt" text not null
);

create table if not exists chore_completions (
  id text primary key,
  "choreId" text not null,
  "userId" text not null,
  "familyId" text not null,
  date text not null,
  "completedAt" text not null
);

create table if not exists polls (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null,
  question text not null,
  options jsonb not null default '[]'::jsonb,
  "allowMultiple" boolean not null default false,
  anonymous boolean not null default false,
  status text not null default 'OPEN',
  deadline text,
  visibility text not null default 'FAMILY',
  "createdAt" text not null
);

create table if not exists poll_votes (
  id text primary key,
  "pollId" text not null,
  "optionId" text not null,
  "userId" text not null,
  "familyId" text not null,
  "votedAt" text not null
);

create table if not exists external_calendars (
  id text primary key,
  "familyId" text not null,
  "creatorId" text not null,
  name text not null,
  url text,
  color text not null default '#6366f1',
  type text not null default 'OTHER',
  enabled boolean not null default true,
  "lastSynced" text,
  "createdAt" text not null
);

-- Migrate events table to support external calendar fields (safe to run multiple times)
alter table events add column if not exists "externalCalendarId" text;
alter table events add column if not exists "externalUid" text;

-- Migrate tasks and events to support recurrence (safe to run multiple times)
alter table tasks add column if not exists recurrence text default 'NONE';
alter table events add column if not exists recurrence text default 'NONE';

-- Tables added after initial deployment (safe to run on existing schemas)
create table if not exists fitness_plans (
  id           text primary key,
  "userId"     text not null,
  summary      text not null,
  "weeklyPlan" jsonb not null default '[]'::jsonb,
  tips         jsonb not null default '[]'::jsonb,
  profile      jsonb not null default '{}'::jsonb,
  "createdAt"  text not null
);

create table if not exists reward_items (
  id          text primary key,
  "familyId"  text not null,
  "creatorId" text not null,
  title       text not null,
  description text,
  cost        numeric not null,
  icon        text not null,
  active      boolean not null default true,
  "createdAt" text not null
);

create table if not exists reward_redemptions (
  id            text primary key,
  "familyId"    text not null,
  "userId"      text not null,
  "rewardId"    text,
  "rewardTitle" text not null,
  amount        numeric not null,
  status        text not null default 'PENDING',
  "requestedAt" text not null,
  "resolvedAt"  text,
  "resolvedBy"  text
);

create table if not exists savings_goals (
  id             text primary key,
  "familyId"     text not null,
  "userId"       text not null,
  title          text not null,
  icon           text not null,
  "imageUrl"     text,
  "targetAmount" numeric not null,
  "savedAmount"  numeric not null default 0,
  "createdAt"    text not null,
  "completedAt"  text
);

create table if not exists prayer_wall (
  id                  text primary key,
  "familyId"          text not null,
  "creatorId"         text not null,
  type                text not null,
  text                text not null,
  "originalRequestId" text,
  reactions           jsonb not null default '[]'::jsonb,
  date                text not null,
  "answeredAt"        text,
  visibility          text not null default 'FAMILY'
);

create table if not exists reading_plans (
  id          text primary key,
  "familyId"  text not null,
  "creatorId" text not null,
  title       text not null,
  description text not null,
  "totalDays" integer not null,
  days        jsonb not null default '[]'::jsonb,
  "createdAt" text not null
);

create table if not exists reading_plan_progress (
  id                text primary key,
  "planId"          text not null,
  "userId"          text not null,
  "familyId"        text not null,
  "completedDays"   jsonb not null default '[]'::jsonb,
  "currentStreak"   integer not null default 0,
  "longestStreak"   integer not null default 0,
  "startedAt"       text not null,
  "lastCompletedAt" text
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
    'external_calendars','reward_items','reward_redemptions','savings_goals',
    'prayer_wall','reading_plans','reading_plan_progress'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "%s_rw_anon" on %I', t, t);
    execute format('create policy "%s_rw_anon" on %I for all to anon, authenticated using (true) with check (true)', t, t);
  end loop;
end $$;

-- ============================================================
-- Migration helpers: run these if upgrading from a previous schema.
-- They are safe to re-run (IF NOT EXISTS / column checks).
-- ============================================================
do $$
begin
  -- events
  if not exists (select 1 from information_schema.columns where table_name='events' and column_name='creatorId') then
    alter table events add column "creatorId" text not null default '';
  end if;
  -- lists
  if not exists (select 1 from information_schema.columns where table_name='lists' and column_name='creatorId') then
    alter table lists add column "creatorId" text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='lists' and column_name='visibility') then
    alter table lists add column visibility text not null default 'FAMILY';
  end if;
  -- devotionals
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='familyId') then
    alter table devotionals add column "familyId" text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='creatorId') then
    alter table devotionals add column "creatorId" text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='visibility') then
    alter table devotionals add column visibility text not null default 'FAMILY';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='devotionals' and column_name='prayer') then
    alter table devotionals add column prayer text;
  end if;
  -- budget_categories
  if not exists (select 1 from information_schema.columns where table_name='budget_categories' and column_name='creatorId') then
    alter table budget_categories add column "creatorId" text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='budget_categories' and column_name='visibility') then
    alter table budget_categories add column visibility text not null default 'FAMILY';
  end if;
  -- transactions
  if not exists (select 1 from information_schema.columns where table_name='transactions' and column_name='creatorId') then
    alter table transactions add column "creatorId" text not null default '';
  end if;
  if not exists (select 1 from information_schema.columns where table_name='transactions' and column_name='visibility') then
    alter table transactions add column visibility text not null default 'FAMILY';
  end if;
end $$;

-- =============================================================================
-- Push Notification device tokens
-- =============================================================================
create table if not exists device_tokens (
  id          uuid primary key default gen_random_uuid(),
  "userId"    text not null,
  "familyId"  text not null,
  token       text not null,
  platform    text not null check (platform in ('ios', 'android')),
  "updatedAt" timestamptz not null default now(),
  unique ("userId", platform)
);

create index if not exists device_tokens_family_idx on device_tokens ("familyId");

-- Weekly digest opt-out flag and schedule on families
alter table families add column if not exists "weeklyDigest" boolean;
-- UTC day-of-week (0=Sun … 6=Sat) and hour (0–23); NULL = defaults (Sunday 08:00 UTC)
alter table families add column if not exists "weeklyDigestDay" smallint;
alter table families add column if not exists "weeklyDigestHour" smallint;

alter table device_tokens enable row level security;

create policy "Users manage own tokens"
  on device_tokens
  for all
  using  (auth.uid()::text = "userId")
  with check (auth.uid()::text = "userId");

-- =============================================================================
-- New modules: Birthdays, Photos, Location (added with competitive feature set)
-- =============================================================================

create table if not exists special_dates (
  id              text primary key,
  "familyId"      text not null,
  "creatorId"     text not null,
  name            text not null,
  type            text not null check (type in ('BIRTHDAY','ANNIVERSARY','MEMORIAL','OTHER')),
  month           smallint not null,
  day             smallint not null,
  year            smallint,
  emoji           text not null,
  notes           text,
  "reminderDays"  jsonb not null default '[]'::jsonb,
  visibility      text not null default 'FAMILY',
  "createdAt"     text not null
);

create table if not exists family_photos (
  id            text primary key,
  "familyId"    text not null,
  "uploaderId"  text not null,
  url           text not null,
  caption       text,
  "takenAt"     text not null,
  "createdAt"   text not null,
  reactions     jsonb not null default '[]'::jsonb,
  "milestoneId" text,
  tags          jsonb not null default '[]'::jsonb,
  visibility    text not null default 'FAMILY'
);

create table if not exists milestones (
  id          text primary key,
  "familyId"  text not null,
  "childId"   text not null,
  title       text not null,
  emoji       text not null,
  category    text not null,
  date        text not null,
  notes       text,
  "photoIds"  jsonb not null default '[]'::jsonb,
  "ageLabel"  text,
  "createdAt" text not null
);

create table if not exists saved_places (
  id              text primary key,
  "familyId"      text not null,
  "creatorId"     text not null,
  name            text not null,
  emoji           text not null,
  latitude        numeric not null,
  longitude       numeric not null,
  "radiusMetres"  numeric not null default 200,
  "createdAt"     text not null
);

create table if not exists user_locations (
  id           text primary key,
  "familyId"   text not null,
  "userId"     text not null,
  latitude     numeric not null,
  longitude    numeric not null,
  accuracy     numeric,
  "placeName"  text,
  "nearPlace"  text,
  "isSharing"  boolean not null default false,
  "updatedAt"  text not null
);

create table if not exists health_records (
  id                      text primary key,
  "familyId"              text not null,
  "memberId"              text not null,
  "updatedBy"             text not null,
  "bloodType"             text not null default 'Unknown',
  allergies               jsonb not null default '[]'::jsonb,
  medications             jsonb not null default '[]'::jsonb,
  conditions              jsonb not null default '[]'::jsonb,
  immunizations           jsonb not null default '[]'::jsonb,
  "emergencyContacts"     jsonb not null default '[]'::jsonb,
  "doctorName"            text,
  "doctorPhone"           text,
  "insuranceProvider"     text,
  "insurancePolicyNumber" text,
  notes                   text,
  "updatedAt"             text not null,
  unique ("familyId", "memberId")
);

-- Add approval fields to chore_completions (safe to run multiple times)
alter table chore_completions add column if not exists "approvalStatus" text;
alter table chore_completions add column if not exists "approvedBy" text;
alter table chore_completions add column if not exists "approvedAt" text;

-- Add requiresApproval to chores (safe to run multiple times)
alter table chores add column if not exists "requiresApproval" boolean;

create index if not exists health_records_family_idx on health_records ("familyId");

-- =============================================================================
-- Family Chat Messages
-- Full message history persisted in Supabase; local state is capped at 500.
-- =============================================================================
create table if not exists messages (
  id           text primary key,
  "familyId"   text not null,
  "userId"     text not null,
  text         text not null,
  "replyToId"  text,
  reactions    jsonb not null default '{}'::jsonb,
  "editedAt"   text,
  "createdAt"  text not null
);

create index if not exists messages_family_idx on messages ("familyId");

create index if not exists special_dates_family_idx    on special_dates ("familyId");
create index if not exists family_photos_family_idx    on family_photos ("familyId");
create index if not exists milestones_family_idx       on milestones ("familyId");
create index if not exists saved_places_family_idx     on saved_places ("familyId");
create index if not exists user_locations_family_idx   on user_locations ("familyId");

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
    execute format('drop policy if exists "%s_rw_anon" on %I', t, t);
    execute format('create policy "%s_rw_anon" on %I for all to anon, authenticated using (true) with check (true)', t, t);
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
  "userId"    text not null,
  "familyId"  text not null,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  "updatedAt" timestamptz not null default now()
);

create index if not exists web_push_family_idx on web_push_subscriptions ("familyId");

alter table web_push_subscriptions enable row level security;

create policy "Users manage own web push subscriptions"
  on web_push_subscriptions
  for all
  using  (auth.uid()::text = "userId")
  with check (auth.uid()::text = "userId");
