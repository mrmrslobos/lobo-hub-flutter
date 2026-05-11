import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';

import '../models/models.dart';
import 'local_db_factory.dart';

/// File-backed (VM) / IndexedDB (web) local store for [AppDB].
///
/// Shards [AppDB.toJson] into separate Sembast records so we avoid one giant
/// SharedPreferences string and reduce peak memory / encode cost versus a
/// single monolithic JSON blob.
class LocalSembastStore {
  LocalSembastStore._();

  static const String _markerKey = '_huddle_sem_marker_v1';
  static const String _tombstoneKey = '_huddle_merge_tombstones';
  static const String _cursorsKey = '_huddle_sync_cursors';
  static const String _outboxKey = '_huddle_sync_outbox';

  static Database? _db;
  static String? _storagePathOrName;

  static final StoreRef<String, dynamic> _store = StoreRef<String, dynamic>.main();

  static Future<Database> _database() async {
    if (_db != null) return _db!;
    final factory = localDatabaseFactory;
    if (kIsWeb) {
      _storagePathOrName = 'huddle_app_v1';
      _db = await factory.openDatabase(_storagePathOrName!);
      return _db!;
    }
    final dir = await getApplicationDocumentsDirectory();
    _storagePathOrName = p.join(dir.path, 'huddle_app_v1.db');
    _db = await factory.openDatabase(_storagePathOrName!);
    return _db!;
  }

  /// True once we have successfully written the sharded Sembast layout.
  static Future<bool> hasStoredAppDb() async {
    final db = await _database();
    final marker = await _store.record(_markerKey).get(db);
    return marker != null;
  }

  /// Loads the full snapshot (all shards must exist after a successful save).
  static Future<AppDB> readAppDb() async {
    final database = await _database();
    final template = AppDB.empty().toJson();
    final keys = template.keys.toList();
    final snapshots = await _store.records(keys).getSnapshots(database);
    final map = <String, dynamic>{};
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      final snap = i < snapshots.length ? snapshots[i] : null;
      map[key] = snap?.value ?? template[key];
    }
    return AppDB.fromJson(map);
  }

  static Future<void> writeAppDb(AppDB db) async {
    final database = await _database();
    final payload = db.toJson();
    await database.transaction((txn) async {
      for (final e in payload.entries) {
        await _store.record(e.key).put(txn, e.value);
      }
      await _store.record(_markerKey).put(txn, true);
    });
  }

  static Future<void> readTombstonesInto(Set<String> sink) async {
    final database = await _database();
    final raw = await _store.record(_tombstoneKey).get(database);
    sink.clear();
    if (raw is List) {
      for (final e in raw) {
        final s = e?.toString();
        if (s != null && s.isNotEmpty) sink.add(s);
      }
    }
  }

  static Future<void> writeTombstones(Set<String> keys) async {
    final database = await _database();
    await _store.record(_tombstoneKey).put(database, keys.toList());
  }

  /// Read per-`(familyId, table)` `last_synced_at` cursors as a flat map keyed
  /// by `"$familyId:$table"` → ISO timestamp string. Empty map means no
  /// cursors recorded yet (initial sync should be a full fetch).
  static Future<Map<String, String>> readCursors() async {
    final database = await _database();
    final raw = await _store.record(_cursorsKey).get(database);
    if (raw is Map) {
      final out = <String, String>{};
      raw.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) {
          out[k] = v;
        }
      });
      return out;
    }
    return <String, String>{};
  }

  static Future<void> writeCursors(Map<String, String> cursors) async {
    final database = await _database();
    await _store.record(_cursorsKey).put(database, cursors);
  }

  /// Read the outbox queue as a list of plain Maps (caller parses to its
  /// record type). Empty list = empty queue or first run.
  static Future<List<Map<String, dynamic>>> readOutbox() async {
    final database = await _database();
    final raw = await _store.record(_outboxKey).get(database);
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) {
          out.add(Map<String, dynamic>.from(e));
        }
      }
      return out;
    }
    return const <Map<String, dynamic>>[];
  }

  static Future<void> writeOutbox(List<Map<String, dynamic>> records) async {
    final database = await _database();
    await _store.record(_outboxKey).put(database, records);
  }

  /// Clears app DB shards + marker + tombstones (logout / clear local DB).
  static Future<void> clearAppRecords() async {
    final database = await _database();
    final keys = AppDB.empty().toJson().keys.toList();
    await database.transaction((txn) async {
      for (final k in keys) {
        await _store.record(k).delete(txn);
      }
      await _store.record(_markerKey).delete(txn);
      await _store.record(_tombstoneKey).delete(txn);
      await _store.record(_cursorsKey).delete(txn);
      await _store.record(_outboxKey).delete(txn);
    });
  }

  /// Deletes the underlying database file / IndexedDB database (destructive wipe).
  static Future<void> deletePhysicalDatabase() async {
    try {
      await _db?.close();
    } on Object catch (_) {}
    _db = null;
    final loc = _storagePathOrName;
    _storagePathOrName = null;
    if (loc == null) return;
    try {
      await localDatabaseFactory.deleteDatabase(loc);
    } on Object catch (e, st) {
      debugPrint('[LocalSembastStore] deletePhysicalDatabase: $e\n$st');
    }
  }
}
