-- 1) Marketing waitlist (migration 45 was never applied to production).
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

-- 2) Backfill trial metadata for existing families.
update public.families
set trial_start_date = coalesce(
  trial_start_date,
  case
    when created_at is null then now()
    else created_at::timestamptz
  end
)
where trial_start_date is null;

-- subscription_tier is guarded by families_protect_subscription_tier (P0).
select set_config('huddle.subscription_tier_sync', '1', true);
update public.families
set subscription_tier = 'trial'
where subscription_tier is null;

-- 3) Service-role RPC for RevenueCat webhooks (bypasses member auth check).
create or replace function public.sync_family_subscription_tier_system(
  p_family_id text,
  p_tier text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_family_id is null or p_family_id = '' then
    raise exception 'invalid family id';
  end if;
  if p_tier is null or p_tier = '' then
    raise exception 'invalid tier';
  end if;
  if p_tier not in ('trial', 'base', 'ai', 'ai_family') then
    raise exception 'invalid tier value';
  end if;

  perform set_config('huddle.subscription_tier_sync', '1', true);
  update public.families
  set subscription_tier = p_tier,
      updated_at = now()
  where id = p_family_id;
end;
$$;

revoke all on function public.sync_family_subscription_tier_system(text, text) from public;
grant execute on function public.sync_family_subscription_tier_system(text, text) to service_role;
