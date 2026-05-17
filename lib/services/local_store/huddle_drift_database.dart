import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'huddle_drift_database.g.dart';

/// One JSON shard per top-level [AppDB.toJson] key (Tier A).
class AppDbShards extends Table {
  TextColumn get shardKey => text()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {shardKey};
}

/// JSON blobs for tombstones, cursors, outbox, and layout marker.
class LocalKvEntries extends Table {
  TextColumn get entryKey => text()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {entryKey};
}

@DriftDatabase(tables: [AppDbShards, LocalKvEntries])
class HuddleDriftDb extends _$HuddleDriftDb {
  HuddleDriftDb._() : super(_lazyExecutor());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {},
      );

  static HuddleDriftDb? _instance;
  static HuddleDriftDb get shared => _instance ??= HuddleDriftDb._();

  static File? _sqliteFile;

  static Future<void> shutdownAndDeleteFile() async {
    try {
      if (_instance != null) {
        await _instance!.close();
        _instance = null;
      }
      final f = _sqliteFile;
      if (f != null && await f.exists()) {
        await f.delete();
      }
    } catch (e, st) {
      debugPrint('[HuddleDriftDb] shutdownAndDeleteFile: $e\n$st');
    } finally {
      _sqliteFile = null;
    }
  }

  static LazyDatabase _lazyExecutor() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'huddle_drift_v1.sqlite'));
      _sqliteFile = file;
      return NativeDatabase.createInBackground(file);
    });
  }
}
