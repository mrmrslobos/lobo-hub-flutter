-- Daily Devotional cron — replace YOUR_PROJECT_REF and YOUR_SERVICE_ROLE_KEY

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('daily-family-devotional')
  where exists (select 1 from cron.job where jobname = 'daily-family-devotional');

select cron.schedule(
  'daily-family-devotional',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/daily-devotional',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY',
      'x-daily-devotional-secret', 'YOUR_DAILY_DEVOTIONAL_CRON_SECRET'
    ),
    body    := '{}'::jsonb
  ) as request_id;
  $$
);

select jobname, schedule from cron.job where jobname = 'daily-family-devotional';
