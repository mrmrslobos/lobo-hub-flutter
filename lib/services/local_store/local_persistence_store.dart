import '../../models/models.dart';

/// Backend-agnostic contract matching [LocalSembastStore] semantics.
abstract class LocalPersistenceStore {
  Future<bool> hasStoredAppDb();

  Future<AppDB> readAppDb();

  Future<void> writeAppDb(AppDB db);

  Future<void> readTombstonesInto(Set<String> sink);

  Future<void> writeTombstones(Set<String> keys);

  Future<Map<String, String>> readCursors();

  Future<void> writeCursors(Map<String, String> cursors);

  Future<List<Map<String, dynamic>>> readOutbox();

  Future<void> writeOutbox(List<Map<String, dynamic>> records);

  /// Clears AppDB payloads, tombstones, cursors, outbox, marker (logout / DB reset).
  Future<void> clearAppRecords();

  /// Deletes the physical database file and closes handles (destructive wipe).
  Future<void> deletePhysicalDatabase();
}
