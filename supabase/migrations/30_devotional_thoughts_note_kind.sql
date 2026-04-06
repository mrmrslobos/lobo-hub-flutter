-- Split per-user "thought" vs "prayer" rows (same RLS as migration 29).

ALTER TABLE devotional_thoughts
  ADD COLUMN IF NOT EXISTS note_kind text NOT NULL DEFAULT 'thought';

UPDATE devotional_thoughts
SET note_kind = 'thought'
WHERE trim(coalesce(note_kind, '')) = '';

DROP INDEX IF EXISTS devotional_thoughts_devotional_user_idx;

CREATE UNIQUE INDEX IF NOT EXISTS devotional_thoughts_devotional_user_kind_idx
  ON devotional_thoughts (devotional_id, user_id, note_kind);

ALTER TABLE devotional_thoughts DROP CONSTRAINT IF EXISTS devotional_thoughts_note_kind_check;
ALTER TABLE devotional_thoughts ADD CONSTRAINT devotional_thoughts_note_kind_check
  CHECK (note_kind IN ('thought', 'prayer'));
