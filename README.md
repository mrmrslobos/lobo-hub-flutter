# Huddle (LoboHub)

Flutter mobile app for family life — tasks, calendar, meals, budget, chat, and many more modules. Cloud sync and auth use **Supabase** (PostgreSQL, Row Level Security, Edge Functions).

## Prerequisites

- **Flutter ≥ 3.35** (Dart ≥ 3.9) — see `pubspec.yaml` and [`AGENTS.md`](AGENTS.md) for SDK notes.
- For **web**: the `web/` folder is in the repo; if it is missing, run `flutter create --platforms web .`

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

## Deploy web to Vercel (GitHub Actions)

Production and PR **preview** builds run in CI and upload the static **`build/web`** output to Vercel — Android and iOS builds are unchanged.

1. Create a [Vercel](https://vercel.com) project (empty or linked to this repo; the Action pushes artifacts via the CLI).
2. In the GitHub repo, add **Actions** secrets:

   | Secret | Where to get it |
   |--------|------------------|
   | `VERCEL_TOKEN` | Vercel → Account → **Tokens** |
   | `VERCEL_ORG_ID` | Project → **Settings** → General → *Team / Personal ID* (`team_…`) |
   | `VERCEL_PROJECT_ID` | Same page → *Project ID* (`prj_…`) |
   | `SUPABASE_URL` | Optional; same value as `--dart-define` for production web |
   | `SUPABASE_ANON_KEY` | Optional; pair with `SUPABASE_URL` |

   If `SUPABASE_URL` / `SUPABASE_ANON_KEY` are omitted, the web bundle is built **without** Supabase (local-only mode), same as a local run without defines.

3. Push to **`main`** for a **production** deploy, or open a **pull request** against `main` for a **preview** URL (fork PRs skip deploy because secrets are unavailable).

Workflow file: [`.github/workflows/deploy-web-vercel.yml`](.github/workflows/deploy-web-vercel.yml). SPA routing uses [`web/vercel.json`](web/vercel.json) (copied into `build/web` after each build).

## Repository layout

| Path | Purpose |
|------|---------|
| `.github/workflows/deploy-web-vercel.yml` | CI: `flutter build web` → Vercel |
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
