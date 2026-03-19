-- Create the family-photos storage bucket if it does not exist.
-- Required for photo uploads; app uses bucket id 'family-photos'.
-- public = true so getPublicUrl() works without signed URLs; RLS still restricts who can upload/update/delete.
INSERT INTO storage.buckets (id, name, public)
VALUES ('family-photos', 'family-photos', true)
ON CONFLICT (id) DO NOTHING;

-- RLS: only family members can read/upload/update/delete objects in their family folder.
-- Path format: {family_id}/{photo_id}.{ext} — first segment is family_id.
DROP POLICY IF EXISTS "family_photos_select" ON storage.objects;
DROP POLICY IF EXISTS "family_photos_insert" ON storage.objects;
DROP POLICY IF EXISTS "family_photos_update" ON storage.objects;
DROP POLICY IF EXISTS "family_photos_delete" ON storage.objects;

CREATE POLICY "family_photos_select"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'family-photos'
  AND auth_is_member_of((storage.foldername(name))[1]::text)
);

CREATE POLICY "family_photos_insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'family-photos'
  AND auth_is_member_of((storage.foldername(name))[1]::text)
);

CREATE POLICY "family_photos_update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'family-photos'
  AND auth_is_member_of((storage.foldername(name))[1]::text)
)
WITH CHECK (
  bucket_id = 'family-photos'
  AND auth_is_member_of((storage.foldername(name))[1]::text)
);

CREATE POLICY "family_photos_delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'family-photos'
  AND auth_is_member_of((storage.foldername(name))[1]::text)
);
