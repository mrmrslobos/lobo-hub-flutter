-- Destructive: delete all app data for one family (owner-only). Used by Settings → Delete all data (cloud).

CREATE OR REPLACE FUNCTION public.delete_family_cloud_data(p_family_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner text;
  member_uids text[];
BEGIN
  IF p_family_id IS NULL OR trim(p_family_id) = '' THEN
    RAISE EXCEPTION 'invalid family id';
  END IF;

  SELECT owner_id INTO v_owner FROM families WHERE id = p_family_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'family not found';
  END IF;
  IF v_owner IS DISTINCT FROM auth.uid()::text THEN
    RAISE EXCEPTION 'only the home owner can delete cloud data';
  END IF;

  SELECT coalesce(array_agg(user_id), '{}') INTO member_uids
  FROM family_members WHERE family_id = p_family_id;

  -- Workouts (sets → exercises → sessions)
  DELETE FROM workout_sets WHERE family_id = p_family_id;
  DELETE FROM workout_exercises WHERE family_id = p_family_id;
  DELETE FROM workout_sessions WHERE family_id = p_family_id;
  DELETE FROM exercise_prs WHERE family_id = p_family_id;

  DELETE FROM fitness_logs WHERE family_id = p_family_id;
  DELETE FROM fitness WHERE user_id = ANY(member_uids);
  DELETE FROM fitness_plans WHERE user_id = ANY(member_uids);

  DELETE FROM daily_habit_completions WHERE habit_id IN (
    SELECT id FROM daily_habits WHERE family_id = p_family_id OR user_id = ANY(member_uids)
  );
  DELETE FROM daily_habits WHERE family_id = p_family_id OR user_id = ANY(member_uids);

  DELETE FROM ai_history WHERE family_id = p_family_id;

  DELETE FROM reading_plan_progress WHERE family_id = p_family_id
    OR plan_id IN (SELECT id FROM reading_plans WHERE family_id = p_family_id);
  DELETE FROM reading_plans WHERE family_id = p_family_id;

  DELETE FROM device_tokens WHERE family_id = p_family_id;
  DELETE FROM web_push_subscriptions WHERE family_id = p_family_id;

  DELETE FROM chore_completions WHERE family_id = p_family_id;
  DELETE FROM poll_votes WHERE family_id = p_family_id;
  DELETE FROM reward_redemptions WHERE family_id = p_family_id;
  DELETE FROM period_cycles WHERE family_id = p_family_id;
  DELETE FROM period_symptoms WHERE family_id = p_family_id;

  DELETE FROM tasks WHERE family_id = p_family_id;
  DELETE FROM events WHERE family_id = p_family_id;
  DELETE FROM recipes WHERE family_id = p_family_id;
  DELETE FROM meal_plans WHERE family_id = p_family_id;
  DELETE FROM lists WHERE family_id = p_family_id;
  DELETE FROM devotionals WHERE family_id = p_family_id;
  DELETE FROM budget_categories WHERE family_id = p_family_id;
  DELETE FROM budget_entries WHERE family_id = p_family_id;
  DELETE FROM transactions WHERE family_id = p_family_id;
  DELETE FROM chores WHERE family_id = p_family_id;
  DELETE FROM polls WHERE family_id = p_family_id;
  DELETE FROM reward_items WHERE family_id = p_family_id;
  DELETE FROM savings_goals WHERE family_id = p_family_id;
  DELETE FROM prayer_wall WHERE family_id = p_family_id;
  DELETE FROM external_calendars WHERE family_id = p_family_id;
  DELETE FROM rewards WHERE family_id = p_family_id;
  DELETE FROM special_dates WHERE family_id = p_family_id;
  DELETE FROM family_photos WHERE family_id = p_family_id;
  DELETE FROM milestones WHERE family_id = p_family_id;
  DELETE FROM saved_places WHERE family_id = p_family_id;
  DELETE FROM messages WHERE family_id = p_family_id;
  DELETE FROM health_records WHERE family_id = p_family_id;
  DELETE FROM user_locations WHERE family_id = p_family_id;
  DELETE FROM pantry_items WHERE family_id = p_family_id;
  DELETE FROM family_activity_logs WHERE family_id = p_family_id;
  DELETE FROM wellness_check_ins WHERE family_id = p_family_id;

  DELETE FROM family_members WHERE family_id = p_family_id;
  DELETE FROM families WHERE id = p_family_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_family_cloud_data(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_family_cloud_data(text) TO authenticated;
