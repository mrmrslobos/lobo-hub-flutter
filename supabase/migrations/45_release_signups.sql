-- Marketing site waitlist / app-release signups (public insert, no public read).
create table if not exists public.release_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text not null default 'marketing',
  created_at timestamptz not null default now(),
  constraint release_signups_email_unique unique (email)
);

create index if not exists release_signups_created_at_idx
  on public.release_signups (created_at desc);

alter table public.release_signups enable row level security;

drop policy if exists release_signups_anon_insert on public.release_signups;
create policy release_signups_anon_insert
  on public.release_signups
  for insert
  to anon, authenticated
  with check (true);

-- Service role / dashboard only for reads (no select policy for anon).
