-- Per-user RSVP for family calendar events (stored as user id arrays).
alter table events add column if not exists rsvp_yes_ids jsonb not null default '[]'::jsonb;
alter table events add column if not exists rsvp_no_ids jsonb not null default '[]'::jsonb;
alter table events add column if not exists rsvp_maybe_ids jsonb not null default '[]'::jsonb;
