# Staging soak checklist (pre–general availability)

Run this against a **staging** Supabase project (or prod with a constrained test account), with **Crashlytics** and **RevenueCat** sandbox keys as appropriate.

## Environment

| Item | Staging expectation |
|------|---------------------|
| App build | Release or profile builds on real devices |
| Backend | Latest migrations applied; RLS enforced |
| Telemetry | Crashlytics collection enabled |
| Monetization | RC sandbox entitlement matches test products |

---

## Sync and offline

Run each item on **two physical devices**, same family:

1. Cold start logged in → wait for sync complete (app bar sync state).
2. Create task on device A → within 60s appears on device B after pull/resume (or realtime).
3. Edit same list item on both devices within 30s → no data loss visible after eventual consistency.
4. **Offline A**: airplane mode on → create/edit multiple entities → airplane off → uploads complete without duplicates.
5. **Background**: repeat large edit, send app to background 2–3 minutes, resume → observe outbox clears (tooltip / logs), no phantom errors stuck.

Documentation of sync behavior lives in repo at [`database_service.dart`](../lib/services/database_service.dart) and [`sync_outbox.dart`](../lib/services/sync_outbox.dart).

---

## Auth and lifecycle

| Check | Pass criteria |
|-------|----------------|
| Logout → login | Correct family restored |
| Wrong password | User-facing message, no crash |
| Kill app mid-sync | Restart recovers cleanly |
| **Upgrade path**: install older build (`n−1`), use app, overlay install `n` | DB migrates opens home |

---

## Monitoring during soak

| Signal | Where to look |
|--------|----------------|
| **RLS denials / 5xx** | Supabase logs / API dashboards |
| **Client crashes** | Firebase Crashlytics (non-fatal + fatals per release) |
| **Upsert backlog** | Debug logs `[SyncOutbox]` if testing debug builds (`pendingCountsByTable`) |
| **Entitlement drift** | RevenueCat customer view vs in-app gated screens |

Targets (tune per org):

- Crash-free sessions threshold for release candidate meets your policy.
- Sync integration job green on upstream PRs (`integration-tests.yml`).

---

## Sign-off block

Copy for release notes owner:

```
Staging soak date: _________
Branches / versions: _________ / _________

Sync two-device checklist: □ Complete
Offline/online checklist: □ Complete
Logout/login / upgrade path: □ Complete
Crashlytics (no regressions observed): □ Verified
Supabase error rate nominal: □ Verified
Decision: □ Go for rollout   □ Fix required: _______________
Signed: _________
```
