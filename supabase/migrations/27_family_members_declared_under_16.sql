-- Self-declaration for AI Family household sizing (synced with app; not age-verified).
alter table family_members add column if not exists declared_under_16 boolean not null default false;
