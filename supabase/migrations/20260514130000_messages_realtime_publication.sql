-- Ensure family chat is in the Realtime publication (required for postgres_changes on `messages`).
-- Idempotent; see also supabase/schema.sql and migration 28_realtime_publication_expand.sql.
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE messages; EXCEPTION WHEN OTHERS THEN NULL; END $$;
