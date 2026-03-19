-- budget_entries: store budget transactions (BudgetEntry) for sync across devices.
-- Safe to re-run.

-- amount/type/category/date/title/notes store encrypted strings (enc:v1:...)
CREATE TABLE IF NOT EXISTS budget_entries (
  id          text PRIMARY KEY,
  family_id   text NOT NULL,
  creator_id   text NOT NULL DEFAULT '',
  title       text NOT NULL,
  amount      text NOT NULL,
  type        text NOT NULL,
  category    text NOT NULL,
  date        text NOT NULL,
  notes       text,
  visibility  text NOT NULL DEFAULT 'FAMILY'
);

ALTER TABLE budget_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "budget_entries_family"
  ON budget_entries FOR ALL
  USING (true);
