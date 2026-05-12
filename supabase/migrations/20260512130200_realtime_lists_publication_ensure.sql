-- Ensure family shopping lists propagate via Postgres Realtime across environments
-- where `lists` might be missing from the publication (staging/fork drift).
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.lists;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;
