-- Last-write-wins sync across family devices. Clients send/compare updated_at on merge.
-- Safe to re-run.
--
-- If you skip this migration: the Flutter app strips updated_at on upsert so rows
-- still insert; after you run this migration, you can optionally start sending
-- updated_at again from the client for server-side timestamps.

DO $m$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tasks','events','recipes','meal_plans','lists','devotionals',
    'budget_categories','budget_entries','transactions','chores','chore_completions',
    'polls','poll_votes','reward_items','reward_redemptions','savings_goals',
    'prayer_wall','special_dates','family_photos','milestones','saved_places',
    'messages','health_records','external_calendars','rewards','reading_plans',
    'user_locations','ai_history','daily_habits','daily_habit_completions',
    'period_cycles','period_symptoms'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
      EXECUTE format(
        'ALTER TABLE %I ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()',
        t
      );
    END IF;
  END LOOP;
END
$m$;
