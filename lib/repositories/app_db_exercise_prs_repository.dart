import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'exercise_prs_repository.dart';

class AppDbExercisePRsRepository implements ExercisePRsRepository {
  AppDbExercisePRsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<ExercisePR>>> _streamsByFamilyId = {};

  @override
  List<ExercisePR> exercisePRsForFamily(String familyId) {
    return _data.db.exercisePrs.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<ExercisePR> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.exerciseKey);
    }
    return buf.toString();
  }

  @override
  Stream<List<ExercisePR>> watchExercisePRsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<ExercisePR>> _createWatchStream(String familyId) {
    late StreamController<List<ExercisePR>> controller;
    String? lastFp;

    void emit() {
      final next = exercisePRsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ExercisePR>>.broadcast(
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
  Future<void> upsert(ExercisePR item) async {
    final db = _data.db;
    final next = db.copyWith(
      exercisePrs: [...db.exercisePrs.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.exercisePrs});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      exercisePrs: [...db.exercisePrs.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.exercisePrs});
  }
}
