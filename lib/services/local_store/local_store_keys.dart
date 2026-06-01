/// Shared keys across Sembast and Drift KV mirror (parity with [LocalSembastStore]).
abstract final class LocalStoreKeys {
  static const driftMarkerKey = '_huddle_drift_blob_v1';
  static const sembastMarkerKey = '_huddle_sem_marker_v1';
  static const tombstoneKey = '_huddle_merge_tombstones';
  static const cursorsKey = '_huddle_sync_cursors';
  static const outboxKey = '_huddle_sync_outbox';
}
