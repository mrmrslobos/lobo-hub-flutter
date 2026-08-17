# RLS vs app sync audit (Phase 2)

Quick reference for family-scoped tables. **RLS is source of truth** for what Supabase accepts; the app should match or be stricter in UI.

| Table | SELECT | INSERT/UPDATE/DELETE | App notes |
|-------|--------|----------------------|-----------|
| `lists` | Family member | Any member can update (mig 40); delete creator/owner (mig 33) | List **metadata** only (`items` empty in cloud) |
| `list_items` | Family member | Any member CRUD (mig 43) | Per-line realtime; `syncListItemsNow` on check/edit |
| `pantry_items` | Family member | Any member (mig 41) | Pushed via `mealsExtendedBundle` |
| `recipes` | Family member | Insert: creator; update/delete: any member (mig 42) | Meal hub edit open to family |
| `fitness_plans` | Own user + family read if `family_id` set (mig 42) | Own user only | UI still shows own plans |
| `tasks`, `messages`, `chores` | Family member | Per-table policies | Phase 1 immediate push |
| `users` | Auth policies | Profile row | Realtime per member id + `notifyFamilyScopedChange` |

When a save succeeds locally but fails in cloud, check **Sync error banner** and Postgres logs for `row-level security`.

## Incremental realtime (Phase 3)

Postgres changes on these tables are merged into local `AppDB` immediately via `DatabaseService.applyRealtimeRowChange` (no debounced full reconcile):

`tasks`, `lists`, `list_items`, `messages`, `chores`, `chore_completions`, `polls`, `poll_votes`, `events`, `external_calendars`, `users`, `recipes`, `meal_plans`, `prayer_wall`, `daily_habits`, `daily_habit_completions`, `budget_categories`, `budget_entries`, `transactions`, `reward_items`, `reward_redemptions`, `pantry_items`, `devotionals`, `devotional_thoughts`, `savings_goals`, `rewards`, `special_dates`, `family_photos`, `milestones`, `reading_plans`, `reading_plan_progress`, `health_records`, `period_cycles`, `period_symptoms`, `wellness_check_ins`, `family_activity_logs`, `saved_places`, `family_members`, `exercise_prs`, `workout_sessions`, `workout_exercises`, `workout_sets`, `fitness`, `fitness_plans`, `fitness_logs`, `ai_history`, `user_locations`

**Still debounced pull only:** foundational tables (`families`, `family_members` profile bootstrap edge cases) and any table not in the publication list above.

Other tables still use debounced pull. If parsing fails, the client falls back to a normal scoped/full pull. The app bar sync icon shows a **bolt** briefly after a live patch.
