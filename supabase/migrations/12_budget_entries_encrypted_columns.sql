-- budget_entries: amount (and other encrypted fields) must be text to store
-- client-side encrypted ciphertext ("enc:v1:<iv>:<ciphertext>").
-- Safe to re-run.

DO $$ BEGIN
  ALTER TABLE budget_entries ALTER COLUMN amount TYPE text USING amount::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
