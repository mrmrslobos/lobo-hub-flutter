import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'workout_sessions_repository.dart';

class AppDbWorkoutSessionsRepository implements WorkoutSessionsRepository {
  AppDbWorkoutSessionsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<WorkoutSession>>> _streamsByKey = {};

  @override
  List<WorkoutSession> workoutSessionsForFamily(String familyId, String userId) {
    return _data.db.workoutSessions
        .where((s) => s.familyId == familyId && s.userId == userId)
        .toList();
  }

  String _fingerprint(List<WorkoutSession> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(s.id);
      buf.write(':');
      buf.write(s.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(s.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<WorkoutSession>> watchWorkoutSessionsForFamily(String familyId, String userId) {
    final key = '$familyId|$userId';
    return _streamsByKey.putIfAbsent(key, () => _createWatchStream(familyId, userId));
  }

  Stream<List<WorkoutSession>> _createWatchStream(String familyId, String userId) {
    late StreamController<List<WorkoutSession>> controller;
    String? lastFp;

    void emit() {
      final next = workoutSessionsForFamily(familyId, userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<WorkoutSession>>.broadcast(
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
  Future<void> upsert(WorkoutSession item) async {
    final db = _data.db;
    final next = db.copyWith(
      workoutSessions: [...db.workoutSessions.where((s) => s.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.workoutSessions});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      workoutSessions: [...db.workoutSessions.where((s) => s.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.workoutSessions});
  }
}
