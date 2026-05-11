-- RLS performance cleanup (Supabase advisors: auth_rls_initplan, multiple_permissive_policies)
--
-- Pass 0: Merge stacked PERMISSIVE SELECT policies on period_* (partner + owner) into one policy
--         so Postgres does not evaluate both predicates for every row.
-- Pass 1: Recreate every public policy whose expressions reference auth.uid() so that bare
--         auth.uid() calls become scalar subqueries ((SELECT auth.uid())), which PostgreSQL
--         hoists to an InitPlan (single evaluation per statement, not per row).
--
-- Idempotent: DROP POLICY IF EXISTS + CREATE POLICY. Runs in one transaction.

-- ── Pass 0: period tracker SELECT consolidation ───────────────────────────

DROP POLICY IF EXISTS period_cycles_select_owner ON public.period_cycles;
DROP POLICY IF EXISTS period_cycles_select_partner ON public.period_cycles;

CREATE POLICY period_cycles_select ON public.period_cycles
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (
    (
      (user_id = ((SELECT auth.uid()))::text)
      AND auth_is_member_of(family_id)
    )
    OR (
      auth_is_member_of(family_id)
      AND EXISTS (
        SELECT 1
        FROM public.users owner_row
        WHERE owner_row.id = period_cycles.user_id
          AND TRIM(BOTH FROM COALESCE(owner_row.settings->>'period_share_with_user_id', ''))
            = ((SELECT auth.uid()))::text
      )
    )
  );

DROP POLICY IF EXISTS period_symptoms_select_owner ON public.period_symptoms;
DROP POLICY IF EXISTS period_symptoms_select_partner ON public.period_symptoms;

CREATE POLICY period_symptoms_select ON public.period_symptoms
  AS PERMISSIVE
  FOR SELECT
  TO public
  USING (
    (
      (user_id = ((SELECT auth.uid()))::text)
      AND auth_is_member_of(family_id)
    )
    OR (
      auth_is_member_of(family_id)
      AND EXISTS (
        SELECT 1
        FROM public.users owner_row
        WHERE owner_row.id = period_symptoms.user_id
          AND TRIM(BOTH FROM COALESCE(owner_row.settings->>'period_share_with_user_id', ''))
            = ((SELECT auth.uid()))::text
      )
    )
  );

-- ── Pass 1: InitPlan rewrite for all policies mentioning auth.uid() ──────────

DO $body$
DECLARE
  pol RECORD;
  nqual TEXT;
  nchk TEXT;
  role_list TEXT;
  permissive_clause TEXT;
BEGIN
  FOR pol IN
    SELECT *
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        POSITION('auth.uid()' IN COALESCE(qual, '')) > 0
        OR POSITION('auth.uid()' IN COALESCE(with_check, '')) > 0
      )
    ORDER BY tablename, policyname
  LOOP
    nqual := pol.qual;
    nchk := pol.with_check;

    IF nqual IS NOT NULL THEN
      -- Longest / most specific replacements first
      nqual := REPLACE(nqual, '(auth.uid())::text', '((SELECT auth.uid()))::text');
      nqual := REPLACE(nqual, 'auth.uid() IS NOT NULL', '((SELECT auth.uid()) IS NOT NULL)');
      nqual := REPLACE(nqual, '(( SELECT auth.uid() AS uid))', '((SELECT auth.uid()))');
    END IF;

    IF nchk IS NOT NULL THEN
      nchk := REPLACE(nchk, '(auth.uid())::text', '((SELECT auth.uid()))::text');
      nchk := REPLACE(nchk, 'auth.uid() IS NOT NULL', '((SELECT auth.uid()) IS NOT NULL)');
      nchk := REPLACE(nchk, '(( SELECT auth.uid() AS uid))', '((SELECT auth.uid()))');
    END IF;

    role_list := (
      SELECT string_agg(quote_ident(r::text), ', ')
      FROM unnest(pol.roles) AS r
    );

    permissive_clause := CASE pol.permissive
      WHEN 'RESTRICTIVE' THEN 'AS RESTRICTIVE'
      ELSE 'AS PERMISSIVE'
    END;

    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON %I.%I',
      pol.policyname,
      pol.schemaname,
      pol.tablename
    );

    IF pol.cmd = 'SELECT' THEN
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I %s FOR SELECT TO %s USING (%s)',
        pol.policyname,
        pol.schemaname,
        pol.tablename,
        permissive_clause,
        role_list,
        nqual
      );
    ELSIF pol.cmd = 'INSERT' THEN
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I %s FOR INSERT TO %s WITH CHECK (%s)',
        pol.policyname,
        pol.schemaname,
        pol.tablename,
        permissive_clause,
        role_list,
        nchk
      );
    ELSIF pol.cmd = 'UPDATE' THEN
      IF nchk IS NULL OR btrim(nchk) = '' THEN
        EXECUTE format(
          'CREATE POLICY %I ON %I.%I %s FOR UPDATE TO %s USING (%s)',
          pol.policyname,
          pol.schemaname,
          pol.tablename,
          permissive_clause,
          role_list,
          nqual
        );
      ELSE
        EXECUTE format(
          'CREATE POLICY %I ON %I.%I %s FOR UPDATE TO %s USING (%s) WITH CHECK (%s)',
          pol.policyname,
          pol.schemaname,
          pol.tablename,
          permissive_clause,
          role_list,
          nqual,
          nchk
        );
      END IF;
    ELSIF pol.cmd = 'DELETE' THEN
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I %s FOR DELETE TO %s USING (%s)',
        pol.policyname,
        pol.schemaname,
        pol.tablename,
        permissive_clause,
        role_list,
        nqual
      );
    ELSIF pol.cmd = 'ALL' THEN
      IF nqual IS NOT NULL AND (nchk IS NULL OR btrim(nchk) = '') THEN
        EXECUTE format(
          'CREATE POLICY %I ON %I.%I %s FOR ALL TO %s USING (%s)',
          pol.policyname,
          pol.schemaname,
          pol.tablename,
          permissive_clause,
          role_list,
          nqual
        );
      ELSIF (nqual IS NULL OR btrim(nqual) = '') AND nchk IS NOT NULL THEN
        EXECUTE format(
          'CREATE POLICY %I ON %I.%I %s FOR ALL TO %s WITH CHECK (%s)',
          pol.policyname,
          pol.schemaname,
          pol.tablename,
          permissive_clause,
          role_list,
          nchk
        );
      ELSE
        EXECUTE format(
          'CREATE POLICY %I ON %I.%I %s FOR ALL TO %s USING (%s) WITH CHECK (%s)',
          pol.policyname,
          pol.schemaname,
          pol.tablename,
          permissive_clause,
          role_list,
          nqual,
          nchk
        );
      END IF;
    END IF;

  END LOOP;
END $body$;
