-- Family fields the app syncs — safe to re-run.
ALTER TABLE families ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'AUD';
ALTER TABLE families ADD COLUMN IF NOT EXISTS trial_start_date timestamptz;
