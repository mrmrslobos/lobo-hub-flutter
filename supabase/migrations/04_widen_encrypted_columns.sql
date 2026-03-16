-- ============================================================
-- Widen columns that will now hold encrypted ciphertext.
--
-- Previously these were numeric or jsonb; after client-side
-- encryption they store "enc:v1:<iv>:<ciphertext>" strings.
-- Alter them to text so encrypted values can be stored.
-- ============================================================

-- transactions.amount  (numeric → text)
DO $$ BEGIN
  ALTER TABLE transactions ALTER COLUMN amount TYPE text USING amount::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

-- transactions.description  (already text — no change needed)

-- budget_categories.limit  (numeric → text)
DO $$ BEGIN
  ALTER TABLE budget_categories ALTER COLUMN "limit" TYPE text USING "limit"::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

-- budget_categories.name  (already text — no change needed)

-- savings_goals.target_amount  (numeric → text)
DO $$ BEGIN
  ALTER TABLE savings_goals ALTER COLUMN target_amount TYPE text USING target_amount::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

-- savings_goals.saved_amount  (numeric → text)
DO $$ BEGIN
  ALTER TABLE savings_goals ALTER COLUMN saved_amount TYPE text USING saved_amount::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

-- savings_goals.title  (already text — no change needed)

-- health_records: blood_type, allergies, medications, conditions,
-- immunizations, emergency_contacts are jsonb → text
DO $$ BEGIN
  ALTER TABLE health_records ALTER COLUMN allergies TYPE text USING allergies::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE health_records ALTER COLUMN medications TYPE text USING medications::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE health_records ALTER COLUMN conditions TYPE text USING conditions::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE health_records ALTER COLUMN immunizations TYPE text USING immunizations::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE health_records ALTER COLUMN emergency_contacts TYPE text USING emergency_contacts::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

-- period_symptoms: symptoms (jsonb → text), pain_level (int → text)
DO $$ BEGIN
  ALTER TABLE period_symptoms ALTER COLUMN symptoms TYPE text USING symptoms::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
DO $$ BEGIN
  ALTER TABLE period_symptoms ALTER COLUMN pain_level TYPE text USING pain_level::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;

-- messages: reactions (jsonb → text)
DO $$ BEGIN
  ALTER TABLE messages ALTER COLUMN reactions TYPE text USING reactions::text;
EXCEPTION WHEN undefined_column OR undefined_table THEN NULL;
END $$;
