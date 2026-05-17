import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'workout_sets_repository.dart';

class AppDbWorkoutSetsRepository implements WorkoutSetsRepository {
  AppDbWorkoutSetsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<WorkoutSet>>> _streamsByKey = {};

  @override
  List<WorkoutSet> workoutSetsForFamily(String familyId, String userId) {
    return _data.db.workoutSets
        .where((s) => s.familyId == familyId && s.userId == userId)
        .toList();
  }

  String _fingerprint(List<WorkoutSet> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(s.id);
      buf.write(':');
      buf.write(s.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(s.reps);
    }
    return buf.toString();
  }

  @override
  Stream<List<WorkoutSet>> watchWorkoutSetsForFamily(String familyId, String userId) {
    final key = '$familyId|$userId';
    return _streamsByKey.putIfAbsent(key, () => _createWatchStream(familyId, userId));
  }

  Stream<List<WorkoutSet>> _createWatchStream(String familyId, String userId) {
    late StreamController<List<WorkoutSet>> controller;
    String? lastFp;

    void emit() {
      final next = workoutSetsForFamily(familyId, userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<WorkoutSet>>.broadcast(
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
  Future<void> upsert(WorkoutSet item) async {
    final db = _data.db;
    final next = db.copyWith(
      workoutSets: [...db.workoutSets.where((s) => s.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.workoutSets});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      workoutSets: [...db.workoutSets.where((s) => s.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.workoutSets});
  }
}
