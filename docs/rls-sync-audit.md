# RLS vs app sync audit (Phase 2)

Quick reference for family-scoped tables. **RLS is source of truth** for what Supabase accepts; the app should match or be stricter in UI.

| Table | SELECT | INSERT/UPDATE/DELETE | App notes |
|-------|--------|----------------------|-----------|
| `lists` | Family member | Any member can update (mig 40); delete creator/owner (mig 33) | `syncListsNow` after edits |
| `pantry_items` | Family member | Any member (mig 41) | Pushed via `mealsExtendedBundle` |
| `recipes` | Family member | Insert: creator; update/delete: any member (mig 42) | Meal hub edit open to family |
| `fitness_plans` | Own user + family read if `family_id` set (mig 42) | Own user only | UI still shows own plans |
| `tasks`, `messages`, `chores` | Family member | Per-table policies | Phase 1 immediate push |
| `users` | Auth policies | Profile row | Realtime per member id + `notifyFamilyScopedChange` |

When a save succeeds locally but fails in cloud, check **Sync error banner** and Postgres logs for `row-level security`.
