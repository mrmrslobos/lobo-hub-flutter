import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'daily_habits_repository.dart';

class AppDbDailyHabitsRepository implements DailyHabitsRepository {
  AppDbDailyHabitsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<DailyHabit>>> _streamsByFamilyId = {};

  @override
  List<DailyHabit> dailyHabitsForFamily(String familyId) {
    return _data.db.dailyHabits.where((h) => h.familyId == familyId).toList();
  }

  String _fingerprint(List<DailyHabit> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final h = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(h.id);
      buf.write(':');
      buf.write(h.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(h.label);
    }
    return buf.toString();
  }

  @override
  Stream<List<DailyHabit>> watchDailyHabitsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<DailyHabit>> _createWatchStream(String familyId) {
    late StreamController<List<DailyHabit>> controller;
    String? lastFp;

    void emit() {
      final next = dailyHabitsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<DailyHabit>>.broadcast(
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
  Future<void> upsert(DailyHabit item) async {
    final db = _data.db;
    final next = db.copyWith(
      dailyHabits: [...db.dailyHabits.where((h) => h.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.dailyHabits});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      dailyHabits: [...db.dailyHabits.where((h) => h.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.dailyHabits});
  }
}
