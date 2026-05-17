import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../local_sembast_store.dart';
import 'huddle_drift_database.dart';
import 'local_persistence_store.dart';
import 'local_store_keys.dart';

/// Tier A drift mirror of [LocalSembastStore] (JSON shards + KV aux rows).
class DriftBlobLocalStore implements LocalPersistenceStore {
  DriftBlobLocalStore(this._db);

  final HuddleDriftDb _db;

  Future<void> _putKv(String key, String payload) async {
    await _db.into(_db.localKvEntries).insert(
          LocalKvEntriesCompanion.insert(entryKey: key, payload: payload),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<String?> _getKv(String key) async {
    final q = await (_db.select(_db.localKvEntries)
          ..where((t) => t.entryKey.equals(key)))
        .getSingleOrNull();
    return q?.payload;
  }

  @override
  Future<bool> hasStoredAppDb() async {
    final m = await _getKv(LocalStoreKeys.driftMarkerKey);
    return m == '1';
  }

  @override
  Future<AppDB> readAppDb() async {
    final template = AppDB.empty().toJson();
    final map = <String, dynamic>{};
    for (final k in template.keys) {
      final row = await (_db.select(_db.appDbShards)
            ..where((t) => t.shardKey.equals(k)))
          .getSingleOrNull();
      if (row == null) {
        map[k] = template[k];
      } else {
        try {
          map[k] = jsonDecode(row.payload);
        } on Object catch (e, st) {
          debugPrint('[DriftBlobLocalStore] jsonDecode shard $k: $e\n$st');
          map[k] = template[k];
        }
      }
    }
    return AppDB.fromJson(map);
  }

  @override
  Future<void> writeAppDb(AppDB db) async {
    await _db.transaction(() async {
      final payload = db.toJson();
      for (final e in payload.entries) {
        final encoded = jsonEncode(e.value);
        await _db.into(_db.appDbShards).insert(
              AppDbShardsCompanion.insert(shardKey: e.key, payload: encoded),
              mode: InsertMode.insertOrReplace,
            );
      }
      await _putKv(LocalStoreKeys.driftMarkerKey, '1');
    });
  }

  /// All-or-nothing Sembast migration (marker written only inside this transaction).
  Future<void> importFullSnapshotFromMigration({
    required AppDB appDb,
    required Set<String> tombstones,
    required Map<String, String> cursors,
    required List<Map<String, dynamic>> outbox,
  }) async {
    await _db.transaction(() async {
      final payload = appDb.toJson();
      for (final e in payload.entries) {
        final encoded = jsonEncode(e.value);
        await _db.into(_db.appDbShards).insert(
              AppDbShardsCompanion.insert(shardKey: e.key, payload: encoded),
              mode: InsertMode.insertOrReplace,
            );
      }
      await _putKv(
        LocalStoreKeys.tombstoneKey,
        jsonEncode(tombstones.toList()),
      );
      await _putKv(LocalStoreKeys.cursorsKey, jsonEncode(cursors));
      await _putKv(LocalStoreKeys.outboxKey, jsonEncode(outbox));
      await _putKv(LocalStoreKeys.driftMarkerKey, '1');
    });
  }

  @override
  Future<void> readTombstonesInto(Set<String> sink) async {
    sink.clear();
    final raw = await _getKv(LocalStoreKeys.tombstoneKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          final s = e?.toString();
          if (s != null && s.isNotEmpty) sink.add(s);
        }
      }
    } on Object catch (e, st) {
      debugPrint('[DriftBlobLocalStore] readTombstones: $e\n$st');
    }
  }

  @override
  Future<void> writeTombstones(Set<String> keys) async {
    await _putKv(LocalStoreKeys.tombstoneKey, jsonEncode(keys.toList()));
  }

  @override
  Future<Map<String, String>> readCursors() async {
    final raw = await _getKv(LocalStoreKeys.cursorsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        final ks = k?.toString();
        final vs = v?.toString();
        if (ks != null && vs != null && vs.isNotEmpty) out[ks] = vs;
      });
      return out;
    } on Object catch (e, st) {
      debugPrint('[DriftBlobLocalStore] readCursors: $e\n$st');
      return {};
    }
  }

  @override
  Future<void> writeCursors(Map<String, String> cursors) async {
    await _putKv(LocalStoreKeys.cursorsKey, jsonEncode(cursors));
  }

  @override
  Future<List<Map<String, dynamic>>> readOutbox() async {
    final raw = await _getKv(LocalStoreKeys.outboxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is Map) {
          out.add(Map<String, dynamic>.from(e));
        }
      }
      return out;
    } on Object catch (e, st) {
      debugPrint('[DriftBlobLocalStore] readOutbox: $e\n$st');
      return [];
    }
  }

  @override
  Future<void> writeOutbox(List<Map<String, dynamic>> records) async {
    await _putKv(LocalStoreKeys.outboxKey, jsonEncode(records));
  }

  @override
  Future<void> clearAppRecords() async {
    await _db.transaction(() async {
      await _db.delete(_db.appDbShards).go();
      await _db.delete(_db.localKvEntries).go();
    });
  }

  @override
  Future<void> deletePhysicalDatabase() async {
    await HuddleDriftDb.shutdownAndDeleteFile();
  }
}

/// Migrate existing Sembast install into drift, then clear Sembast app records only.
Future<void> migrateSembastToDriftOrThrow(DriftBlobLocalStore target) async {
  final appDb = await LocalSembastStore.readAppDb();
  final tombstones = <String>{};
  await LocalSembastStore.readTombstonesInto(tombstones);
  final cursors = await LocalSembastStore.readCursors();
  final outbox = await LocalSembastStore.readOutbox();

  await target.importFullSnapshotFromMigration(
    appDb: appDb,
    tombstones: tombstones,
    cursors: cursors,
    outbox: outbox,
  );
  await LocalSembastStore.clearAppRecords();
}
