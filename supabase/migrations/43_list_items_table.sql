-- Normalize shopping list line items into rows (Phase 3 lists).
-- Enables per-item realtime sync without whole-list JSON last-write-wins.

CREATE TABLE IF NOT EXISTS public.list_items (
  id          text PRIMARY KEY,
  list_id     text NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
  family_id   text NOT NULL,
  text        text NOT NULL DEFAULT '',
  quantity    text,
  checked     boolean NOT NULL DEFAULT false,
  notes       text,
  ai_category text,
  sort_order  integer NOT NULL DEFAULT 0,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);

CREATE INDEX IF NOT EXISTS list_items_list_id_idx
  ON public.list_items (list_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS list_items_family_alive_idx
  ON public.list_items (family_id)
  WHERE deleted_at IS NULL;

-- Backfill from legacy lists.items JSON (idempotent).
INSERT INTO public.list_items (
  id, list_id, family_id, text, quantity, checked, notes, ai_category, sort_order, updated_at
)
SELECT
  COALESCE(NULLIF(elem->>'id', ''), gen_random_uuid()::text),
  l.id,
  l.family_id,
  COALESCE(elem->>'text', elem->>'name', ''),
  NULLIF(elem->>'quantity', ''),
  COALESCE((elem->>'checked')::boolean, false),
  NULLIF(elem->>'notes', ''),
  NULLIF(elem->>'ai_category', ''),
  (ord - 1)::integer,
  COALESCE(l.updated_at, now())
FROM public.lists l
CROSS JOIN LATERAL jsonb_array_elements(
  CASE
    WHEN l.items IS NULL OR jsonb_typeof(l.items) <> 'array' THEN '[]'::jsonb
    ELSE l.items
  END
) WITH ORDINALITY AS t(elem, ord)
WHERE jsonb_array_length(
  CASE
    WHEN l.items IS NULL OR jsonb_typeof(l.items) <> 'array' THEN '[]'::jsonb
    ELSE l.items
  END
) > 0
ON CONFLICT (id) DO NOTHING;

-- RLS: any family member can manage items in their family.
ALTER TABLE public.list_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "list_items_select" ON public.list_items;
DROP POLICY IF EXISTS "list_items_insert" ON public.list_items;
DROP POLICY IF EXISTS "list_items_update" ON public.list_items;
DROP POLICY IF EXISTS "list_items_delete" ON public.list_items;

CREATE POLICY "list_items_select" ON public.list_items
  FOR SELECT USING (public.auth_is_member_of(family_id));

CREATE POLICY "list_items_insert" ON public.list_items
  FOR INSERT WITH CHECK (public.auth_is_member_of(family_id));

CREATE POLICY "list_items_update" ON public.list_items
  FOR UPDATE
  USING (public.auth_is_member_of(family_id))
  WITH CHECK (public.auth_is_member_of(family_id));

CREATE POLICY "list_items_delete" ON public.list_items
  FOR DELETE USING (public.auth_is_member_of(family_id));

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.list_items;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
