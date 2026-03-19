ALTER TABLE prayer_wall ADD COLUMN IF NOT EXISTS prayed_by_ids jsonb NOT NULL DEFAULT '[]'::jsonb;
