-- Task reminder channel + server-side reminder queue for email/SMS/voice dispatch.

alter table tasks add column if not exists reminder_channel text;

create table if not exists reminder_jobs (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references families(id) on delete cascade,
  user_id uuid not null,
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
        and fm.user_id = auth.uid()
    )
  );

create policy "Members insert reminder jobs for their family"
  on reminder_jobs for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from family_members fm
      where fm.family_id = reminder_jobs.family_id
        and fm.user_id = auth.uid()
    )
  );
