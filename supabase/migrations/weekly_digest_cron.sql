-- ============================================================
-- Weekly Digest — Supabase Cron (hourly → edge picks families)
-- ============================================================
-- Run in Supabase SQL Editor after replacing placeholders.
--
-- Replace YOUR_PROJECT_REF  (e.g. abcdefghijklmnop)
-- Replace YOUR_SERVICE_ROLE_KEY  (Settings → API → service_role)
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('weekly-family-digest')
  where exists (
    select 1 from cron.job where jobname = 'weekly-family-digest'
  );

select cron.schedule(
  'weekly-family-digest',
  '0 * * * *',
  $$
  select net.http_post(
    url     := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/weekly-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
    ),
    body    := '{}'::jsonb
  ) as request_id;
  $$
);

select jobname, schedule from cron.job where jobname = 'weekly-family-digest';
