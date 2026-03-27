-- Pantry staples, activity audit log, wellness check-ins, chore rotation, household role

create table if not exists pantry_items (
  id text primary key,
  family_id text not null,
  name text not null,
  quantity text,
  unit text,
  updated_at text not null
);

create table if not exists family_activity_logs (
  id text primary key,
  family_id text not null,
  actor_user_id text not null,
  action text not null,
  detail text,
  related_user_id text,
  created_at text not null
);

create table if not exists wellness_check_ins (
  id text primary key,
  family_id text not null,
  user_id text not null,
  mood text not null,
  note text,
  day text not null,
  created_at text not null
);

alter table family_members add column if not exists household_role text;

alter table chores add column if not exists rotation_enabled boolean not null default false;
alter table chores add column if not exists rotation_cursor integer not null default 0;

-- RLS (match existing permissive pattern)
do $$
declare
  t text;
begin
  foreach t in array array[
    'pantry_items',
    'family_activity_logs',
    'wellness_check_ins'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "%s_rw_anon" on %I', t, t);
    execute format('drop policy if exists "%s_rw_auth" on %I', t, t);
    execute format('create policy "%s_rw_auth" on %I for all to authenticated using (true) with check (true)', t, t);
    execute format('drop policy if exists "%s_ro_anon" on %I', t, t);
    execute format('create policy "%s_ro_anon" on %I for select to anon using (true)', t, t);
  end loop;
end $$;
