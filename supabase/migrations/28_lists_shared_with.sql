-- Share-picker recipients for lists (synced with app ShoppingList.sharedWith).
alter table lists add column if not exists shared_with jsonb not null default '[]'::jsonb;
