-- Run in Supabase SQL Editor before applying FK / NOT NULL migrations.
-- Orphan rows listed here should be fixed (delete or repoint) or noted.

-- family_members.family_id with no matching families row (blocks FK in 37)
SELECT 'family_members → missing family' AS issue, fm.*
FROM public.family_members fm
WHERE NOT EXISTS (SELECT 1 FROM public.families f WHERE f.id = fm.family_id);

-- meal_plans.family_id with no matching family (blocks NOT NULL backfill in 38)
SELECT 'meal_plans → missing family' AS issue, mp.*
FROM public.meal_plans mp
WHERE NOT EXISTS (SELECT 1 FROM public.families f WHERE f.id = mp.family_id);
