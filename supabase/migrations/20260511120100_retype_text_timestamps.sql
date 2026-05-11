-- user_locations.updated_at and health_records.updated_at were stored as text,
-- which prevents server-side ordering and .gte() filters from working
-- (lexicographic compare ≠ chronological compare). Convert to timestamptz.
--
-- We tolerate the existing text being either empty, an ISO-8601 string, or an
-- unparseable value: NULLIF '' → null, otherwise cast via timestamptz, and
-- fall back to now() on parse failure so the migration never blocks on bad data.

DO $m$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user_locations', 'health_records']
  LOOP
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = t
        AND column_name = 'updated_at'
        AND data_type = 'text'
    ) THEN
      EXECUTE format($q$
        ALTER TABLE public.%I
        ALTER COLUMN updated_at TYPE timestamptz
        USING (
          CASE
            WHEN updated_at IS NULL OR updated_at = '' THEN now()
            ELSE
              COALESCE(
                (NULLIF(updated_at, '')::timestamptz),
                now()
              )
          END
        )
      $q$, t);

      EXECUTE format('ALTER TABLE public.%I ALTER COLUMN updated_at SET DEFAULT now()', t);
      EXECUTE format('ALTER TABLE public.%I ALTER COLUMN updated_at SET NOT NULL', t);
    END IF;
  END LOOP;
END
$m$;
