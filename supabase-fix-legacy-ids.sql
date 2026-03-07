-- =============================================================================
-- Lobo Hub — One-time data repair: migrate legacy random IDs to Supabase UUIDs
-- =============================================================================
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor → Run).
-- The SQL Editor executes as the postgres superuser, so it bypasses RLS and
-- can update rows that the app itself cannot (because the ownerId/userId still
-- holds the old random ID, making the RLS UPDATE USING check fail).
--
-- What this does:
--   Finds every row in the `users` table whose `id` doesn't match the
--   `id` in `auth.users` for the same email address — these are legacy
--   profiles created before Supabase Auth was configured.  For each one,
--   it updates ALL referencing rows to use the correct Supabase Auth UUID.
--
-- This is idempotent: if no legacy rows exist it does nothing.
-- Safe to run multiple times.
-- =============================================================================

DO $$
DECLARE
  rec    RECORD;
  n      int := 0;
BEGIN
  FOR rec IN
    SELECT u.id AS old_id, au.id::text AS new_id, au.email
    FROM   users u
    JOIN   auth.users au ON au.email = u.email
    WHERE  u.id != au.id::text          -- old random ID ≠ Supabase Auth UUID
  LOOP
    RAISE NOTICE 'Migrating user % → % (%)', rec.old_id, rec.new_id, rec.email;

    -- Core identity tables (have userId-based RLS — must be fixed for writes to work)
    UPDATE users            SET id         = rec.new_id WHERE id         = rec.old_id;
    UPDATE families         SET "ownerId"  = rec.new_id WHERE "ownerId"  = rec.old_id;
    UPDATE family_members   SET "userId"   = rec.new_id WHERE "userId"   = rec.old_id;

    -- Personal data tables (userId-based RLS)
    UPDATE fitness                 SET "userId" = rec.new_id WHERE "userId" = rec.old_id;
    UPDATE fitness_plans           SET "userId" = rec.new_id WHERE "userId" = rec.old_id;
    UPDATE daily_habits            SET "userId" = rec.new_id WHERE "userId" = rec.old_id;
    UPDATE daily_habit_completions SET "userId" = rec.new_id WHERE "userId" = rec.old_id;
    UPDATE device_tokens           SET "userId" = rec.new_id WHERE "userId" = rec.old_id;

    -- Family-scoped tables (these sync fine once family_members is fixed, but
    -- updating creatorId/userId here keeps historical attribution correct)
    UPDATE ai_history         SET "userId"    = rec.new_id WHERE "userId"    = rec.old_id;
    UPDATE savings_goals      SET "userId"    = rec.new_id WHERE "userId"    = rec.old_id;
    UPDATE poll_votes         SET "userId"    = rec.new_id WHERE "userId"    = rec.old_id;
    UPDATE reward_redemptions SET "userId"    = rec.new_id WHERE "userId"    = rec.old_id;
    UPDATE chore_completions  SET "userId"    = rec.new_id WHERE "userId"    = rec.old_id;
    UPDATE tasks  SET "creatorId" = rec.new_id WHERE "creatorId" = rec.old_id;
    UPDATE chores SET "creatorId" = rec.new_id WHERE "creatorId" = rec.old_id;

    n := n + 1;
  END LOOP;

  IF n = 0 THEN
    RAISE NOTICE 'No legacy IDs found — data is already up-to-date.';
  ELSE
    RAISE NOTICE 'Migration complete: % user(s) updated.', n;
  END IF;
END $$;
