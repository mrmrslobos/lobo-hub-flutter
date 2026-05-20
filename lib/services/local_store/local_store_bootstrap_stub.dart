import 'local_persistence_store.dart';
import 'sembast_local_store.dart';

/// Web / unsupported — Sembast IndexedDB (`LocalSembastStore`).
Future<LocalPersistenceStore> bootstrapLocalPersistenceStore() async {
  return SembastLocalStore();
}
