-- fitness_logs: store workout logs (encrypted fields stored as ciphertext text)
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS fitness_logs (
  id              text PRIMARY KEY,
  family_id      text NOT NULL,
  user_id        text NOT NULL,
  activity       text NOT NULL,
  duration_minutes text NOT NULL,
  calories_burned  text,
  notes           text,
  date            text NOT NULL
);

-- If the table already existed with numeric columns, widen them to `text`
-- so encrypted ciphertext strings can be stored.
DO $$ BEGIN
  ALTER TABLE fitness_logs ALTER COLUMN duration_minutes TYPE text USING duration_minutes::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE fitness_logs ALTER COLUMN calories_burned TYPE text USING calories_burned::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

ALTER TABLE fitness_logs ENABLE ROW LEVEL SECURITY;

-- Family members can READ all logs for their family.
CREATE POLICY "fitness_logs_select_family"
  ON fitness_logs
  FOR SELECT
  USING (auth_is_member_of(family_id));

-- Only the owner can INSERT/UPDATE/DELETE their own logs.
CREATE POLICY "fitness_logs_insert_own"
  ON fitness_logs
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "fitness_logs_update_own"
  ON fitness_logs
  FOR UPDATE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "fitness_logs_delete_own"
  ON fitness_logs
  FOR DELETE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

