-- Referential integrity: family_members.family_id → families.id
-- Skips if orphan membership rows exist (fix in SQL editor, then re-apply or add manually).
-- ON DELETE CASCADE removes membership rows when a family row is deleted.

DO $body$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'family_members'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'families'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'family_members_family_id_fkey'
  ) THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE NOT EXISTS (SELECT 1 FROM public.families f WHERE f.id = fm.family_id)
  ) THEN
    RAISE NOTICE
      'Skipping family_members_family_id_fkey: orphaned family_id values exist; delete or repoint them, then add the FK.';
    RETURN;
  END IF;

  ALTER TABLE public.family_members
    ADD CONSTRAINT family_members_family_id_fkey
    FOREIGN KEY (family_id) REFERENCES public.families(id) ON DELETE CASCADE;
END
$body$ LANGUAGE plpgsql;
