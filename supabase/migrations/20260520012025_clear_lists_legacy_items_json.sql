-- Items now live in list_items; clear legacy JSON blobs on list headers.
-- Safe to re-run.

UPDATE public.lists
SET items = '[]'::jsonb,
    updated_at = now()
WHERE jsonb_array_length(items) > 0;
