import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'workout_exercises_repository.dart';

class AppDbWorkoutExercisesRepository implements WorkoutExercisesRepository {
  AppDbWorkoutExercisesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<WorkoutExercise>>> _streamsByKey = {};

  @override
  List<WorkoutExercise> workoutExercisesForSession(String sessionId) {
    return _data.db.workoutExercises.where((e) => e.sessionId == sessionId).toList();
  }

  String _fingerprint(List<WorkoutExercise> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(e.id);
      buf.write(':');
      buf.write(e.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(e.exerciseName);
    }
    return buf.toString();
  }

  @override
  Stream<List<WorkoutExercise>> watchWorkoutExercisesForFamily(String familyId, String userId) {
    final key = '$familyId|$userId';
    return _streamsByKey.putIfAbsent(key, () => _createWatchStream(familyId, userId));
  }

  Stream<List<WorkoutExercise>> _createWatchStream(String familyId, String userId) {
    late StreamController<List<WorkoutExercise>> controller;
    String? lastFp;

    void emit() {
      final next = _data.db.workoutExercises
          .where((e) => e.familyId == familyId && e.userId == userId)
          .toList();
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<WorkoutExercise>>.broadcast(
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
  Future<void> upsert(WorkoutExercise item) async {
    final db = _data.db;
    final next = db.copyWith(
      workoutExercises: [...db.workoutExercises.where((e) => e.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.workoutExercises});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      workoutExercises: [...db.workoutExercises.where((e) => e.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.workoutExercises});
  }
}
