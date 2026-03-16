-- ============================================================
-- Ensure daily devotional columns exist on the families table.
--
-- The original migration only RENAMED camelCase → snake_case.
-- If the columns were never created in the first place, the
-- rename was a no-op and the edge function fails silently.
-- This migration adds them if missing.
-- ============================================================

-- daily_devotional_enabled (default false)
DO $$ BEGIN
  ALTER TABLE families ADD COLUMN daily_devotional_enabled boolean DEFAULT false;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- daily_devotional_hour (0-23, UTC, default 12 = noon UTC)
DO $$ BEGIN
  ALTER TABLE families ADD COLUMN daily_devotional_hour integer DEFAULT 12;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- daily_devotional_minute (0-59, UTC, default 0)
DO $$ BEGIN
  ALTER TABLE families ADD COLUMN daily_devotional_minute integer DEFAULT 0;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

-- Also ensure the devotionals table has all columns the edge function needs
DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN creator_id text DEFAULT '00000000-0000-0000-0000-000000000000';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN scripture text;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN content text;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN reflection_prompts jsonb DEFAULT '[]'::jsonb;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN prayer text;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN tags jsonb DEFAULT '[]'::jsonb;
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE devotionals ADD COLUMN visibility text DEFAULT 'FAMILY';
EXCEPTION WHEN duplicate_column THEN NULL;
END $$;
