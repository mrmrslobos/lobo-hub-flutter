-- Task reminder channel + server-side reminder queue for email/SMS/voice dispatch.

alter table tasks add column if not exists reminder_channel text;

-- family_id / user_id are text to match public.families(id) and family_members (see migration 02).
create table if not exists reminder_jobs (
  id uuid primary key default gen_random_uuid(),
  family_id text not null references families(id) on delete cascade,
  user_id text not null,
  channel text not null check (channel in ('email','sms','voice')),
  scheduled_at timestamptz not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','sent','failed','cancelled')),
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique (idempotency_key)
);

create index if not exists reminder_jobs_pending_scheduled_idx
  on reminder_jobs (status, scheduled_at)
  where status = 'pending';

alter table reminder_jobs enable row level security;

create policy "Members read own family reminder jobs"
  on reminder_jobs for select
  using (
    exists (
      select 1 from family_members fm
      where fm.family_id = reminder_jobs.family_id
        and fm.user_id = auth.uid()::text
    )
  );

create policy "Members insert reminder jobs for their family"
  on reminder_jobs for insert
  with check (
    auth.uid()::text = user_id
    and exists (
      select 1 from family_members fm
      where fm.family_id = reminder_jobs.family_id
        and fm.user_id = auth.uid()::text
    )
  );
