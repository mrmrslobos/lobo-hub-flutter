-- Normalized shopping-list rows (one row per item). Safe to re-run.

CREATE TABLE IF NOT EXISTS public.list_items (
  id text PRIMARY KEY,
  list_id text NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  family_id text NOT NULL,
  text text NOT NULL DEFAULT ''::text,
  quantity text,
  checked boolean NOT NULL DEFAULT false,
  notes text,
  ai_category text,
  sort_order integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS list_items_list_id_idx
  ON public.list_items (list_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS list_items_family_alive_idx
  ON public.list_items (family_id)
  WHERE deleted_at IS NULL;

ALTER TABLE public.list_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "list_items_select" ON public.list_items;
CREATE POLICY "list_items_select" ON public.list_items
  FOR SELECT USING (public.auth_is_member_of(family_id));

DROP POLICY IF EXISTS "list_items_insert" ON public.list_items;
CREATE POLICY "list_items_insert" ON public.list_items
  FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));

DROP POLICY IF EXISTS "list_items_update" ON public.list_items;
CREATE POLICY "list_items_update" ON public.list_items
  FOR UPDATE
  USING (public.auth_is_member_of(family_id))
  WITH CHECK (public.auth_is_member_of(family_id));

DROP POLICY IF EXISTS "list_items_delete" ON public.list_items;
CREATE POLICY "list_items_delete" ON public.list_items
  FOR DELETE USING (public.auth_is_member_of(family_id));

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.list_items;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
