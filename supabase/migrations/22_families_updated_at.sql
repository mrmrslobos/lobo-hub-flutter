-- Last-write-wins for family row merges (settings, task folders, etc.)
alter table families add column if not exists updated_at timestamptz not null default now();
