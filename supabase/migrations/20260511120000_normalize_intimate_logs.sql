-- Normalize intimate_logs to snake_case + add updated_at for sync.
-- The table was created with camelCase column names (userId, familyId, createdAt)
-- which breaks the project convention and forces per-table special-cases in the
-- Flutter client. This migration renames them in place; the client falls back
-- to the new names after deploy.
--
-- Idempotent: each RENAME guards on the source column existing.

DO $m$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'intimate_logs' AND column_name = 'userId'
  ) THEN
    ALTER TABLE public.intimate_logs RENAME COLUMN "userId" TO user_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'intimate_logs' AND column_name = 'familyId'
  ) THEN
    ALTER TABLE public.intimate_logs RENAME COLUMN "familyId" TO family_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'intimate_logs' AND column_name = 'createdAt'
  ) THEN
    ALTER TABLE public.intimate_logs RENAME COLUMN "createdAt" TO created_at;
  END IF;
END
$m$;

ALTER TABLE public.intimate_logs
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
