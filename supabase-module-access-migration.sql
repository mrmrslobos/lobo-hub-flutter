-- Migration: add moduleAccess column to family_members
-- Run this once against your existing Supabase project.
-- Safe to re-run (IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).

ALTER TABLE family_members
  ADD COLUMN IF NOT EXISTS "moduleAccess" jsonb;
