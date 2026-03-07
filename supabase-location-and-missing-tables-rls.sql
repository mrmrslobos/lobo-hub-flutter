-- ============================================================
-- RLS policies for tables that were missing from the original
-- supabase-rls-migration.sql:
--   user_locations, saved_places, special_dates,
--   family_photos, milestones, health_records, messages
--
-- Run this in the Supabase SQL editor (or via supabase db push).
-- ============================================================

-- ── user_locations ───────────────────────────────────────────
-- Any family member can read everyone's location in their family.
-- Only the owning user can write their own row.

ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_locations_select" ON user_locations;
CREATE POLICY "user_locations_select" ON user_locations FOR SELECT
  USING (auth_is_member_of("familyId"));

DROP POLICY IF EXISTS "user_locations_insert" ON user_locations;
CREATE POLICY "user_locations_insert" ON user_locations FOR INSERT
  WITH CHECK (auth_is_member_of("familyId") AND "userId" = auth.uid()::text);

DROP POLICY IF EXISTS "user_locations_update" ON user_locations;
CREATE POLICY "user_locations_update" ON user_locations FOR UPDATE
  USING ("userId" = auth.uid()::text)
  WITH CHECK ("userId" = auth.uid()::text);

DROP POLICY IF EXISTS "user_locations_delete" ON user_locations;
CREATE POLICY "user_locations_delete" ON user_locations FOR DELETE
  USING ("userId" = auth.uid()::text);

-- ── saved_places ─────────────────────────────────────────────
-- Shared family resource — any member can read/write.

ALTER TABLE saved_places ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "saved_places_all" ON saved_places;
CREATE POLICY "saved_places_all" ON saved_places FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- ── special_dates ────────────────────────────────────────────

ALTER TABLE special_dates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "special_dates_all" ON special_dates;
CREATE POLICY "special_dates_all" ON special_dates FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- ── family_photos ────────────────────────────────────────────

ALTER TABLE family_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "family_photos_all" ON family_photos;
CREATE POLICY "family_photos_all" ON family_photos FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- ── milestones ───────────────────────────────────────────────

ALTER TABLE milestones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "milestones_all" ON milestones;
CREATE POLICY "milestones_all" ON milestones FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- ── health_records ───────────────────────────────────────────

ALTER TABLE health_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "health_records_all" ON health_records;
CREATE POLICY "health_records_all" ON health_records FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));

-- ── messages (chat) ──────────────────────────────────────────

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_all" ON messages;
CREATE POLICY "messages_all" ON messages FOR ALL
  USING (auth_is_member_of("familyId"))
  WITH CHECK (auth_is_member_of("familyId"));
