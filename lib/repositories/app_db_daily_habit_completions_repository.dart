import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'daily_habit_completions_repository.dart';

class AppDbDailyHabitCompletionsRepository implements DailyHabitCompletionsRepository {
  AppDbDailyHabitCompletionsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<DailyHabitCompletion>>> _streamsByUserId = {};

  @override
  List<DailyHabitCompletion> dailyHabitCompletionsForUser(String userId) {
    return _data.db.dailyHabitCompletions.where((c) => c.userId == userId).toList();
  }

  String _fingerprint(List<DailyHabitCompletion> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(c.id);
      buf.write(':');
      buf.write(c.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(c.completedAt.microsecondsSinceEpoch);
    }
    return buf.toString();
  }

  @override
  Stream<List<DailyHabitCompletion>> watchDailyHabitCompletionsForUser(String userId) {
    return _streamsByUserId.putIfAbsent(userId, () => _createWatchStream(userId));
  }

  Stream<List<DailyHabitCompletion>> _createWatchStream(String userId) {
    late StreamController<List<DailyHabitCompletion>> controller;
    String? lastFp;

    void emit() {
      final next = dailyHabitCompletionsForUser(userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<DailyHabitCompletion>>.broadcast(
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
  Future<void> upsert(DailyHabitCompletion item) async {
    final db = _data.db;
    final next = db.copyWith(
      dailyHabitCompletions: [...db.dailyHabitCompletions.where((c) => c.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.dailyHabitCompletions});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      dailyHabitCompletions: [...db.dailyHabitCompletions.where((c) => c.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.dailyHabitCompletions});
  }
}
