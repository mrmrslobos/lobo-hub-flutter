-- Per-user exercise PRs, workout Health sync marker, recipe macros, meal repeat/leftovers

create table if not exists exercise_prs (
  id text primary key,
  user_id text not null,
  family_id text not null,
  exercise_key text not null,
  best_volume numeric,
  best_weight text,
  best_reps integer,
  session_id text,
  exercise_id text,
  achieved_at text not null,
  created_at text not null
);

alter table exercise_prs enable row level security;
drop policy if exists "exercise_prs_rw_auth" on exercise_prs;
create policy "exercise_prs_rw_auth" on exercise_prs for all to authenticated using (true) with check (true);
drop policy if exists "exercise_prs_ro_anon" on exercise_prs;
create policy "exercise_prs_ro_anon" on exercise_prs for select to anon using (true);

alter table workout_sessions add column if not exists health_synced_at text;

alter table recipes add column if not exists kcal integer;
alter table recipes add column if not exists protein_g numeric;
alter table recipes add column if not exists carbs_g numeric;
alter table recipes add column if not exists fat_g numeric;
alter table recipes add column if not exists fiber_g numeric;

alter table meal_plans add column if not exists repeat_rule text;
alter table meal_plans add column if not exists source_meal_plan_id text;
alter table meal_plans add column if not exists leftover_meal_plan_id text;
