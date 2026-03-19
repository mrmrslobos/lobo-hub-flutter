ALTER TABLE events ADD COLUMN IF NOT EXISTS shared_with jsonb NOT NULL DEFAULT '[]'::jsonb;
