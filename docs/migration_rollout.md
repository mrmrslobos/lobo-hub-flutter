# Migration rollout

Apply `supabase/migrations/*.sql` in **numeric filename order** on the target project (staging first, then production).

## General rules

1. **Backup or branch** production data before destructive changes.
2. Run migrations in a **transaction** when the file is written as idempotent single-file deploys; the Supabase SQL editor runs each script as submitted.
3. After deploy, run [`../supabase/scripts/verify_prod_rls_assumptions.sql`](../supabase/scripts/verify_prod_rls_assumptions.sql) (or your own checklist) and fix any reported rows.

## Migration 28–30 (realtime + devotionals)

- **28** (`28_realtime_publication_expand.sql`): expands the `supabase_realtime` publication. No app binary requirement; ensures new tables can emit realtime events.
- **29** (`29_devotional_thoughts.sql`): adds `devotional_thoughts` and related RLS. **Client expectation:** app builds that still use the old unique key `(devotional_id, user_id)` for thoughts must be upgraded before or in sync with this migration to avoid upsert conflicts.
- **30** (`30_devotional_thoughts_note_kind.sql`): adds `note_kind` and replaces the unique constraint with `(devotional_id, user_id, note_kind)`.

### Minimum app behaviour after migration 30

- Local ↔ cloud sync for Devotional thoughts must use **`onConflict: devotional_id,user_id,note_kind`** for `devotional_thoughts` (see `lib/services/database_service.dart`).
- **Ship order:** deploy migration **30** only when production clients are on a version that includes that sync path (or be prepared for failed upserts / 409s on older builds).

## Rolling back

Migrations are not auto-reversible. To undo a change, author a **new** forward migration that restores the prior shape (columns, indexes, policies), never delete applied migration files from version control.
