/// Suppresses self-echo from Supabase Postgres realtime.
///
/// Every row we send via `SupabaseService.upsertTable` will round-trip back
/// as a postgres-changes broadcast on the same channel this device subscribes
/// to. Without filtering, every local write triggers a full reconcile pull —
/// wasted bandwidth, latency, and rebuild churn.
///
/// We record `(table, id, updated_at_ms)` at push time. The realtime callback
/// asks `isSelfEcho` before scheduling a pull; matching entries are ignored.
/// Entries auto-expire so a never-pushed-back write never blocks a real one.
class SyncEchoTracker {
  SyncEchoTracker._();

  static final Map<String, int> _writes = <String, int>{}; // "table:id" → updated_at ms
  static const Duration _ttl = Duration(seconds: 8);
  static int _lastGcMs = 0;

  static String _key(String table, String id) => '$table:$id';

  static void record(String table, String id, DateTime updatedAt) {
    if (id.isEmpty) return;
    _writes[_key(table, id)] = updatedAt.millisecondsSinceEpoch;
    _gcIfNeeded();
  }

  /// Returns true if `(table, id, updated_at)` matches a recently-pushed row.
  /// Matches are consumed so a later real change to the same row still pulls.
  static bool isSelfEcho(String table, String id, DateTime updatedAt) {
    if (id.isEmpty) return false;
    final key = _key(table, id);
    final ts = _writes[key];
    if (ts == null) return false;
    if (ts == updatedAt.millisecondsSinceEpoch) {
      _writes.remove(key);
      return true;
    }
    // Window check: timestamps within ±2s also count (clock skew + Postgres
    // re-stamping triggers can shift a few ms).
    if ((ts - updatedAt.millisecondsSinceEpoch).abs() <= 2000) {
      _writes.remove(key);
      return true;
    }
    return false;
  }

  static void _gcIfNeeded() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastGcMs < 1000) return;
    _lastGcMs = now;
    final cutoff = now - _ttl.inMilliseconds;
    _writes.removeWhere((_, ts) => ts < cutoff);
  }

  static void clear() => _writes.clear();
}
