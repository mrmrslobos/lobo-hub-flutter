-- =============================================================================
-- Migration Part 2: Update functions and RLS policies for snake_case
-- =============================================================================
-- Run this AFTER Part 1 (01_rename_columns_to_snake_case.sql).
-- Safe to re-run — all operations use DROP IF EXISTS / CREATE OR REPLACE.
-- =============================================================================

-- =============================================================================
-- Recreate helper functions with snake_case column references
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_is_member_of(fid text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn1$
  SELECT EXISTS (
    SELECT 1 FROM family_members
    WHERE family_id = fid AND user_id = auth.uid()::text
  );
$fn1$;

CREATE OR REPLACE FUNCTION find_family_by_join_code(code text)
RETURNS SETOF families LANGUAGE sql SECURITY DEFINER STABLE AS $fn2$
  SELECT * FROM families WHERE join_code = code LIMIT 1;
$fn2$;

CREATE OR REPLACE FUNCTION claim_owned_families()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn3$
DECLARE
  new_id text := auth.uid()::text;
  old_id text;
  usr_email text;
BEGIN
  IF new_id IS NULL THEN RETURN; END IF;
  SELECT email INTO usr_email FROM auth.users WHERE id = auth.uid();
  IF usr_email IS NULL THEN RETURN; END IF;
  SELECT id INTO old_id FROM users WHERE email = usr_email AND id <> new_id LIMIT 1;
  IF old_id IS NULL THEN RETURN; END IF;
  UPDATE users SET id = new_id WHERE id = old_id;
  UPDATE families SET owner_id = new_id WHERE owner_id = old_id;
  UPDATE family_members SET user_id = new_id WHERE user_id = old_id;
  UPDATE fitness SET user_id = new_id WHERE user_id = old_id;
  UPDATE fitness_plans SET user_id = new_id WHERE user_id = old_id;
  UPDATE daily_habits SET user_id = new_id WHERE user_id = old_id;
  UPDATE daily_habit_completions SET user_id = new_id WHERE user_id = old_id;
  UPDATE device_tokens SET user_id = new_id WHERE user_id = old_id;
END;
$fn3$;

-- =============================================================================
-- Recreate RLS policies — users
-- =============================================================================
DROP POLICY IF EXISTS "users_select" ON users;
DROP POLICY IF EXISTS "users_insert" ON users;
DROP POLICY IF EXISTS "users_update" ON users;
DROP POLICY IF EXISTS "users_delete" ON users;
DROP POLICY IF EXISTS "users_rw_auth" ON users;
DROP POLICY IF EXISTS "users_ro_anon" ON users;

CREATE POLICY "users_select" ON users FOR SELECT USING (
  id = auth.uid()::text
  OR EXISTS (
    SELECT 1 FROM family_members fm1
    JOIN family_members fm2 ON fm1.family_id = fm2.family_id
    WHERE fm1.user_id = auth.uid()::text AND fm2.user_id = users.id
  )
);
CREATE POLICY "users_insert" ON users FOR INSERT WITH CHECK (id = auth.uid()::text);
CREATE POLICY "users_update" ON users FOR UPDATE USING (id = auth.uid()::text) WITH CHECK (id = auth.uid()::text);
CREATE POLICY "users_delete" ON users FOR DELETE USING (id = auth.uid()::text);

-- =============================================================================
-- Recreate RLS policies — families
-- =============================================================================
DROP POLICY IF EXISTS "families_select" ON families;
DROP POLICY IF EXISTS "families_insert" ON families;
DROP POLICY IF EXISTS "families_update" ON families;
DROP POLICY IF EXISTS "families_delete" ON families;
DROP POLICY IF EXISTS "families_rw_auth" ON families;
DROP POLICY IF EXISTS "families_ro_anon" ON families;

CREATE POLICY "families_select" ON families FOR SELECT USING (auth_is_member_of(id));
CREATE POLICY "families_insert" ON families FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "families_update" ON families FOR UPDATE USING (owner_id = auth.uid()::text) WITH CHECK (owner_id = auth.uid()::text);
CREATE POLICY "families_delete" ON families FOR DELETE USING (owner_id = auth.uid()::text);

-- =============================================================================
-- Recreate RLS policies — family_members
-- =============================================================================
DROP POLICY IF EXISTS "family_members_select" ON family_members;
DROP POLICY IF EXISTS "family_members_insert" ON family_members;
DROP POLICY IF EXISTS "family_members_update" ON family_members;
DROP POLICY IF EXISTS "family_members_delete" ON family_members;
DROP POLICY IF EXISTS "family_members_rw_auth" ON family_members;
DROP POLICY IF EXISTS "family_members_ro_anon" ON family_members;

CREATE POLICY "family_members_select" ON family_members FOR SELECT USING (auth_is_member_of(family_id));
CREATE POLICY "family_members_insert" ON family_members FOR INSERT
  WITH CHECK (
    user_id = auth.uid()::text
    OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN ('OWNER','ADMIN'))
  );
CREATE POLICY "family_members_update" ON family_members FOR UPDATE
  USING (
    user_id = auth.uid()::text
    OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN ('OWNER','ADMIN'))
  )
  WITH CHECK (
    user_id = auth.uid()::text
    OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN ('OWNER','ADMIN'))
  );
CREATE POLICY "family_members_delete" ON family_members FOR DELETE
  USING (
    user_id = auth.uid()::text
    OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN ('OWNER','ADMIN'))
  );

-- =============================================================================
-- Family-scoped tables: drop old + create new policy
-- Uses DO block with format() to handle missing tables gracefully.
-- =============================================================================
DO $do1$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tasks','events','recipes','meal_plans','lists','devotionals',
    'budget_categories','transactions','ai_history',
    'chores','chore_completions','polls','poll_votes','external_calendars',
    'rewards','reward_items','reward_redemptions','savings_goals',
    'prayer_wall','reading_plans','reading_plan_progress',
    'special_dates','family_photos','milestones','saved_places',
    'user_locations','health_records','messages'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_auth" ON %I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_ro_anon" ON %I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_anon" ON %I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_all" ON %I', t, t);
      EXECUTE format('CREATE POLICY "%s_all" ON %I FOR ALL USING (auth_is_member_of(family_id)) WITH CHECK (auth_is_member_of(family_id))', t, t);
    END IF;
  END LOOP;
END
$do1$;

-- =============================================================================
-- Personal tables: user_id = auth.uid()
-- =============================================================================
DO $do2$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'fitness','fitness_plans','daily_habits','period_cycles','period_symptoms'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_auth" ON %I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_ro_anon" ON %I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_anon" ON %I', t, t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_all" ON %I', t, t);
      EXECUTE format('CREATE POLICY "%s_all" ON %I FOR ALL USING (user_id = auth.uid()::text) WITH CHECK (user_id = auth.uid()::text)', t, t);
    END IF;
  END LOOP;
END
$do2$;

-- =============================================================================
-- daily_habit_completions (special: habit owner can also read)
-- =============================================================================
DO $do3$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='daily_habit_completions') THEN
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_rw_auth" ON daily_habit_completions';
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_ro_anon" ON daily_habit_completions';
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_all" ON daily_habit_completions';
    EXECUTE 'CREATE POLICY "daily_habit_completions_all" ON daily_habit_completions FOR ALL
      USING (user_id = auth.uid()::text OR EXISTS (SELECT 1 FROM daily_habits dh WHERE dh.id = daily_habit_completions.habit_id AND dh.user_id = auth.uid()::text))
      WITH CHECK (user_id = auth.uid()::text)';
  END IF;
END
$do3$;

-- =============================================================================
-- device_tokens + web_push_subscriptions
-- =============================================================================
DO $do4$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='device_tokens') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Users manage own tokens" ON device_tokens';
    EXECUTE 'CREATE POLICY "Users manage own tokens" ON device_tokens FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='web_push_subscriptions') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Users manage own web push subscriptions" ON web_push_subscriptions';
    EXECUTE 'CREATE POLICY "Users manage own web push subscriptions" ON web_push_subscriptions FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id)';
  END IF;
END
$do4$;
