-- daily_habits: family members can SELECT shared habits; owners retain full CRUD.
-- daily_habit_completions: members can SELECT others' completions for shared habits only; writers own their rows only.

DROP POLICY IF EXISTS daily_habits_all ON public.daily_habits;

CREATE POLICY daily_habits_select ON public.daily_habits FOR SELECT TO public
  USING (
    (
      family_id IS NOT NULL
      AND public.auth_is_member_of(family_id)
      AND (
        user_id = (auth.uid())::text
        OR coalesce(is_shared, false)
      )
    )
    OR (
      family_id IS NULL
      AND user_id = (auth.uid())::text
    )
  );

CREATE POLICY daily_habits_insert ON public.daily_habits FOR INSERT TO public
  WITH CHECK (
    user_id = (auth.uid())::text
    AND (
      (family_id IS NOT NULL AND public.auth_is_member_of(family_id))
      OR family_id IS NULL
    )
  );

CREATE POLICY daily_habits_update ON public.daily_habits FOR UPDATE TO public
  USING (
    user_id = (auth.uid())::text
    AND (
      (family_id IS NOT NULL AND public.auth_is_member_of(family_id))
      OR family_id IS NULL
    )
  )
  WITH CHECK (
    user_id = (auth.uid())::text
    AND (
      (family_id IS NOT NULL AND public.auth_is_member_of(family_id))
      OR family_id IS NULL
    )
  );

CREATE POLICY daily_habits_delete ON public.daily_habits FOR DELETE TO public
  USING (
    user_id = (auth.uid())::text
    AND (
      (family_id IS NOT NULL AND public.auth_is_member_of(family_id))
      OR family_id IS NULL
    )
  );

DROP POLICY IF EXISTS daily_habit_completions_all ON public.daily_habit_completions;

CREATE POLICY daily_habit_completions_select ON public.daily_habit_completions FOR SELECT TO public
  USING (
    family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND (
      user_id = (auth.uid())::text
      OR EXISTS (
        SELECT 1
        FROM public.daily_habits h
        WHERE h.id = daily_habit_completions.habit_id
          AND h.family_id = daily_habit_completions.family_id
          AND coalesce(h.is_shared, false)
      )
    )
  );

CREATE POLICY daily_habit_completions_insert ON public.daily_habit_completions FOR INSERT TO public
  WITH CHECK (
    user_id = (auth.uid())::text
    AND family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND EXISTS (
      SELECT 1
      FROM public.daily_habits dh
      WHERE dh.id = habit_id
        AND dh.family_id = daily_habit_completions.family_id
    )
  );

CREATE POLICY daily_habit_completions_update ON public.daily_habit_completions FOR UPDATE TO public
  USING (
    user_id = (auth.uid())::text
    AND family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND EXISTS (
      SELECT 1
      FROM public.daily_habits dh
      WHERE dh.id = habit_id
        AND dh.family_id = daily_habit_completions.family_id
    )
  )
  WITH CHECK (
    user_id = (auth.uid())::text
    AND family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND EXISTS (
      SELECT 1
      FROM public.daily_habits dh
      WHERE dh.id = habit_id
        AND dh.family_id = daily_habit_completions.family_id
    )
  );

CREATE POLICY daily_habit_completions_delete ON public.daily_habit_completions FOR DELETE TO public
  USING (
    user_id = (auth.uid())::text
    AND family_id IS NOT NULL
    AND public.auth_is_member_of(family_id)
    AND EXISTS (
      SELECT 1
      FROM public.daily_habits dh
      WHERE dh.id = habit_id
        AND dh.family_id = daily_habit_completions.family_id
    )
  );
