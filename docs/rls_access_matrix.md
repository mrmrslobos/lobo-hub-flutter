# RLS access matrix (overview)

This document summarises **intent** for Row Level Security on Supabase. The real policies live in `supabase/migrations/`. Use [`../supabase/scripts/verify_prod_rls_assumptions.sql`](../supabase/scripts/verify_prod_rls_assumptions.sql) after deploys to catch obvious gaps (RLS off, missing columns, publication issues).

## Actor model

- **Authenticated user** via Supabase Auth (`auth.uid()`).
- **Family scoping:** most family data rows include `family_id`. Access is granted when the user is a **member** of that family (`family_members`), often with role checks for admin/owner-only operations.
- **User-scoped tables:** some rows are keyed by `user_id` (e.g. personal fitness metrics). RLS typically allows read/write only for `user_id = auth.uid()`, sometimes with family read visibility.

## Table groups (conceptual)

| Area | Tables (examples) | Policy idea |
|------|-------------------|-------------|
| Identity | `users`, `families`, `family_members` | Users update self; family row edits restricted to owners/admins; membership rows follow invite/join rules. |
| Tasks & lists | `tasks`, `lists` | Family members read/write within `family_id`. |
| Chat | `messages` | Family members; optional visibility / thread rules per migration. |
| Calendar | `events`, `external_calendars` | Family-scoped events; external calendar rows tied to linking user + family. |
| Devotionals | `devotionals`, `devotional_thoughts` | Family-visible devotionals; thoughts often scoped per user + `note_kind` (migration 30). |
| Media / places | `family_photos`, `milestones`, `saved_places`, `user_locations` | Family or user visibility depending on column semantics in migrations. |
| Money / rewards | `budget_*`, `transactions`, `reward_*`, `savings_goals`, `rewards` | Typically family members; sensitive operations may require admin. |
| Health / cycle | `health_records`, `period_cycles`, `period_symptoms` | Often owner-of-row or family policy per migration — verify before exposing to minors’ accounts. |
| AI / activity | `ai_history`, `family_activity_logs` | User or family scoped; avoid cross-family leakage. |

## Client responsibilities

- The Flutter app uses the **anon** key and relies on RLS; it must send correct `family_id` / `user_id` on inserts and updates.
- **Partial cloud pushes** (`pushTableScope` in `AppProvider.saveAndSync`) only limit which tables are upserted in a given call; they **do not** bypass RLS.

## When you change policies

1. Update migrations with explicit `DROP POLICY` / `CREATE POLICY` where needed.
2. Re-run the verify script and smoke-test: join family, second device, child account, and admin-only actions.
