import '../../models/models.dart';
import '../local_sembast_store.dart';
import 'local_persistence_store.dart';

/// Delegates to [LocalSembastStore] — used on web and as `--dart-define=LOCAL_STORE=sembast` escape hatch on native.
class SembastLocalStore implements LocalPersistenceStore {
  @override
  Future<bool> hasStoredAppDb() => LocalSembastStore.hasStoredAppDb();

  @override
  Future<AppDB> readAppDb() => LocalSembastStore.readAppDb();

  @override
  Future<void> writeAppDb(AppDB db) => LocalSembastStore.writeAppDb(db);

  @override
  Future<void> readTombstonesInto(Set<String> sink) =>
      LocalSembastStore.readTombstonesInto(sink);

  @override
  Future<void> writeTombstones(Set<String> keys) =>
      LocalSembastStore.writeTombstones(keys);

  @override
  Future<Map<String, String>> readCursors() =>
      LocalSembastStore.readCursors();

  @override
  Future<void> writeCursors(Map<String, String> cursors) =>
      LocalSembastStore.writeCursors(cursors);

  @override
  Future<List<Map<String, dynamic>>> readOutbox() =>
      LocalSembastStore.readOutbox();

  @override
  Future<void> writeOutbox(List<Map<String, dynamic>> records) =>
      LocalSembastStore.writeOutbox(records);

  @override
  Future<void> clearAppRecords() => LocalSembastStore.clearAppRecords();

  @override
  Future<void> deletePhysicalDatabase() =>
      LocalSembastStore.deletePhysicalDatabase();
}
