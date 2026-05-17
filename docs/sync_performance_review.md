# Sync performance review — outbox drain and batching

## Problem statement

Family-wide outbound sync [`DatabaseService._syncToCloud`](../lib/services/database_service.dart) enqueues **one durable outbox record per logical row** for most tables (via `_outboxEnqueueFamilyUpserts` / `_outboxEnqueueUserUpserts`). A large local database yields **hundreds of queued upserts**.

Prior to optimization, [`SyncOutbox.drain`](../lib/services/sync_outbox.dart) issued **one PostgREST `upsert` per record** — correct for granular retry, but slower on wide tables and flaky networks because each row is a distinct HTTP round-trip.

---

## Implemented decision: batch contiguous upserts

`drain` now merges consecutive due rows that share:

- `OutboxOp.upsert`
- same `table`
- same resolved `onConflict` string (defaults to `'id'`)

into a single `SupabaseService.upsertTable` call with up to **`_maxBatchUpsert`** rows (currently **75**) per batch.

Deletes (`softDelete` / `hardDelete`) stay **single-row**: batching deletes would complicate attribution of RLS failures and is uncommon relative to bulk upserts during initial sync.

**Failure handling:** if a batch fails for any reason, the drain pass **falls back to per-row `_attempt`** for records still present in the queue, preserving the original backoff and error attribution behavior.

---

## Profiling checklist (staging / QA)

Recommended when validating a candidate release with a representative family dataset:

| Step | How |
|------|-----|
| Baseline timings | Toggle release vs debug; use device logs timestamps around outbound sync boundaries in `sync_provider` |
| Narrow culprit tables | Debug builds emit `[SyncOutbox] drain pass finished:` with aggregate counts [`pendingCountsByTable`](../lib/services/sync_outbox.dart) |
| Backend pressure | Monitor Supabase request rate and latency for PostgREST during full push |
| Post-change comparison | Repeat with same seed DB; expect fewer HTTP writes for outbound upserts when backlog is homogeneous by table |

For deeper CPU profiling than sync alone, Flutter DevTools **CPU profiler** captured during a scripted “save + wait for sync idle” automation run is sufficient for client-side hotspots.

---

## Future options (not yet implemented)

- **Dynamic `_maxBatchUpsert`** from row payload size estimation (prevent oversized bodies on wide JSON columns).
- **Batch non-adjacent** rows (same table) by sorting `due` by `(table, onConflict)` before drain — trades ordering guarantees for compaction; evaluate against concurrent enqueue assumptions.
- **Scope pushes** (`tableScope`) for cold-start hydration paths so low-priority tables do not block critical modules.

Cross-reference staged manual validation: [`staging_soak_checklist.md`](staging_soak_checklist.md).
