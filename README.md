# Huddle (LoboHub)

Flutter mobile app for family life — tasks, calendar, meals, budget, chat, and many more modules. Cloud sync and auth use **Supabase** (PostgreSQL, Row Level Security, Edge Functions).

## Prerequisites

- **Flutter ≥ 3.35** (Dart ≥ 3.9) — see `pubspec.yaml` and [`AGENTS.md`](AGENTS.md) for SDK notes.
- For **web**: generate the platform folder once (it may be gitignored):

  ```bash
  flutter create --platforms web .
  ```

## Run locally

```bash
flutter pub get
flutter run
```

Run **without Supabase** (local-only / `SharedPreferences`): use your editor’s “Dev - no Supabase” launch config or omit `--dart-define` flags.

Run **with Supabase** (example):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

More detail: [`AGENTS.md`](AGENTS.md) (web port, RevenueCat `--dart-define`, Android/iOS build commands).

## Repository layout

| Path | Purpose |
|------|---------|
| `lib/` | Flutter app |
| `supabase/migrations/` | Postgres schema + RLS (apply in order) |
| `supabase/functions/` | Edge Functions (TypeScript / Deno) |
| `docs/migration_rollout.md` | Deployment order and client compatibility |
| `docs/rls_access_matrix.md` | High-level RLS expectations |

This repo does **not** use `npm run dev` or Vite; ignore any leftover references to an AI Studio / npm template in older snippets.

## Database / production checks

- Apply migrations in numeric order in the Supabase SQL editor or CLI.
- After production deploys, optional sanity checks: [`supabase/scripts/verify_prod_rls_assumptions.sql`](supabase/scripts/verify_prod_rls_assumptions.sql).

## Lint

```bash
flutter analyze
```

Pre-existing info-level warnings are expected unless you are tightening lint policy on purpose.
