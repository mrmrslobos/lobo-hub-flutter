-- period_cycles / period_symptoms: owner CRUD; partner read-only when owner nominates viewer in users.settings.period_share_with_user_id

DROP POLICY IF EXISTS period_cycles_all ON public.period_cycles;

CREATE POLICY period_cycles_select_owner ON public.period_cycles FOR SELECT TO public
  USING (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

CREATE POLICY period_cycles_select_partner ON public.period_cycles FOR SELECT TO public
  USING (
    public.auth_is_member_of(family_id)
    AND EXISTS (
      SELECT 1
      FROM public.users owner_row
      WHERE owner_row.id = period_cycles.user_id
        AND trim(coalesce(owner_row.settings->>'period_share_with_user_id', '')) = (auth.uid())::text
    )
  );

CREATE POLICY period_cycles_insert ON public.period_cycles FOR INSERT TO public
  WITH CHECK (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

CREATE POLICY period_cycles_update ON public.period_cycles FOR UPDATE TO public
  USING (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

CREATE POLICY period_cycles_delete ON public.period_cycles FOR DELETE TO public
  USING (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

DROP POLICY IF EXISTS period_symptoms_all ON public.period_symptoms;

CREATE POLICY period_symptoms_select_owner ON public.period_symptoms FOR SELECT TO public
  USING (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

CREATE POLICY period_symptoms_select_partner ON public.period_symptoms FOR SELECT TO public
  USING (
    public.auth_is_member_of(family_id)
    AND EXISTS (
      SELECT 1
      FROM public.users owner_row
      WHERE owner_row.id = period_symptoms.user_id
        AND trim(coalesce(owner_row.settings->>'period_share_with_user_id', '')) = (auth.uid())::text
    )
  );

CREATE POLICY period_symptoms_insert ON public.period_symptoms FOR INSERT TO public
  WITH CHECK (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

CREATE POLICY period_symptoms_update ON public.period_symptoms FOR UPDATE TO public
  USING (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  )
  WITH CHECK (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );

CREATE POLICY period_symptoms_delete ON public.period_symptoms FOR DELETE TO public
  USING (
    user_id = (auth.uid())::text
    AND public.auth_is_member_of(family_id)
  );
