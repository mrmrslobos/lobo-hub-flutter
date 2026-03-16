-- =============================================================================
-- Migration: Rename all camelCase columns to snake_case
-- =============================================================================
-- Run this in the Supabase SQL Editor to migrate an existing database that was
-- created with fresh-setup.sql (which used camelCase column names).
--
-- This script is idempotent — it checks whether the old column exists before
-- attempting the rename, so it is safe to run multiple times.
--
-- After running this, deploy the updated Edge Functions (notify-family,
-- weekly-digest, daily-devotional) which already use snake_case column names.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Helper: rename a column only if the old name exists and the new name does not
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _rename_col_if_exists(
  p_table text, p_old text, p_new text
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = p_table AND column_name = p_old
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = p_table AND column_name = p_new
  ) THEN
    EXECUTE format('ALTER TABLE %I RENAME COLUMN %I TO %I', p_table, p_old, p_new);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- families
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('families', 'ownerId',                'owner_id');
SELECT _rename_col_if_exists('families', 'joinCode',               'join_code');
SELECT _rename_col_if_exists('families', 'announcementAuthor',     'announcement_author');
SELECT _rename_col_if_exists('families', 'subscriptionTier',       'subscription_tier');
SELECT _rename_col_if_exists('families', 'enabledModules',         'enabled_modules');
SELECT _rename_col_if_exists('families', 'createdAt',              'created_at');
SELECT _rename_col_if_exists('families', 'welcomeDismissed',       'welcome_dismissed');
SELECT _rename_col_if_exists('families', 'weeklyDigest',           'weekly_digest');
SELECT _rename_col_if_exists('families', 'weeklyDigestDay',        'weekly_digest_day');
SELECT _rename_col_if_exists('families', 'weeklyDigestHour',       'weekly_digest_hour');
SELECT _rename_col_if_exists('families', 'dailyDevotionalEnabled', 'daily_devotional_enabled');
SELECT _rename_col_if_exists('families', 'dailyDevotionalHour',    'daily_devotional_hour');
SELECT _rename_col_if_exists('families', 'dailyDevotionalMinute',  'daily_devotional_minute');

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('family_members', 'userId',       'user_id');
SELECT _rename_col_if_exists('family_members', 'familyId',     'family_id');
SELECT _rename_col_if_exists('family_members', 'moduleAccess', 'module_access');
SELECT _rename_col_if_exists('family_members', 'displayName',  'display_name');

-- ---------------------------------------------------------------------------
-- tasks
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('tasks', 'familyId',        'family_id');
SELECT _rename_col_if_exists('tasks', 'creatorId',       'creator_id');
SELECT _rename_col_if_exists('tasks', 'dueDate',         'due_date');
SELECT _rename_col_if_exists('tasks', 'dueTime',         'due_time');
SELECT _rename_col_if_exists('tasks', 'reminderMinutes', 'reminder_minutes');
SELECT _rename_col_if_exists('tasks', 'completedBy',     'completed_by');
SELECT _rename_col_if_exists('tasks', 'updatedBy',       'updated_by');

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('events', 'familyId',           'family_id');
SELECT _rename_col_if_exists('events', 'creatorId',          'creator_id');
SELECT _rename_col_if_exists('events', 'sharedWith',         'shared_with');
SELECT _rename_col_if_exists('events', 'budgetEstimate',     'budget_estimate');
SELECT _rename_col_if_exists('events', 'externalCalendarId', 'external_calendar_id');
SELECT _rename_col_if_exists('events', 'externalUid',        'external_uid');

-- ---------------------------------------------------------------------------
-- recipes
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('recipes', 'familyId', 'family_id');

-- ---------------------------------------------------------------------------
-- meal_plans
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('meal_plans', 'familyId',   'family_id');
SELECT _rename_col_if_exists('meal_plans', 'mealType',   'meal_type');
SELECT _rename_col_if_exists('meal_plans', 'recipeId',   'recipe_id');
SELECT _rename_col_if_exists('meal_plans', 'customMeal', 'custom_meal');

-- ---------------------------------------------------------------------------
-- lists
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('lists', 'familyId',  'family_id');
SELECT _rename_col_if_exists('lists', 'creatorId', 'creator_id');

-- ---------------------------------------------------------------------------
-- devotionals
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('devotionals', 'familyId',          'family_id');
SELECT _rename_col_if_exists('devotionals', 'creatorId',         'creator_id');
SELECT _rename_col_if_exists('devotionals', 'reflectionPrompts', 'reflection_prompts');
SELECT _rename_col_if_exists('devotionals', 'userPrayer',        'user_prayer');
SELECT _rename_col_if_exists('devotionals', 'isFavorited',       'is_favorited');

-- ---------------------------------------------------------------------------
-- fitness
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('fitness', 'userId', 'user_id');

-- ---------------------------------------------------------------------------
-- fitness_plans
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('fitness_plans', 'userId',    'user_id');
SELECT _rename_col_if_exists('fitness_plans', 'weeklyPlan','weekly_plan');
SELECT _rename_col_if_exists('fitness_plans', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- budget_categories
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('budget_categories', 'familyId',  'family_id');
SELECT _rename_col_if_exists('budget_categories', 'creatorId', 'creator_id');

-- ---------------------------------------------------------------------------
-- transactions
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('transactions', 'familyId',   'family_id');
SELECT _rename_col_if_exists('transactions', 'creatorId',  'creator_id');
SELECT _rename_col_if_exists('transactions', 'categoryId', 'category_id');

-- ---------------------------------------------------------------------------
-- ai_history
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('ai_history', 'userId',    'user_id');
SELECT _rename_col_if_exists('ai_history', 'familyId',  'family_id');
SELECT _rename_col_if_exists('ai_history', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- daily_habits
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('daily_habits', 'userId',    'user_id');
SELECT _rename_col_if_exists('daily_habits', 'familyId',  'family_id');
SELECT _rename_col_if_exists('daily_habits', 'isShared',   'is_shared');
SELECT _rename_col_if_exists('daily_habits', 'targetValue','target_value');
SELECT _rename_col_if_exists('daily_habits', 'targetUnit', 'target_unit');
SELECT _rename_col_if_exists('daily_habits', 'createdAt',  'created_at');

-- ---------------------------------------------------------------------------
-- daily_habit_completions
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('daily_habit_completions', 'habitId',     'habit_id');
SELECT _rename_col_if_exists('daily_habit_completions', 'userId',      'user_id');
SELECT _rename_col_if_exists('daily_habit_completions', 'completedAt', 'completed_at');

-- ---------------------------------------------------------------------------
-- chores
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('chores', 'familyId',         'family_id');
SELECT _rename_col_if_exists('chores', 'creatorId',        'creator_id');
SELECT _rename_col_if_exists('chores', 'daysOfWeek',       'days_of_week');
SELECT _rename_col_if_exists('chores', 'requiresApproval', 'requires_approval');
SELECT _rename_col_if_exists('chores', 'createdAt',        'created_at');

-- ---------------------------------------------------------------------------
-- chore_completions
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('chore_completions', 'choreId',        'chore_id');
SELECT _rename_col_if_exists('chore_completions', 'userId',         'user_id');
SELECT _rename_col_if_exists('chore_completions', 'familyId',       'family_id');
SELECT _rename_col_if_exists('chore_completions', 'completedAt',    'completed_at');
SELECT _rename_col_if_exists('chore_completions', 'approvalStatus', 'approval_status');
SELECT _rename_col_if_exists('chore_completions', 'approvedBy',     'approved_by');
SELECT _rename_col_if_exists('chore_completions', 'approvedAt',     'approved_at');

-- ---------------------------------------------------------------------------
-- polls
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('polls', 'familyId',      'family_id');
SELECT _rename_col_if_exists('polls', 'creatorId',     'creator_id');
SELECT _rename_col_if_exists('polls', 'allowMultiple', 'allow_multiple');
SELECT _rename_col_if_exists('polls', 'createdAt',     'created_at');

-- ---------------------------------------------------------------------------
-- poll_votes
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('poll_votes', 'pollId',   'poll_id');
SELECT _rename_col_if_exists('poll_votes', 'optionId', 'option_id');
SELECT _rename_col_if_exists('poll_votes', 'userId',   'user_id');
SELECT _rename_col_if_exists('poll_votes', 'familyId', 'family_id');
SELECT _rename_col_if_exists('poll_votes', 'votedAt',  'voted_at');

-- ---------------------------------------------------------------------------
-- external_calendars
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('external_calendars', 'familyId',   'family_id');
SELECT _rename_col_if_exists('external_calendars', 'creatorId',  'creator_id');
SELECT _rename_col_if_exists('external_calendars', 'lastSynced', 'last_synced');
SELECT _rename_col_if_exists('external_calendars', 'createdAt',  'created_at');

-- ---------------------------------------------------------------------------
-- rewards
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('rewards', 'familyId',   'family_id');
SELECT _rename_col_if_exists('rewards', 'pointCost',  'point_cost');
SELECT _rename_col_if_exists('rewards', 'redeemedBy', 'redeemed_by');

-- ---------------------------------------------------------------------------
-- reward_items
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('reward_items', 'familyId',  'family_id');
SELECT _rename_col_if_exists('reward_items', 'creatorId', 'creator_id');
SELECT _rename_col_if_exists('reward_items', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- reward_redemptions
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('reward_redemptions', 'familyId',    'family_id');
SELECT _rename_col_if_exists('reward_redemptions', 'userId',      'user_id');
SELECT _rename_col_if_exists('reward_redemptions', 'rewardId',    'reward_id');
SELECT _rename_col_if_exists('reward_redemptions', 'rewardTitle', 'reward_title');
SELECT _rename_col_if_exists('reward_redemptions', 'requestedAt', 'requested_at');
SELECT _rename_col_if_exists('reward_redemptions', 'resolvedAt',  'resolved_at');
SELECT _rename_col_if_exists('reward_redemptions', 'resolvedBy',  'resolved_by');

-- ---------------------------------------------------------------------------
-- savings_goals
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('savings_goals', 'familyId',     'family_id');
SELECT _rename_col_if_exists('savings_goals', 'userId',       'user_id');
SELECT _rename_col_if_exists('savings_goals', 'imageUrl',     'image_url');
SELECT _rename_col_if_exists('savings_goals', 'targetAmount', 'target_amount');
SELECT _rename_col_if_exists('savings_goals', 'savedAmount',  'saved_amount');
SELECT _rename_col_if_exists('savings_goals', 'createdAt',    'created_at');
SELECT _rename_col_if_exists('savings_goals', 'completedAt',  'completed_at');

-- ---------------------------------------------------------------------------
-- prayer_wall
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('prayer_wall', 'familyId',          'family_id');
SELECT _rename_col_if_exists('prayer_wall', 'creatorId',         'creator_id');
SELECT _rename_col_if_exists('prayer_wall', 'originalRequestId', 'original_request_id');
SELECT _rename_col_if_exists('prayer_wall', 'prayedByIds',       'prayed_by_ids');
SELECT _rename_col_if_exists('prayer_wall', 'answeredAt',        'answered_at');

-- ---------------------------------------------------------------------------
-- reading_plans
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('reading_plans', 'familyId',  'family_id');
SELECT _rename_col_if_exists('reading_plans', 'creatorId', 'creator_id');
SELECT _rename_col_if_exists('reading_plans', 'totalDays', 'total_days');
SELECT _rename_col_if_exists('reading_plans', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- reading_plan_progress
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('reading_plan_progress', 'planId',          'plan_id');
SELECT _rename_col_if_exists('reading_plan_progress', 'userId',          'user_id');
SELECT _rename_col_if_exists('reading_plan_progress', 'familyId',        'family_id');
SELECT _rename_col_if_exists('reading_plan_progress', 'completedDays',   'completed_days');
SELECT _rename_col_if_exists('reading_plan_progress', 'currentStreak',   'current_streak');
SELECT _rename_col_if_exists('reading_plan_progress', 'longestStreak',   'longest_streak');
SELECT _rename_col_if_exists('reading_plan_progress', 'startedAt',       'started_at');
SELECT _rename_col_if_exists('reading_plan_progress', 'lastCompletedAt', 'last_completed_at');

-- ---------------------------------------------------------------------------
-- period_cycles
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('period_cycles', 'userId',    'user_id');
SELECT _rename_col_if_exists('period_cycles', 'familyId',  'family_id');
SELECT _rename_col_if_exists('period_cycles', 'startDate', 'start_date');
SELECT _rename_col_if_exists('period_cycles', 'endDate',   'end_date');
SELECT _rename_col_if_exists('period_cycles', 'flowLevel', 'flow_level');
SELECT _rename_col_if_exists('period_cycles', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- period_symptoms
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('period_symptoms', 'userId',    'user_id');
SELECT _rename_col_if_exists('period_symptoms', 'familyId',  'family_id');
SELECT _rename_col_if_exists('period_symptoms', 'painLevel', 'pain_level');
SELECT _rename_col_if_exists('period_symptoms', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- device_tokens
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('device_tokens', 'userId',    'user_id');
SELECT _rename_col_if_exists('device_tokens', 'familyId',  'family_id');
SELECT _rename_col_if_exists('device_tokens', 'updatedAt', 'updated_at');

-- ---------------------------------------------------------------------------
-- special_dates (may not exist yet on all installs)
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('special_dates', 'familyId',     'family_id');
SELECT _rename_col_if_exists('special_dates', 'creatorId',    'creator_id');
SELECT _rename_col_if_exists('special_dates', 'reminderDays', 'reminder_days');
SELECT _rename_col_if_exists('special_dates', 'createdAt',    'created_at');

-- ---------------------------------------------------------------------------
-- family_photos
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('family_photos', 'familyId',    'family_id');
SELECT _rename_col_if_exists('family_photos', 'uploaderId',  'uploader_id');
SELECT _rename_col_if_exists('family_photos', 'takenAt',     'taken_at');
SELECT _rename_col_if_exists('family_photos', 'createdAt',   'created_at');
SELECT _rename_col_if_exists('family_photos', 'milestoneId', 'milestone_id');

-- ---------------------------------------------------------------------------
-- milestones
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('milestones', 'familyId',  'family_id');
SELECT _rename_col_if_exists('milestones', 'childId',   'child_id');
SELECT _rename_col_if_exists('milestones', 'photoIds',  'photo_ids');
SELECT _rename_col_if_exists('milestones', 'ageLabel',  'age_label');
SELECT _rename_col_if_exists('milestones', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- saved_places
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('saved_places', 'familyId',     'family_id');
SELECT _rename_col_if_exists('saved_places', 'creatorId',    'creator_id');
SELECT _rename_col_if_exists('saved_places', 'radiusMetres', 'radius_metres');
SELECT _rename_col_if_exists('saved_places', 'createdAt',    'created_at');

-- ---------------------------------------------------------------------------
-- user_locations
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('user_locations', 'familyId',  'family_id');
SELECT _rename_col_if_exists('user_locations', 'userId',    'user_id');
SELECT _rename_col_if_exists('user_locations', 'placeName', 'place_name');
SELECT _rename_col_if_exists('user_locations', 'nearPlace', 'near_place');
SELECT _rename_col_if_exists('user_locations', 'isSharing', 'is_sharing');
SELECT _rename_col_if_exists('user_locations', 'updatedAt', 'updated_at');

-- ---------------------------------------------------------------------------
-- health_records
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('health_records', 'familyId',              'family_id');
SELECT _rename_col_if_exists('health_records', 'memberId',              'member_id');
SELECT _rename_col_if_exists('health_records', 'updatedBy',             'updated_by');
SELECT _rename_col_if_exists('health_records', 'bloodType',             'blood_type');
SELECT _rename_col_if_exists('health_records', 'emergencyContacts',     'emergency_contacts');
SELECT _rename_col_if_exists('health_records', 'doctorName',            'doctor_name');
SELECT _rename_col_if_exists('health_records', 'doctorPhone',           'doctor_phone');
SELECT _rename_col_if_exists('health_records', 'insuranceProvider',     'insurance_provider');
SELECT _rename_col_if_exists('health_records', 'insurancePolicyNumber', 'insurance_policy_number');
SELECT _rename_col_if_exists('health_records', 'updatedAt',             'updated_at');

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('messages', 'familyId',  'family_id');
SELECT _rename_col_if_exists('messages', 'userId',    'user_id');
SELECT _rename_col_if_exists('messages', 'replyToId', 'reply_to_id');
SELECT _rename_col_if_exists('messages', 'editedAt',  'edited_at');
SELECT _rename_col_if_exists('messages', 'createdAt', 'created_at');

-- ---------------------------------------------------------------------------
-- web_push_subscriptions
-- ---------------------------------------------------------------------------
SELECT _rename_col_if_exists('web_push_subscriptions', 'userId',    'user_id');
SELECT _rename_col_if_exists('web_push_subscriptions', 'familyId',  'family_id');
SELECT _rename_col_if_exists('web_push_subscriptions', 'updatedAt', 'updated_at');


-- =============================================================================
-- Recreate helper functions with snake_case column references
-- =============================================================================

CREATE OR REPLACE FUNCTION auth_is_member_of(fid text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM family_members
    WHERE family_id = fid
      AND user_id = auth.uid()::text
  );
$$;

CREATE OR REPLACE FUNCTION find_family_by_join_code(code text)
RETURNS SETOF families
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT * FROM families WHERE join_code = code LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION claim_owned_families()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_id    text := auth.uid()::text;
  old_id    text;
  usr_email text;
BEGIN
  IF new_id IS NULL THEN RETURN; END IF;

  SELECT email INTO usr_email FROM auth.users WHERE id = auth.uid();
  IF usr_email IS NULL THEN RETURN; END IF;

  SELECT id INTO old_id
  FROM users
  WHERE email = usr_email AND id <> new_id
  LIMIT 1;

  IF old_id IS NULL THEN RETURN; END IF;

  UPDATE users            SET id       = new_id WHERE id       = old_id;
  UPDATE families         SET owner_id = new_id WHERE owner_id = old_id;
  UPDATE family_members   SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE fitness          SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE fitness_plans    SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE daily_habits     SET user_id  = new_id WHERE user_id  = old_id;
  UPDATE daily_habit_completions SET user_id = new_id WHERE user_id = old_id;
  UPDATE device_tokens    SET user_id  = new_id WHERE user_id  = old_id;
END;
$$;


-- =============================================================================
-- Recreate all RLS policies with snake_case column references
-- =============================================================================
-- All policy operations are wrapped in a DO block that checks table existence
-- first, so this migration works even if some tables haven't been created yet.
-- =============================================================================

DO $$
DECLARE
  _t text;
BEGIN
  -- -----------------------------------------------------------------------
  -- Helper: drop + create a policy only if the table exists
  -- -----------------------------------------------------------------------

  -- users (special: cross-family visibility)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
    EXECUTE 'DROP POLICY IF EXISTS "users_select" ON users';
    EXECUTE $p$CREATE POLICY "users_select" ON users FOR SELECT
      USING (
        id = auth.uid()::text
        OR EXISTS (
          SELECT 1 FROM family_members fm1
          JOIN family_members fm2 ON fm1.family_id = fm2.family_id
          WHERE fm1.user_id = auth.uid()::text
            AND fm2.user_id = users.id
        )
      )$p$;
    EXECUTE 'DROP POLICY IF EXISTS "users_insert" ON users';
    EXECUTE $p$CREATE POLICY "users_insert" ON users FOR INSERT WITH CHECK (id = auth.uid()::text)$p$;
    EXECUTE 'DROP POLICY IF EXISTS "users_update" ON users';
    EXECUTE $p$CREATE POLICY "users_update" ON users FOR UPDATE USING (id = auth.uid()::text) WITH CHECK (id = auth.uid()::text)$p$;
    EXECUTE 'DROP POLICY IF EXISTS "users_delete" ON users';
    EXECUTE $p$CREATE POLICY "users_delete" ON users FOR DELETE USING (id = auth.uid()::text)$p$;
  END IF;

  -- families (special: owner-based update/delete)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='families') THEN
    EXECUTE 'DROP POLICY IF EXISTS "families_select" ON families';
    EXECUTE $p$CREATE POLICY "families_select" ON families FOR SELECT USING (auth_is_member_of(id))$p$;
    EXECUTE 'DROP POLICY IF EXISTS "families_insert" ON families';
    EXECUTE $p$CREATE POLICY "families_insert" ON families FOR INSERT WITH CHECK (auth.uid() IS NOT NULL)$p$;
    EXECUTE 'DROP POLICY IF EXISTS "families_update" ON families';
    EXECUTE $p$CREATE POLICY "families_update" ON families FOR UPDATE USING (owner_id = auth.uid()::text) WITH CHECK (owner_id = auth.uid()::text)$p$;
    EXECUTE 'DROP POLICY IF EXISTS "families_delete" ON families';
    EXECUTE $p$CREATE POLICY "families_delete" ON families FOR DELETE USING (owner_id = auth.uid()::text)$p$;
  END IF;

  -- family_members (special: self + owner/admin)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='family_members') THEN
    EXECUTE 'DROP POLICY IF EXISTS "family_members_select" ON family_members';
    EXECUTE $p$CREATE POLICY "family_members_select" ON family_members FOR SELECT USING (auth_is_member_of(family_id))$p$;
    EXECUTE 'DROP POLICY IF EXISTS "family_members_insert" ON family_members';
    EXECUTE $p$CREATE POLICY "family_members_insert" ON family_members FOR INSERT
      WITH CHECK (
        user_id = auth.uid()::text
        OR EXISTS (
          SELECT 1 FROM family_members fm
          WHERE fm.family_id = family_members.family_id
            AND fm.user_id = auth.uid()::text
            AND fm.role IN ('OWNER', 'ADMIN')
        )
      )$p$;
    EXECUTE 'DROP POLICY IF EXISTS "family_members_update" ON family_members';
    EXECUTE $p$CREATE POLICY "family_members_update" ON family_members FOR UPDATE
      USING (
        user_id = auth.uid()::text
        OR EXISTS (
          SELECT 1 FROM family_members fm
          WHERE fm.family_id = family_members.family_id
            AND fm.user_id = auth.uid()::text
            AND fm.role IN ('OWNER', 'ADMIN')
        )
      )
      WITH CHECK (
        user_id = auth.uid()::text
        OR EXISTS (
          SELECT 1 FROM family_members fm
          WHERE fm.family_id = family_members.family_id
            AND fm.user_id = auth.uid()::text
            AND fm.role IN ('OWNER', 'ADMIN')
        )
      )$p$;
    EXECUTE 'DROP POLICY IF EXISTS "family_members_delete" ON family_members';
    EXECUTE $p$CREATE POLICY "family_members_delete" ON family_members FOR DELETE
      USING (
        user_id = auth.uid()::text
        OR EXISTS (
          SELECT 1 FROM family_members fm
          WHERE fm.family_id = family_members.family_id
            AND fm.user_id = auth.uid()::text
            AND fm.role IN ('OWNER', 'ADMIN')
        )
      )$p$;
  END IF;

  -- Family-scoped tables: auth_is_member_of(family_id)
  FOREACH _t IN ARRAY ARRAY[
    'tasks','events','recipes','meal_plans','lists','devotionals',
    'budget_categories','transactions','ai_history',
    'chores','chore_completions','polls','poll_votes','external_calendars',
    'rewards','reward_items','reward_redemptions','savings_goals',
    'prayer_wall','reading_plans','reading_plan_progress',
    'special_dates','family_photos','milestones','saved_places',
    'user_locations','health_records','messages'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=_t) THEN
      -- Drop old permissive policies from schema.sql
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_auth" ON %I', _t, _t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_ro_anon" ON %I', _t, _t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_anon" ON %I', _t, _t);
      -- Drop and recreate the _all policy
      EXECUTE format('DROP POLICY IF EXISTS "%s_all" ON %I', _t, _t);
      EXECUTE format('CREATE POLICY "%s_all" ON %I FOR ALL USING (auth_is_member_of(family_id)) WITH CHECK (auth_is_member_of(family_id))', _t, _t);
    END IF;
  END LOOP;

  -- Personal tables: user_id = auth.uid()
  FOREACH _t IN ARRAY ARRAY[
    'fitness','fitness_plans','daily_habits','period_cycles','period_symptoms'
  ]
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=_t) THEN
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_auth" ON %I', _t, _t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_ro_anon" ON %I', _t, _t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_rw_anon" ON %I', _t, _t);
      EXECUTE format('DROP POLICY IF EXISTS "%s_all" ON %I', _t, _t);
      EXECUTE format('CREATE POLICY "%s_all" ON %I FOR ALL USING (user_id = auth.uid()::text) WITH CHECK (user_id = auth.uid()::text)', _t, _t);
    END IF;
  END LOOP;

  -- daily_habit_completions (special: owner of habit can also see)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='daily_habit_completions') THEN
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_rw_auth" ON daily_habit_completions';
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_ro_anon" ON daily_habit_completions';
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_rw_anon" ON daily_habit_completions';
    EXECUTE 'DROP POLICY IF EXISTS "daily_habit_completions_all" ON daily_habit_completions';
    EXECUTE $p$CREATE POLICY "daily_habit_completions_all" ON daily_habit_completions FOR ALL
      USING (
        user_id = auth.uid()::text
        OR EXISTS (
          SELECT 1 FROM daily_habits dh
          WHERE dh.id = daily_habit_completions.habit_id
            AND dh.user_id = auth.uid()::text
        )
      )
      WITH CHECK (user_id = auth.uid()::text)$p$;
  END IF;

  -- device_tokens
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='device_tokens') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Users manage own tokens" ON device_tokens';
    EXECUTE $p$CREATE POLICY "Users manage own tokens" ON device_tokens FOR ALL
      USING  (auth.uid()::text = user_id)
      WITH CHECK (auth.uid()::text = user_id)$p$;
  END IF;

  -- web_push_subscriptions
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='web_push_subscriptions') THEN
    EXECUTE 'DROP POLICY IF EXISTS "Users manage own web push subscriptions" ON web_push_subscriptions';
    EXECUTE $p$CREATE POLICY "Users manage own web push subscriptions" ON web_push_subscriptions FOR ALL
      USING  (auth.uid()::text = user_id)
      WITH CHECK (auth.uid()::text = user_id)$p$;
  END IF;

END $$;

-- ---------------------------------------------------------------------------
-- Clean up helper function
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS _rename_col_if_exists(text, text, text);

COMMIT;
