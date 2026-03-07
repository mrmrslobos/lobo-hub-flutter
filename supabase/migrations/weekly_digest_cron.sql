-- ============================================================
-- Weekly Digest — Supabase Cron schedule
--
-- Run this SQL ONCE in your Supabase project's SQL editor
-- (Database → SQL Editor) to register the pg_cron job that
-- triggers the weekly-digest edge function every Sunday at
-- 08:00 UTC.
--
-- Prerequisites:
--   1. pg_cron and pg_net extensions must be enabled in your
--      project (Database → Extensions).
--   2. The weekly-digest edge function must be deployed:
--        supabase functions deploy weekly-digest
--   3. Replace the two <placeholder> values below with your
--      actual Supabase project ref and service role key
--      (Settings → API in the Supabase dashboard).
-- ============================================================

-- Enable required extensions (safe to run if already enabled)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove any previous schedule with the same name before re-adding
select cron.unschedule('weekly-family-digest')
  where exists (
    select 1 from cron.job where jobname = 'weekly-family-digest'
  );

-- Schedule: every hour on the hour
-- The edge function itself checks each family's stored UTC day + hour and
-- only sends when they match, so families fire at their chosen time.
select cron.schedule(
  'weekly-family-digest',
  '0 * * * *',
  $$
  select net.http_post(
    url     := 'https://.supabase.co/functions/v1/weekly-digest',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer     ),
    body    := '{}'::jsonb
  ) as request_id;
  $$
);

-- Verify the job was registered
select jobname, schedule, command
from cron.job
where jobname = 'weekly-family-digest';
