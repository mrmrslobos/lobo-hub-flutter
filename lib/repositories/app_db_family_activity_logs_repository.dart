import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'family_activity_logs_repository.dart';

class AppDbFamilyActivityLogsRepository implements FamilyActivityLogsRepository {
  AppDbFamilyActivityLogsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<FamilyActivityLog>>> _streamsByFamilyId = {};

  @override
  List<FamilyActivityLog> familyActivityLogsForFamily(String familyId) {
    return _data.db.familyActivityLogs.where((l) => l.familyId == familyId).toList();
  }

  String _fingerprint(List<FamilyActivityLog> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(l.id);
      buf.write(':');
      buf.write(l.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(l.action);
    }
    return buf.toString();
  }

  @override
  Stream<List<FamilyActivityLog>> watchFamilyActivityLogsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<FamilyActivityLog>> _createWatchStream(String familyId) {
    late StreamController<List<FamilyActivityLog>> controller;
    String? lastFp;

    void emit() {
      final next = familyActivityLogsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<FamilyActivityLog>>.broadcast(
      onListen: () {
        _data.addListener(emit);
        emit();
      },
      onCancel: () {
        if (!controller.hasListener) _data.removeListener(emit);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> upsert(FamilyActivityLog item) async {
    final db = _data.db;
    final next = db.copyWith(
      familyActivityLogs: [...db.familyActivityLogs.where((l) => l.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.familyActivityLogs});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      familyActivityLogs: [...db.familyActivityLogs.where((l) => l.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.familyActivityLogs});
  }
}
