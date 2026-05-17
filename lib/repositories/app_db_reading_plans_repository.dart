import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'reading_plans_repository.dart';

class AppDbReadingPlansRepository implements ReadingPlansRepository {
  AppDbReadingPlansRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<ReadingPlan>>> _streamsByFamilyId = {};

  @override
  List<ReadingPlan> readingPlansForFamily(String familyId) {
    return _data.db.readingPlans.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<ReadingPlan> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<ReadingPlan>> watchReadingPlansForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<ReadingPlan>> _createWatchStream(String familyId) {
    late StreamController<List<ReadingPlan>> controller;
    String? lastFp;

    void emit() {
      final next = readingPlansForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ReadingPlan>>.broadcast(
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
  Future<void> upsert(ReadingPlan item) async {
    final db = _data.db;
    final next = db.copyWith(
      readingPlans: [...db.readingPlans.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.readingPlans});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      readingPlans: [...db.readingPlans.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.readingPlans});
  }
}
