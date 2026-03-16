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

-- NOTE: No BEGIN/COMMIT transaction wrapper — Supabase SQL Editor runs each
-- statement independently. The migration is idempotent so this is safe.

-- ---------------------------------------------------------------------------
-- Helper: rename a column only if the old name exists and the new name does not
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _rename_col_if_exists(
  p_table text, p_old text, p_new text
) RETURNS void LANGUAGE plpgsql AS $fn_rename$
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
$fn_rename$;

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
AS $fn_auth$
  SELECT EXISTS (
    SELECT 1 FROM family_members
    WHERE family_id = fid
      AND user_id = auth.uid()::text
  );
$fn_auth$;

CREATE OR REPLACE FUNCTION find_family_by_join_code(code text)
RETURNS SETOF families
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $fn_join$
  SELECT * FROM families WHERE join_code = code LIMIT 1;
$fn_join$;

CREATE OR REPLACE FUNCTION claim_owned_families()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $fn_claim$
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
$fn_claim$;


-- =============================================================================
-- Helper function to recreate policies safely (skips missing tables)
-- =============================================================================
CREATE OR REPLACE FUNCTION _recreate_policy(
  p_table text,
  p_name text,
  p_cmd text,    -- 'ALL', 'SELECT', 'INSERT', 'UPDATE', 'DELETE'
  p_using text,  -- USING clause (NULL to omit)
  p_check text   -- WITH CHECK clause (NULL to omit)
) RETURNS void LANGUAGE plpgsql AS $fn_pol$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=p_table) THEN
    RETURN;
  END IF;
  EXECUTE format('DROP POLICY IF EXISTS %I ON %I', p_name, p_table);
  IF p_using IS NOT NULL AND p_check IS NOT NULL THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR %s USING (%s) WITH CHECK (%s)', p_name, p_table, p_cmd, p_using, p_check);
  ELSIF p_using IS NOT NULL THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR %s USING (%s)', p_name, p_table, p_cmd, p_using);
  ELSIF p_check IS NOT NULL THEN
    EXECUTE format('CREATE POLICY %I ON %I FOR %s WITH CHECK (%s)', p_name, p_table, p_cmd, p_check);
  END IF;
END;
$fn_pol$;

-- Helper to drop old permissive policies from schema.sql
CREATE OR REPLACE FUNCTION _drop_old_policies(p_table text)
RETURNS void LANGUAGE plpgsql AS $fn_drop$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=p_table) THEN
    RETURN;
  END IF;
  EXECUTE format('DROP POLICY IF EXISTS "%s_rw_auth" ON %I', p_table, p_table);
  EXECUTE format('DROP POLICY IF EXISTS "%s_ro_anon" ON %I', p_table, p_table);
  EXECUTE format('DROP POLICY IF EXISTS "%s_rw_anon" ON %I', p_table, p_table);
END;
$fn_drop$;


-- =============================================================================
-- Recreate all RLS policies with snake_case column references
-- =============================================================================

-- ---------------------------------------------------------------------------
-- users (special: cross-family visibility)
-- ---------------------------------------------------------------------------
SELECT _drop_old_policies('users');
SELECT _recreate_policy('users', 'users_select', 'SELECT',
  'id = auth.uid()::text OR EXISTS (SELECT 1 FROM family_members fm1 JOIN family_members fm2 ON fm1.family_id = fm2.family_id WHERE fm1.user_id = auth.uid()::text AND fm2.user_id = users.id)',
  NULL);
SELECT _recreate_policy('users', 'users_insert', 'INSERT', NULL, 'id = auth.uid()::text');
SELECT _recreate_policy('users', 'users_update', 'UPDATE', 'id = auth.uid()::text', 'id = auth.uid()::text');
SELECT _recreate_policy('users', 'users_delete', 'DELETE', 'id = auth.uid()::text', NULL);

-- ---------------------------------------------------------------------------
-- families (special: owner-based update/delete)
-- ---------------------------------------------------------------------------
SELECT _drop_old_policies('families');
SELECT _recreate_policy('families', 'families_select', 'SELECT', 'auth_is_member_of(id)', NULL);
SELECT _recreate_policy('families', 'families_insert', 'INSERT', NULL, 'auth.uid() IS NOT NULL');
SELECT _recreate_policy('families', 'families_update', 'UPDATE', 'owner_id = auth.uid()::text', 'owner_id = auth.uid()::text');
SELECT _recreate_policy('families', 'families_delete', 'DELETE', 'owner_id = auth.uid()::text', NULL);

-- ---------------------------------------------------------------------------
-- family_members (special: self + owner/admin)
-- ---------------------------------------------------------------------------
SELECT _drop_old_policies('family_members');
SELECT _recreate_policy('family_members', 'family_members_select', 'SELECT', 'auth_is_member_of(family_id)', NULL);
SELECT _recreate_policy('family_members', 'family_members_insert', 'INSERT', NULL,
  'user_id = auth.uid()::text OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN (''OWNER'', ''ADMIN''))');
SELECT _recreate_policy('family_members', 'family_members_update', 'UPDATE',
  'user_id = auth.uid()::text OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN (''OWNER'', ''ADMIN''))',
  'user_id = auth.uid()::text OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN (''OWNER'', ''ADMIN''))');
SELECT _recreate_policy('family_members', 'family_members_delete', 'DELETE',
  'user_id = auth.uid()::text OR EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.user_id = auth.uid()::text AND fm.role IN (''OWNER'', ''ADMIN''))', NULL);

-- ---------------------------------------------------------------------------
-- Family-scoped tables: auth_is_member_of(family_id)
-- ---------------------------------------------------------------------------
SELECT _drop_old_policies('tasks');
SELECT _recreate_policy('tasks', 'tasks_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('events');
SELECT _recreate_policy('events', 'events_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('recipes');
SELECT _recreate_policy('recipes', 'recipes_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('meal_plans');
SELECT _recreate_policy('meal_plans', 'meal_plans_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('lists');
SELECT _recreate_policy('lists', 'lists_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('devotionals');
SELECT _recreate_policy('devotionals', 'devotionals_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('budget_categories');
SELECT _recreate_policy('budget_categories', 'budget_categories_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('transactions');
SELECT _recreate_policy('transactions', 'transactions_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('ai_history');
SELECT _recreate_policy('ai_history', 'ai_history_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('chores');
SELECT _recreate_policy('chores', 'chores_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('chore_completions');
SELECT _recreate_policy('chore_completions', 'chore_completions_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('polls');
SELECT _recreate_policy('polls', 'polls_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('poll_votes');
SELECT _recreate_policy('poll_votes', 'poll_votes_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('external_calendars');
SELECT _recreate_policy('external_calendars', 'external_calendars_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('rewards');
SELECT _recreate_policy('rewards', 'rewards_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('reward_items');
SELECT _recreate_policy('reward_items', 'reward_items_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('reward_redemptions');
SELECT _recreate_policy('reward_redemptions', 'reward_redemptions_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('savings_goals');
SELECT _recreate_policy('savings_goals', 'savings_goals_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('prayer_wall');
SELECT _recreate_policy('prayer_wall', 'prayer_wall_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('reading_plans');
SELECT _recreate_policy('reading_plans', 'reading_plans_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('reading_plan_progress');
SELECT _recreate_policy('reading_plan_progress', 'reading_plan_progress_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('special_dates');
SELECT _recreate_policy('special_dates', 'special_dates_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('family_photos');
SELECT _recreate_policy('family_photos', 'family_photos_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('milestones');
SELECT _recreate_policy('milestones', 'milestones_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('saved_places');
SELECT _recreate_policy('saved_places', 'saved_places_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('user_locations');
SELECT _recreate_policy('user_locations', 'user_locations_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('health_records');
SELECT _recreate_policy('health_records', 'health_records_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

SELECT _drop_old_policies('messages');
SELECT _recreate_policy('messages', 'messages_all', 'ALL', 'auth_is_member_of(family_id)', 'auth_is_member_of(family_id)');

-- ---------------------------------------------------------------------------
-- Personal tables: user_id = auth.uid()
-- ---------------------------------------------------------------------------
SELECT _drop_old_policies('fitness');
SELECT _recreate_policy('fitness', 'fitness_all', 'ALL', 'user_id = auth.uid()::text', 'user_id = auth.uid()::text');

SELECT _drop_old_policies('fitness_plans');
SELECT _recreate_policy('fitness_plans', 'fitness_plans_all', 'ALL', 'user_id = auth.uid()::text', 'user_id = auth.uid()::text');

SELECT _drop_old_policies('daily_habits');
SELECT _recreate_policy('daily_habits', 'daily_habits_all', 'ALL', 'user_id = auth.uid()::text', 'user_id = auth.uid()::text');

SELECT _drop_old_policies('daily_habit_completions');
SELECT _recreate_policy('daily_habit_completions', 'daily_habit_completions_all', 'ALL',
  'user_id = auth.uid()::text OR EXISTS (SELECT 1 FROM daily_habits dh WHERE dh.id = daily_habit_completions.habit_id AND dh.user_id = auth.uid()::text)',
  'user_id = auth.uid()::text');

SELECT _drop_old_policies('period_cycles');
SELECT _recreate_policy('period_cycles', 'period_cycles_all', 'ALL', 'user_id = auth.uid()::text', 'user_id = auth.uid()::text');

SELECT _drop_old_policies('period_symptoms');
SELECT _recreate_policy('period_symptoms', 'period_symptoms_all', 'ALL', 'user_id = auth.uid()::text', 'user_id = auth.uid()::text');

-- ---------------------------------------------------------------------------
-- device_tokens & web_push_subscriptions
-- ---------------------------------------------------------------------------
SELECT _recreate_policy('device_tokens', 'Users manage own tokens', 'ALL', 'auth.uid()::text = user_id', 'auth.uid()::text = user_id');
SELECT _recreate_policy('web_push_subscriptions', 'Users manage own web push subscriptions', 'ALL', 'auth.uid()::text = user_id', 'auth.uid()::text = user_id');

-- ---------------------------------------------------------------------------
-- Clean up helper functions
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS _rename_col_if_exists(text, text, text);
DROP FUNCTION IF EXISTS _recreate_policy(text, text, text, text, text);
DROP FUNCTION IF EXISTS _drop_old_policies(text);
