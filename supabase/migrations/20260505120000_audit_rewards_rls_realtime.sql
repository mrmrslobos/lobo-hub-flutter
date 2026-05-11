-- Applied to production via Supabase MCP (Familyhub / vinumlekpmddtbfkojkd).
-- Rewards table, schema fixes for realtime filters, RLS hardening, publication updates.

CREATE TABLE IF NOT EXISTS public.rewards (
  id text PRIMARY KEY,
  family_id text NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  title text NOT NULL,
  point_cost integer NOT NULL DEFAULT 0,
  description text,
  redeemed_by jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rewards_all ON public.rewards;
CREATE POLICY rewards_all ON public.rewards
  FOR ALL TO public
  USING (public.auth_is_member_of(family_id))
  WITH CHECK (public.auth_is_member_of(family_id));

ALTER PUBLICATION supabase_realtime ADD TABLE public.rewards;

ALTER TABLE public.fitness ADD COLUMN IF NOT EXISTS family_id text REFERENCES public.families(id) ON DELETE SET NULL;
UPDATE public.fitness f
SET family_id = (
  SELECT fm.family_id FROM public.family_members fm
  WHERE fm.user_id = f.user_id ORDER BY fm.family_id LIMIT 1
)
WHERE f.family_id IS NULL;

ALTER TABLE public.daily_habit_completions ADD COLUMN IF NOT EXISTS family_id text REFERENCES public.families(id) ON DELETE CASCADE;
UPDATE public.daily_habit_completions c
SET family_id = dh.family_id
FROM public.daily_habits dh
WHERE dh.id = c.habit_id AND c.family_id IS NULL;

ALTER TABLE public.workout_exercises ADD COLUMN IF NOT EXISTS exercise_db_id text;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS settings jsonb;

DROP POLICY IF EXISTS families_rw_anon ON public.families;
DROP POLICY IF EXISTS family_members_rw_anon ON public.family_members;
DROP POLICY IF EXISTS users_rw_anon ON public.users;
DROP POLICY IF EXISTS daily_habit_completions_rw_anon ON public.daily_habit_completions;
DROP POLICY IF EXISTS budget_entries_family ON public.budget_entries;
DROP POLICY IF EXISTS family_activity_logs_ro_anon ON public.family_activity_logs;
DROP POLICY IF EXISTS family_activity_logs_rw_auth ON public.family_activity_logs;
DROP POLICY IF EXISTS wellness_check_ins_ro_anon ON public.wellness_check_ins;
DROP POLICY IF EXISTS wellness_check_ins_rw_auth ON public.wellness_check_ins;
DROP POLICY IF EXISTS exercise_prs_ro_anon ON public.exercise_prs;
DROP POLICY IF EXISTS exercise_prs_rw_auth ON public.exercise_prs;

DROP POLICY IF EXISTS fitness_all ON public.fitness;
CREATE POLICY fitness_all ON public.fitness FOR ALL TO public
  USING (
    user_id = (auth.uid())::text
    AND (family_id IS NULL OR public.auth_is_member_of(family_id))
  )
  WITH CHECK (
    user_id = (auth.uid())::text
    AND (family_id IS NULL OR public.auth_is_member_of(family_id))
  );

DROP POLICY IF EXISTS daily_habit_completions_all ON public.daily_habit_completions;
CREATE POLICY daily_habit_completions_all ON public.daily_habit_completions FOR ALL TO public
  USING (
    user_id = (auth.uid())::text
    AND family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.daily_habits dh
        WHERE dh.id = habit_id AND dh.family_id = daily_habit_completions.family_id
      )
    )
  )
  WITH CHECK (
    user_id = (auth.uid())::text
    AND family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.daily_habits dh
        WHERE dh.id = habit_id AND dh.family_id = daily_habit_completions.family_id
      )
    )
  );

CREATE POLICY budget_entries_all ON public.budget_entries FOR ALL TO public
  USING (public.auth_is_member_of(family_id))
  WITH CHECK (public.auth_is_member_of(family_id));

CREATE POLICY family_activity_logs_select ON public.family_activity_logs FOR SELECT TO public
  USING (public.auth_is_member_of(family_id));
CREATE POLICY family_activity_logs_insert ON public.family_activity_logs FOR INSERT TO public
  WITH CHECK (
    public.auth_is_member_of(family_id)
    AND actor_user_id = (auth.uid())::text
  );
CREATE POLICY family_activity_logs_update ON public.family_activity_logs FOR UPDATE TO public
  USING (public.auth_is_member_of(family_id))
  WITH CHECK (public.auth_is_member_of(family_id));
CREATE POLICY family_activity_logs_delete ON public.family_activity_logs FOR DELETE TO public
  USING (
    public.auth_is_member_of(family_id)
    AND actor_user_id = (auth.uid())::text
  );

CREATE POLICY wellness_check_ins_select ON public.wellness_check_ins FOR SELECT TO public
  USING (public.auth_is_member_of(family_id));
CREATE POLICY wellness_check_ins_insert ON public.wellness_check_ins FOR INSERT TO public
  WITH CHECK (
    public.auth_is_member_of(family_id)
    AND user_id = (auth.uid())::text
  );
CREATE POLICY wellness_check_ins_update ON public.wellness_check_ins FOR UPDATE TO public
  USING (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text)
  WITH CHECK (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text);
CREATE POLICY wellness_check_ins_delete ON public.wellness_check_ins FOR DELETE TO public
  USING (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text);

CREATE POLICY exercise_prs_select ON public.exercise_prs FOR SELECT TO public
  USING (public.auth_is_member_of(family_id));
CREATE POLICY exercise_prs_insert ON public.exercise_prs FOR INSERT TO public
  WITH CHECK (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text);
CREATE POLICY exercise_prs_update ON public.exercise_prs FOR UPDATE TO public
  USING (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text)
  WITH CHECK (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text);
CREATE POLICY exercise_prs_delete ON public.exercise_prs FOR DELETE TO public
  USING (public.auth_is_member_of(family_id) AND user_id = (auth.uid())::text);

ALTER PUBLICATION supabase_realtime ADD TABLE public.daily_habit_completions;
