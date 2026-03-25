-- Multiple AI fitness plans per user (history); stable row id = plan_id UUID
alter table fitness_plans add column if not exists plan_id text;

-- Backfill: one legacy row per user used id = user_id_family_id; leave plan_id null (client uses user_id+created_at as key)
