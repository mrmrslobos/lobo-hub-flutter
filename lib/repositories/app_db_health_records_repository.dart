import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'health_records_repository.dart';

class AppDbHealthRecordsRepository implements HealthRecordsRepository {
  AppDbHealthRecordsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<HealthRecord>>> _streamsByFamilyId = {};

  @override
  List<HealthRecord> healthRecordsForFamily(String familyId) {
    return _data.db.healthRecords.where((h) => h.familyId == familyId).toList();
  }

  String _fingerprint(List<HealthRecord> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final h = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(h.id);
      buf.write(':');
      buf.write(h.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(h.memberId);
    }
    return buf.toString();
  }

  @override
  Stream<List<HealthRecord>> watchHealthRecordsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<HealthRecord>> _createWatchStream(String familyId) {
    late StreamController<List<HealthRecord>> controller;
    String? lastFp;

    void emit() {
      final next = healthRecordsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<HealthRecord>>.broadcast(
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
  Future<void> upsert(HealthRecord item) async {
    final db = _data.db;
    final next = db.copyWith(
      healthRecords: [...db.healthRecords.where((h) => h.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.healthRecords});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      healthRecords: [...db.healthRecords.where((h) => h.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.healthRecords});
  }
}
