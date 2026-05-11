-- Ensure WAL replication for fitness + reading plan progress live sync filters.
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.fitness; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.reading_plan_progress; EXCEPTION WHEN OTHERS THEN NULL; END $$;
