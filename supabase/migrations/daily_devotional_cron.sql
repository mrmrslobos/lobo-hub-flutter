-- ============================================================
-- Daily Devotional — Supabase Cron schedule
--
-- Run this SQL ONCE in your Supabase project's SQL editor
-- (Database → SQL Editor) to register the pg_cron job that
-- triggers the daily-devotional edge function every 15 minutes.
--
-- Prerequisites:
--   1. pg_cron and pg_net extensions must be enabled in your
--      project (Database → Extensions).
--   2. The daily-devotional edge function must be deployed:
--        supabase functions deploy daily-devotional
--   3. Replace the two <placeholder> values below with your
--      actual Supabase project ref and service role key
--      (Settings → API in the Supabase dashboard).
-- ============================================================

-- Enable required extensions (safe to run if already enabled)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove any previous schedule with the same name before re-adding
select cron.unschedule('daily-family-devotional')
  where exists (
    select 1 from cron.job where jobname = 'daily-family-devotional'
  );

-- Schedule: every 15 minutes
-- The edge function itself checks each family's stored UTC hour + minute
-- and only generates when they fall in the current 15-minute window.
select cron.schedule(
  'daily-family-devotional',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := 'https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/daily-devotional',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <YOUR_SERVICE_ROLE_KEY>'
    ),
    body    := '{}'::jsonb
  ) as request_id;
  $$
);

-- Verify the job was registered
select jobname, schedule, command
from cron.job
where jobname = 'daily-family-devotional';
