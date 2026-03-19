ALTER TABLE tasks ADD COLUMN IF NOT EXISTS completed_by text;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS updated_by text;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS due_time text;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS reminder_minutes integer;
