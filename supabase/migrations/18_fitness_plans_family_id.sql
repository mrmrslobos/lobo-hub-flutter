-- Optional: scope fitness plans by family for sync (user_id still primary owner)
alter table fitness_plans add column if not exists family_id text;
