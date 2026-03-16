-- =============================================================================
-- Migration Part 1: Rename all camelCase columns to snake_case
-- =============================================================================
-- Run this FIRST in the Supabase SQL Editor, then run Part 2.
-- Safe to re-run — catches errors if columns already renamed.
-- =============================================================================

-- families
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "ownerId" TO owner_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "joinCode" TO join_code; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "announcementAuthor" TO announcement_author; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "subscriptionTier" TO subscription_tier; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "enabledModules" TO enabled_modules; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "welcomeDismissed" TO welcome_dismissed; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "weeklyDigest" TO weekly_digest; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "weeklyDigestDay" TO weekly_digest_day; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "weeklyDigestHour" TO weekly_digest_hour; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "dailyDevotionalEnabled" TO daily_devotional_enabled; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "dailyDevotionalHour" TO daily_devotional_hour; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE families RENAME COLUMN "dailyDevotionalMinute" TO daily_devotional_minute; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- family_members
DO $a$ BEGIN ALTER TABLE family_members RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_members RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_members RENAME COLUMN "moduleAccess" TO module_access; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_members RENAME COLUMN "displayName" TO display_name; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- tasks
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "dueDate" TO due_date; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "dueTime" TO due_time; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "reminderMinutes" TO reminder_minutes; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "completedBy" TO completed_by; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE tasks RENAME COLUMN "updatedBy" TO updated_by; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- events
DO $a$ BEGIN ALTER TABLE events RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE events RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE events RENAME COLUMN "sharedWith" TO shared_with; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE events RENAME COLUMN "budgetEstimate" TO budget_estimate; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE events RENAME COLUMN "externalCalendarId" TO external_calendar_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE events RENAME COLUMN "externalUid" TO external_uid; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- recipes
DO $a$ BEGIN ALTER TABLE recipes RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- meal_plans
DO $a$ BEGIN ALTER TABLE meal_plans RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE meal_plans RENAME COLUMN "mealType" TO meal_type; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE meal_plans RENAME COLUMN "recipeId" TO recipe_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE meal_plans RENAME COLUMN "customMeal" TO custom_meal; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- lists
DO $a$ BEGIN ALTER TABLE lists RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE lists RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- devotionals
DO $a$ BEGIN ALTER TABLE devotionals RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE devotionals RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE devotionals RENAME COLUMN "reflectionPrompts" TO reflection_prompts; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE devotionals RENAME COLUMN "userPrayer" TO user_prayer; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE devotionals RENAME COLUMN "isFavorited" TO is_favorited; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- fitness
DO $a$ BEGIN ALTER TABLE fitness RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- fitness_plans
DO $a$ BEGIN ALTER TABLE fitness_plans RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE fitness_plans RENAME COLUMN "weeklyPlan" TO weekly_plan; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE fitness_plans RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- budget_categories
DO $a$ BEGIN ALTER TABLE budget_categories RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE budget_categories RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- transactions
DO $a$ BEGIN ALTER TABLE transactions RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE transactions RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE transactions RENAME COLUMN "categoryId" TO category_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- ai_history
DO $a$ BEGIN ALTER TABLE ai_history RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE ai_history RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE ai_history RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- daily_habits
DO $a$ BEGIN ALTER TABLE daily_habits RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habits RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habits RENAME COLUMN "isShared" TO is_shared; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habits RENAME COLUMN "targetValue" TO target_value; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habits RENAME COLUMN "targetUnit" TO target_unit; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habits RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- daily_habit_completions
DO $a$ BEGIN ALTER TABLE daily_habit_completions RENAME COLUMN "habitId" TO habit_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habit_completions RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE daily_habit_completions RENAME COLUMN "completedAt" TO completed_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- chores
DO $a$ BEGIN ALTER TABLE chores RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chores RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chores RENAME COLUMN "daysOfWeek" TO days_of_week; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chores RENAME COLUMN "requiresApproval" TO requires_approval; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chores RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- chore_completions
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "choreId" TO chore_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "completedAt" TO completed_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "approvalStatus" TO approval_status; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "approvedBy" TO approved_by; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE chore_completions RENAME COLUMN "approvedAt" TO approved_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- polls
DO $a$ BEGIN ALTER TABLE polls RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE polls RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE polls RENAME COLUMN "allowMultiple" TO allow_multiple; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE polls RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- poll_votes
DO $a$ BEGIN ALTER TABLE poll_votes RENAME COLUMN "pollId" TO poll_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE poll_votes RENAME COLUMN "optionId" TO option_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE poll_votes RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE poll_votes RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE poll_votes RENAME COLUMN "votedAt" TO voted_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- external_calendars
DO $a$ BEGIN ALTER TABLE external_calendars RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE external_calendars RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE external_calendars RENAME COLUMN "lastSynced" TO last_synced; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE external_calendars RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- rewards (may not exist)
DO $a$ BEGIN ALTER TABLE rewards RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE rewards RENAME COLUMN "pointCost" TO point_cost; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE rewards RENAME COLUMN "redeemedBy" TO redeemed_by; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- reward_items (may not exist)
DO $a$ BEGIN ALTER TABLE reward_items RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_items RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_items RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- reward_redemptions (may not exist)
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "rewardId" TO reward_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "rewardTitle" TO reward_title; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "requestedAt" TO requested_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "resolvedAt" TO resolved_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reward_redemptions RENAME COLUMN "resolvedBy" TO resolved_by; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- savings_goals
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "imageUrl" TO image_url; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "targetAmount" TO target_amount; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "savedAmount" TO saved_amount; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE savings_goals RENAME COLUMN "completedAt" TO completed_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- prayer_wall
DO $a$ BEGIN ALTER TABLE prayer_wall RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE prayer_wall RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE prayer_wall RENAME COLUMN "originalRequestId" TO original_request_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE prayer_wall RENAME COLUMN "prayedByIds" TO prayed_by_ids; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE prayer_wall RENAME COLUMN "answeredAt" TO answered_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- reading_plans
DO $a$ BEGIN ALTER TABLE reading_plans RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plans RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plans RENAME COLUMN "totalDays" TO total_days; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plans RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- reading_plan_progress
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "planId" TO plan_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "completedDays" TO completed_days; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "currentStreak" TO current_streak; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "longestStreak" TO longest_streak; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "startedAt" TO started_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE reading_plan_progress RENAME COLUMN "lastCompletedAt" TO last_completed_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- period_cycles
DO $a$ BEGIN ALTER TABLE period_cycles RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_cycles RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_cycles RENAME COLUMN "startDate" TO start_date; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_cycles RENAME COLUMN "endDate" TO end_date; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_cycles RENAME COLUMN "flowLevel" TO flow_level; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_cycles RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- period_symptoms
DO $a$ BEGIN ALTER TABLE period_symptoms RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_symptoms RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_symptoms RENAME COLUMN "painLevel" TO pain_level; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE period_symptoms RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- device_tokens
DO $a$ BEGIN ALTER TABLE device_tokens RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE device_tokens RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE device_tokens RENAME COLUMN "updatedAt" TO updated_at; EXCEPTION WHEN undefined_column THEN NULL; END $a$;

-- special_dates (may not exist)
DO $a$ BEGIN ALTER TABLE special_dates RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE special_dates RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE special_dates RENAME COLUMN "reminderDays" TO reminder_days; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE special_dates RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- family_photos (may not exist)
DO $a$ BEGIN ALTER TABLE family_photos RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_photos RENAME COLUMN "uploaderId" TO uploader_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_photos RENAME COLUMN "takenAt" TO taken_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_photos RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE family_photos RENAME COLUMN "milestoneId" TO milestone_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- milestones (may not exist)
DO $a$ BEGIN ALTER TABLE milestones RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE milestones RENAME COLUMN "childId" TO child_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE milestones RENAME COLUMN "photoIds" TO photo_ids; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE milestones RENAME COLUMN "ageLabel" TO age_label; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE milestones RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- saved_places (may not exist)
DO $a$ BEGIN ALTER TABLE saved_places RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE saved_places RENAME COLUMN "creatorId" TO creator_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE saved_places RENAME COLUMN "radiusMetres" TO radius_metres; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE saved_places RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- user_locations (may not exist)
DO $a$ BEGIN ALTER TABLE user_locations RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE user_locations RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE user_locations RENAME COLUMN "placeName" TO place_name; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE user_locations RENAME COLUMN "nearPlace" TO near_place; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE user_locations RENAME COLUMN "isSharing" TO is_sharing; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE user_locations RENAME COLUMN "updatedAt" TO updated_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- health_records (may not exist)
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "memberId" TO member_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "updatedBy" TO updated_by; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "bloodType" TO blood_type; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "emergencyContacts" TO emergency_contacts; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "doctorName" TO doctor_name; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "doctorPhone" TO doctor_phone; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "insuranceProvider" TO insurance_provider; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "insurancePolicyNumber" TO insurance_policy_number; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE health_records RENAME COLUMN "updatedAt" TO updated_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- messages (may not exist)
DO $a$ BEGIN ALTER TABLE messages RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE messages RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE messages RENAME COLUMN "replyToId" TO reply_to_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE messages RENAME COLUMN "editedAt" TO edited_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE messages RENAME COLUMN "createdAt" TO created_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;

-- web_push_subscriptions (may not exist)
DO $a$ BEGIN ALTER TABLE web_push_subscriptions RENAME COLUMN "userId" TO user_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE web_push_subscriptions RENAME COLUMN "familyId" TO family_id; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
DO $a$ BEGIN ALTER TABLE web_push_subscriptions RENAME COLUMN "updatedAt" TO updated_at; EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END $a$;
