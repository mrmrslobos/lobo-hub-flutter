# Cloud sync — reproduction checklist

Use this when reporting sporadic sync issues so we can distinguish **local persistence**, **push scope**, **deferred pulls**, and **realtime gaps**.

## Environment

| Question | Why it matters |
|----------|----------------|
| Platform (Chrome web, Safari web, Android, iOS, desktop) | Web uses Sembast on IndexedDB; mobile uses native storage. Multi-tab web can race on the same origin. |
| Single device or multiple devices / accounts | Confirms cross-device pull vs same-session merge. |
| Same family ID on both sides | Pulls are family-scoped; wrong family looks like “no sync.” |

## Timing and triggers

| Question | Why it matters |
|----------|----------------|
| Rough delay between writer saving and reader checking | Realtime is debounced (~450 ms); long outbound sync **defers** inbound pulls until push completes. |
| Was the reader app foreground or background | Resume refresh runs when last successful sync is **> 3 minutes** or after a sync error (`SyncProvider.resumeSyncStaleAfter`). |
| Writer and reader syncing at the same time | Concurrent outbound work queues `_deferredCloudPull`. |

## Recovery behavior

| Question | Why it matters |
|----------|----------------|
| Does **pull latest** (app bar sync) or pull-to-refresh fix it | If yes, likely realtime/backpressure rather than missing push. |
| Does killing and reopening the app lose **only** the last edit | Points to disk flush timing before Sembast completes (see awaited `updateDb` / `saveLocal`). |
| Does signing out and back in change behavior | Auth/reconcile overlap can desync memory vs disk during sign-in (see `AppProvider.resumeAuthAfterSupabaseSignIn`). |

## Scope

| Question | Why it matters |
|----------|----------------|
| Which module / data type (tasks, meals, AI history, etc.) | Some flows use narrow `pushTableScope`; others use `AppProvider.setDb` (memory-only, no disk). See [sync-scope-audit.md](sync-scope-audit.md). |

## Logs to capture (debug / profile runs)

Filter console for prefix **`[CloudSync]`** (structured sync telemetry). Note the time of the user action and whether **`deferred_pull`** or **`reconcile_error`** lines appear.
