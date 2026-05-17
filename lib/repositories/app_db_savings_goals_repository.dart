import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'savings_goals_repository.dart';

class AppDbSavingsGoalsRepository implements SavingsGoalsRepository {
  AppDbSavingsGoalsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<SavingsGoal>>> _streamsByFamilyId = {};

  @override
  List<SavingsGoal> savingsGoalsForFamily(String familyId) {
    return _data.db.savingsGoals.where((g) => g.familyId == familyId).toList();
  }

  String _fingerprint(List<SavingsGoal> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final g = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(g.id);
      buf.write(':');
      buf.write(g.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(g.title);
      buf.write(':');
      buf.write(g.savedAmount.toString());
    }
    return buf.toString();
  }

  @override
  Stream<List<SavingsGoal>> watchSavingsGoalsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<SavingsGoal>> _createWatchStream(String familyId) {
    late StreamController<List<SavingsGoal>> controller;
    String? lastFp;

    void emit() {
      final next = savingsGoalsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<SavingsGoal>>.broadcast(
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
  Future<void> upsert(SavingsGoal item) async {
    final db = _data.db;
    final next = db.copyWith(
      savingsGoals: [...db.savingsGoals.where((g) => g.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.savingsGoals});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      savingsGoals: [...db.savingsGoals.where((g) => g.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.savingsGoals});
  }
}
