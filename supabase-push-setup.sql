-- =============================================================================
-- Push Notification Setup
-- Run this in the Supabase SQL editor.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. device_tokens table
--    Stores one row per user per platform (ios/android).
--    Supabase Database Webhooks call notify-family when family data changes.
-- ---------------------------------------------------------------------------
create table if not exists device_tokens (
  id          uuid primary key default gen_random_uuid(),
  "userId"    text not null,
  "familyId"  text not null,
  token       text not null,
  platform    text not null check (platform in ('ios', 'android')),
  "updatedAt" timestamptz not null default now(),
  -- One token row per user per platform
  unique ("userId", platform)
);

-- Index for fast look-up of all tokens for a given family
create index if not exists device_tokens_family_idx on device_tokens ("familyId");

-- ---------------------------------------------------------------------------
-- 2. Row Level Security
-- ---------------------------------------------------------------------------
alter table device_tokens enable row level security;

-- Users may only see/manage their own tokens
create policy "Users manage own tokens"
  on device_tokens
  for all
  using  (auth.uid()::text = "userId")
  with check (auth.uid()::text = "userId");

-- Edge Functions (service role) can read all tokens to deliver notifications
-- (Service role bypasses RLS automatically — no extra policy needed.)

-- ---------------------------------------------------------------------------
-- 3. Database Webhooks
--    These call the notify-family Edge Function when rows change.
--    Create them in the Supabase Dashboard → Database → Webhooks, or paste
--    the SQL below to create them programmatically (requires pg_net extension).
-- ---------------------------------------------------------------------------

-- Enable the HTTP extension if not already enabled:
-- create extension if not exists pg_net with schema extensions;

-- Helper: replace <PROJECT_REF> with your Supabase project ref (e.g. abcdefghij).
-- The service role key header is required so the Edge Function can call Supabase.

/*

-- tasks: INSERT
select supabase_functions.http_request(
  'https://<PROJECT_REF>.supabase.co/functions/v1/notify-family',
  'POST',
  '{"Content-Type":"application/json","Authorization":"Bearer <SERVICE_ROLE_KEY>"}',
  '{}',  -- body is provided by the trigger automatically
  '5000'
);

-- NOTE: The easiest way is to create these through the Dashboard:
--
--   Dashboard → Database → Webhooks → Create webhook
--
--   Name:        notify-family-tasks-insert
--   Table:       tasks
--   Events:      INSERT
--   Type:        Supabase Edge Function
--   Function:    notify-family
--
-- Repeat for:
--   tasks        UPDATE  (to catch task completions)
--   events       INSERT
--   chores       INSERT
--   chore_completions  INSERT
--   lists        INSERT
--   polls        INSERT

*/

-- ---------------------------------------------------------------------------
-- 4. Verification queries
-- ---------------------------------------------------------------------------
-- select * from device_tokens limit 10;
-- select count(*) from device_tokens;
