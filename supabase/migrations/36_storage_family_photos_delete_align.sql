-- Align storage.objects DELETE on bucket family-photos with public.family_photos RLS:
-- only the uploader of the matching row or the family owner may remove an object.
-- Path format (see SupabaseService.uploadPhoto): {family_id}/{photo_id}.{ext}
-- Family owners may still delete orphan objects in their folder (no matching row).

DO $body$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'family_photos'
  ) THEN
    RAISE NOTICE 'Skipping storage family_photos_delete tighten: public.family_photos not found.';
    RETURN;
  END IF;

  DROP POLICY IF EXISTS "family_photos_delete" ON storage.objects;

  CREATE POLICY "family_photos_delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'family-photos'
    AND public.auth_is_member_of((storage.foldername(name))[1]::text)
    AND (
      public.auth_is_family_owner((storage.foldername(name))[1]::text)
      OR EXISTS (
        SELECT 1
        FROM public.family_photos fp
        WHERE fp.family_id = (storage.foldername(name))[1]::text
          AND fp.id = split_part(split_part(name, '/', 2), '.', 1)
          AND fp.uploader_id = (SELECT auth.uid())::text
      )
    )
  );
END
$body$ LANGUAGE plpgsql;
