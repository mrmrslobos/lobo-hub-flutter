-- Phase 3 list_items: legacy `lists.items` JSON can resurrect deleted lines if
-- clients ever read it. Normalized rows live in list_items; clear stale JSON.
UPDATE public.lists
SET items = '[]'::jsonb,
    updated_at = GREATEST(updated_at, now())
WHERE items IS DISTINCT FROM '[]'::jsonb
  AND deleted_at IS NULL;
