# Cloud sync scope and persistence audit

Companion to [sync-repro-matrix.md](sync-repro-matrix.md). Summarizes patterns that affect **what reaches Supabase** and **what is written to Sembast**.

## Central paths

| Path | Persist Sembast | Push cloud |
|------|-------------------|------------|
| `AppProvider.saveAndSync` → `SyncProvider.saveAndSync` | Yes (`await DataProvider.updateDb` → `saveLocal`) before outbound sync | Scoped by `pushTableScope` or full default in `DatabaseService.syncToCloud` |
| `AppProvider.setDb` | **No** — memory only (`DataProvider.setDbMemory`) | No |
| `DatabaseService.saveAndSync` (e.g. auth signup) | Yes (`await saveLocal` then `syncToCloud`) | Full pipeline |

## Memory-only `setDb` (auth flow)

[`AppProvider.setDb`](lib/providers/app_provider.dart) intentionally skips disk during interactive Supabase sign-in to avoid racing an in-flight `reconcileCloud` (see comment on [`resumeAuthAfterSupabaseSignIn`](lib/providers/app_provider.dart)). Call sites: [`auth_screen.dart`](lib/screens/auth/auth_screen.dart). After login completes, persisted state should come from `DatabaseService.saveAndSync` / `reconcileCloud` / normal module saves.

## `pushTableScope` modules

Most screens pass explicit bundles from [`cloud_sync_scope.dart`](lib/config/cloud_sync_scope.dart) (e.g. `CloudSyncScope.mealsExtendedBundle`, `habitBundle`, `tasks` + `families`). Narrow scopes are intentional for bandwidth; if a single handler mutates **multiple** unrelated tables but only pushes one table key, other devices may lag until a broader sync or pull.

Notable narrow scopes worth verifying when debugging missing rows:

| Area | Typical scope |
|------|----------------|
| Tasks screen | `{tasks}`, `{families}` |
| Fitness | `{users}`, `{fitnessPlans}`, bundles |
| Period tracker | `{users}` on some paths |
| Calendar | `{events}` vs full `calendarBundle` |
| Copilot | Dynamic scopes from [`copilot_action_applier.dart`](lib/services/copilot_action_applier.dart) |

## Fire-and-forget `saveAndSync` (fixed)

Previously un-awaited calls risked navigating away before local persist + outbound sync finished. These were updated to `async`/`await`: chef recipe save and meal-plan delete / recipe delete in [`meals_screen.dart`](lib/screens/meals/meals_screen.dart), welcome banner dismiss on [`dashboard_screen.dart`](lib/screens/dashboard/dashboard_screen.dart), reading-plan completion on [`devotional_screen.dart`](lib/screens/devotional/devotional_screen.dart). Remaining call sites should prefer **`await provider.saveAndSync`** inside async handlers.

## Auth-side `updateDb`

[`AuthProvider.switchFamily`](lib/providers/auth_provider.dart) / [`updateFamily`](lib/providers/auth_provider.dart) use **`unawaited(updateDb)`** so synchronous notifier APIs stay sync; persistence still runs asynchronously. Prefer **`await updateDb`** inside `Future` methods when ordering matters (e.g. before `syncToCloud`).
