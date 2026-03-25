-- Envelope-style rollover + weekly vs monthly limit interpretation
alter table budget_categories add column if not exists rollover_enabled boolean not null default false;
alter table budget_categories add column if not exists limit_period text not null default 'monthly';
