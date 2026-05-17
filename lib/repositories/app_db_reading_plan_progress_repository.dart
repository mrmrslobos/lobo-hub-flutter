import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'reading_plan_progress_repository.dart';

class AppDbReadingPlanProgressRepository implements ReadingPlanProgressRepository {
  AppDbReadingPlanProgressRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<ReadingPlanProgress>>> _streamsByFamilyId = {};

  @override
  List<ReadingPlanProgress> readingPlanProgressForFamily(String familyId) {
    return _data.db.readingPlanProgress.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<ReadingPlanProgress> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.startedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.completedDayNumbers.length);
    }
    return buf.toString();
  }

  @override
  Stream<List<ReadingPlanProgress>> watchReadingPlanProgressForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<ReadingPlanProgress>> _createWatchStream(String familyId) {
    late StreamController<List<ReadingPlanProgress>> controller;
    String? lastFp;

    void emit() {
      final next = readingPlanProgressForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ReadingPlanProgress>>.broadcast(
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
  Future<void> upsert(ReadingPlanProgress item) async {
    final db = _data.db;
    final next = db.copyWith(
      readingPlanProgress: [...db.readingPlanProgress.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.readingPlanProgress});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      readingPlanProgress: [...db.readingPlanProgress.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.readingPlanProgress});
  }
}
