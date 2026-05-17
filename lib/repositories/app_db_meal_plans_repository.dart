import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'meal_plans_repository.dart';

class AppDbMealPlansRepository implements MealPlansRepository {
  AppDbMealPlansRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<MealPlanEntry>>> _streamsByFamilyId = {};

  @override
  List<MealPlanEntry> mealPlansForFamily(String familyId) {
    return _data.db.mealPlans.where((m) => m.familyId == familyId).toList();
  }

  String _fingerprint(List<MealPlanEntry> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final m = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(m.id);
      buf.write(':');
      buf.write(m.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(m.mealType);
    }
    return buf.toString();
  }

  @override
  Stream<List<MealPlanEntry>> watchMealPlansForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<MealPlanEntry>> _createWatchStream(String familyId) {
    late StreamController<List<MealPlanEntry>> controller;
    String? lastFp;

    void emit() {
      final next = mealPlansForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<MealPlanEntry>>.broadcast(
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
  Future<void> upsert(MealPlanEntry item) async {
    final db = _data.db;
    final next = db.copyWith(
      mealPlans: [...db.mealPlans.where((m) => m.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.mealPlans});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      mealPlans: [...db.mealPlans.where((m) => m.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.mealPlans});
  }
}
