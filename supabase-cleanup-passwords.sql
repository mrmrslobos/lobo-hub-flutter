-- =============================================================================
-- Run this NOW in Supabase Dashboard → SQL Editor
-- Clears all plain-text passwords from the users table and drops the column.
-- =============================================================================

-- Step 1: Wipe all password values (even if column stays for safety first)
UPDATE users SET password = NULL WHERE password IS NOT NULL;

-- Step 2: Drop the column entirely so it can never be written again
ALTER TABLE users DROP COLUMN IF EXISTS password;

-- Done. Passwords are gone from Supabase.
-- The app code now also strips the password field from localStorage
-- before any sync, so it will never be written back.
