# Huddle — brand and naming

## Customer-facing vs internal

| Audience | Name | Notes |
|----------|------|--------|
| App stores, UI, marketing | **Huddle** | Single public product name. Use `AppConfig.appName` in code for user-visible strings. |
| Repository, package, dev docs | **LoboHub** | `pubspec.yaml` package name `lobohub`; folder `lobo-hub-flutter`. Mention in AGENTS/README for developers only. |

Do not show “LoboHub” or “lobohub” in the app UI.

## Voice

- **Family-first:** we talk about *your family*, *family members*, and what's shared or private.
- **Plain language:** say “saved to your account” / “synced across your devices” instead of “cloud” or vendor names where possible.
- **“Home”** is optional shorthand for the shared family space in billing or data-deletion flows only (e.g. “delete your family’s data from our servers”). Prefer **family** in onboarding and settings.

## Glossary (UI copy)

| Term | Use |
|------|-----|
| Family | The people on one subscription / invite code. |
| Family members | People list and roles (replaces “manage members” as the primary heading). |
| Shared / with your family | Visibility that matches `Visibility.FAMILY` in code. |
| Private | Only you (or the creator) can see it. |
| Essentials | Former “Base” plan — core modules without AI. |
| AI / AI family plan | Paid tiers; spell out in subscription screen, not internal enum names. |

## Module naming

Module titles live in `lib/config/module_config.dart` and should match the navigation drawer. Prefer **outcome-oriented** labels (e.g. “Shopping lists”, “Reading & faith”) over internal route names.

## Changing the product name

1. Update `AppConfig.appName` / `appShortName` / `appDescription`.
2. Store listings and OAuth/deep links may need separate updates (`appBundleId`, URLs in `AppConfig`).
3. Replace any stray hardcoded `'Huddle'` strings with `AppConfig.appName` when you find them.
