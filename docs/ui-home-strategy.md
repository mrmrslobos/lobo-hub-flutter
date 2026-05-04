# Home & navigation UI strategy (Phase 0)

This document anchors implementation for dashboard density, “glance vs deep” modes, and module discovery.

## Entry points (first screen after session)

| Entry | Intent |
|--------|--------|
| Cold start → `/` (dashboard) | Glance: today, shortcuts, recents. |
| Return from background → last route | Restores deep work. |
| Notification deep link (FCM) | Task-specific screen after sync. |
| Drawer / Jump to / All tools | Explicit discovery. |

## Home = “Today + your shortcuts” (hero story)

- **Primary job:** answer “What’s going on for our family *now* and *soon*?” in one scroll, without scanning the full module catalog.
- **Secondary:** one tap into Copilot, essentials, or **All tools** for everything else.
- **Deferred from above-the-fold priority:** long AI suggestion lists, full monthly story, and second-layer stats—available, but not competing with the hero.

## Surfaces and priority (highest first)

1. Greeting + **today snapshot** (tasks due / next event in one read).
2. Plan chip + trial banner (business-critical).
3. **At most one** “education” block per session: Get started **or** Try AI, not both when both would show.
4. Family announcement.
5. **Quick actions** (essentials) + **All tools** (full catalog).
6. **Recents** (last visited modules).
7. Deeper home sections (AI suggestions, monthly summary, stats, etc.) in lighter or collapsed patterns.

## Implementation references

- `essentialModules` + `isModulePathEnabled` — home shortcuts and filters.
- `AllTools` bottom sheet — full module list filtered by `Family.enabledModules`.
- `RecentRoutesService` — persisted last visits; not shown for disabled modules.
- `ModuleRouteRecency` in `app.dart` shell — records non-dashboard routes on navigation.
- **Pinned modules** — `User.settings['pinned_module_paths']` (max 6), merged into the home quick row via `resolvedDashboardQuickPaths` in `user_module_pins.dart`; toggled from **All tools** (star). Syncs with `CloudSyncScope.users` when online.

## Open questions (product)

- Pinned favorites per user (v2).
- “Today” vs “This week” as alternate hero (A/B or setting).
