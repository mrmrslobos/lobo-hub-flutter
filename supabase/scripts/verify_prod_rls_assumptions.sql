-- Run in Supabase SQL Editor (Dashboard → SQL) against production after deploying migrations.
-- Expects zero rows in every "should be empty" SELECT. Policy counts may vary slightly if you add custom policies.

-- ── Schema: devotional_thoughts (migration 30) ─────────────────────────────
SELECT 'FAIL: devotional_thoughts missing note_kind' AS check_name
WHERE NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'devotional_thoughts'
    AND column_name = 'note_kind'
);

SELECT 'FAIL: unique (devotional_id,user_id,note_kind) missing' AS check_name
WHERE NOT EXISTS (
  SELECT 1 FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname = 'devotional_thoughts_devotional_user_kind_idx'
);

SELECT 'FAIL: old unique index still present' AS check_name
WHERE EXISTS (
  SELECT 1 FROM pg_indexes
  WHERE schemaname = 'public'
    AND indexname = 'devotional_thoughts_devotional_user_idx'
);

-- ── RLS enabled on sync-critical tables (sample) ────────────────────────────
SELECT tablename, 'FAIL: RLS not enabled' AS check_name
FROM pg_tables t
WHERE t.schemaname = 'public'
  AND t.tablename = ANY (ARRAY[
    'devotional_thoughts',
    'devotionals',
    'tasks',
    'lists',
    'messages',
    'family_members'
  ])
  AND NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = t.tablename
      AND c.relrowsecurity = true
  );

-- ── Policy presence (broader than zero is OK; zero means broken) ───────────
SELECT tablename, COUNT(*) AS policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = ANY (ARRAY[
    'devotional_thoughts',
    'devotionals',
    'tasks',
    'lists',
    'messages'
  ])
GROUP BY tablename
ORDER BY tablename;

-- ── Realtime publication (migration 28/29 pattern) ───────────────────────────
SELECT 'WARN: devotional_thoughts not in publication' AS check_name
WHERE NOT EXISTS (
  SELECT 1 FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime'
    AND schemaname = 'public'
    AND tablename = 'devotional_thoughts'
);
