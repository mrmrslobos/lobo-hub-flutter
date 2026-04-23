-- Stricter RLS for family_photos: prevent spoofed uploads and non-uploader deletes
-- while keeping UPDATE open to all members (reactions/caption flows use full-row updates).

CREATE OR REPLACE FUNCTION public.auth_is_family_owner(fid text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.families f
    WHERE f.id = fid AND f.owner_id = (SELECT auth.uid())::text
  );
$$;

DO $body$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'family_photos'
  ) THEN
    DROP POLICY IF EXISTS "family_photos_all" ON public.family_photos;

    DROP POLICY IF EXISTS "family_photos_select" ON public.family_photos;
    DROP POLICY IF EXISTS "family_photos_insert" ON public.family_photos;
    DROP POLICY IF EXISTS "family_photos_update" ON public.family_photos;
    DROP POLICY IF EXISTS "family_photos_delete" ON public.family_photos;

    CREATE POLICY "family_photos_select" ON public.family_photos
      FOR SELECT USING (public.auth_is_member_of(family_id));

    CREATE POLICY "family_photos_insert" ON public.family_photos
      FOR INSERT WITH CHECK (
        public.auth_is_member_of(family_id)
        AND uploader_id = (SELECT auth.uid())::text
      );

    CREATE POLICY "family_photos_update" ON public.family_photos
      FOR UPDATE USING (public.auth_is_member_of(family_id))
      WITH CHECK (public.auth_is_member_of(family_id));

    CREATE POLICY "family_photos_delete" ON public.family_photos
      FOR DELETE USING (
        public.auth_is_member_of(family_id)
        AND (
          uploader_id = (SELECT auth.uid())::text
          OR public.auth_is_family_owner(family_id)
        )
      );
  END IF;
END
$body$;
