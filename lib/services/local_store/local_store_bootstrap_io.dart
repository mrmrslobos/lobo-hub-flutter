import 'package:flutter/foundation.dart';

import '../local_sembast_store.dart';
import 'drift_blob_local_store.dart';
import 'huddle_drift_database.dart';
import 'local_persistence_store.dart';
import 'sembast_local_store.dart';

/// Native: defaults to Drift Tier A + one-shot Sembast import.
///
/// Escape hatch: `--dart-define=LOCAL_STORE=sembast` keeps Sembast only.
///
/// Tier A SQLite file: see [HuddleDriftDb].
Future<LocalPersistenceStore> bootstrapLocalPersistenceStore() async {
  const mode = String.fromEnvironment('LOCAL_STORE', defaultValue: 'auto');
  if (mode == 'sembast') {
    debugPrint('[LocalStore] LOCAL_STORE=sembast — using Sembast (native)');
    return SembastLocalStore();
  }

  final drift = DriftBlobLocalStore(HuddleDriftDb.shared);

  if (await drift.hasStoredAppDb()) {
    return drift;
  }

  if (await LocalSembastStore.hasStoredAppDb()) {
    try {
      await migrateSembastToDriftOrThrow(drift);
      debugPrint('[LocalStore] Completed Sembast → Drift (Tier A) migration');
      return drift;
    } catch (e, st) {
      debugPrint('[LocalStore] Sembast migration failed, wiping partial Drift '
          'and falling back to Sembast: $e\n$st');
      await HuddleDriftDb.shutdownAndDeleteFile();
      return SembastLocalStore();
    }
  }

  return drift;
}
