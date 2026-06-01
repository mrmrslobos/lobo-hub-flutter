import 'local_persistence_store.dart';
import 'local_store_bootstrap.dart';

LocalPersistenceStore? _singleton;

/// Single [LocalPersistenceStore] for the process (matches prior static Sembast layout).
Future<LocalPersistenceStore> resolvedLocalPersistence() async {
  _singleton ??= await bootstrapLocalPersistenceStore();
  return _singleton!;
}

/// After [LocalPersistenceStore.deletePhysicalDatabase]; next [resolvedLocalPersistence] re-bootstraps.
void resetResolvedLocalPersistence() => _singleton = null;
