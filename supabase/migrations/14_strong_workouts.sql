-- Strong integration: workout sessions + exercises + sets
-- Encrypted (FieldEncryption) workout fields are stored as ciphertext strings,
-- so any encrypted numeric/string columns are `text`.

-- ---------------------------------------------------------------------------
-- workout_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workout_sessions (
  id               text PRIMARY KEY,
  family_id       text NOT NULL,
  user_id         text NOT NULL,
  title           text NOT NULL,
  date            text NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 0,
  notes           text,
  created_at      text NOT NULL
);

ALTER TABLE workout_sessions ENABLE ROW LEVEL SECURITY;

-- Read: any family member can view all sessions in the family
CREATE POLICY "workout_sessions_select_family"
  ON workout_sessions
  FOR SELECT
  USING (
    auth_is_member_of(family_id)
  );

-- Write: only the owner can create/update/delete their own rows
CREATE POLICY "workout_sessions_write_own"
  ON workout_sessions
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "workout_sessions_update_own"
  ON workout_sessions
  FOR UPDATE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "workout_sessions_delete_own"
  ON workout_sessions
  FOR DELETE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

-- ---------------------------------------------------------------------------
-- workout_exercises
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workout_exercises (
  id            text PRIMARY KEY,
  family_id    text NOT NULL,
  user_id      text NOT NULL,
  session_id   text NOT NULL,
  exercise_name text NOT NULL,
  "order"      integer NOT NULL DEFAULT 0,
  rest_seconds integer NOT NULL DEFAULT 60,
  notes         text,
  created_at    text NOT NULL
);

ALTER TABLE workout_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workout_exercises_select_family"
  ON workout_exercises
  FOR SELECT
  USING (
    auth_is_member_of(family_id)
  );

CREATE POLICY "workout_exercises_write_own"
  ON workout_exercises
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "workout_exercises_update_own"
  ON workout_exercises
  FOR UPDATE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "workout_exercises_delete_own"
  ON workout_exercises
  FOR DELETE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

-- ---------------------------------------------------------------------------
-- workout_sets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workout_sets (
  id            text PRIMARY KEY,
  family_id    text NOT NULL,
  user_id      text NOT NULL,
  exercise_id  text NOT NULL,
  set_number   integer NOT NULL,
  reps          text NOT NULL,
  weight        text,
  completed     boolean NOT NULL DEFAULT false,
  notes         text,
  created_at    text NOT NULL
);

ALTER TABLE workout_sets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workout_sets_select_family"
  ON workout_sets
  FOR SELECT
  USING (
    auth_is_member_of(family_id)
  );

CREATE POLICY "workout_sets_write_own"
  ON workout_sets
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "workout_sets_update_own"
  ON workout_sets
  FOR UPDATE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

CREATE POLICY "workout_sets_delete_own"
  ON workout_sets
  FOR DELETE
  USING (
    user_id = auth.uid()::text
    AND auth_is_member_of(family_id)
  );

