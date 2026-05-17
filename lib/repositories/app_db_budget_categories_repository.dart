import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'budget_categories_repository.dart';

class AppDbBudgetCategoriesRepository implements BudgetCategoriesRepository {
  AppDbBudgetCategoriesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<BudgetCategoryRecord>>> _streamsByFamilyId = {};

  @override
  List<BudgetCategoryRecord> budgetCategoriesForFamily(String familyId) {
    return _data.db.budgetCategories.where((c) => c.familyId == familyId).toList();
  }

  String _fingerprint(List<BudgetCategoryRecord> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(c.id);
      buf.write(':');
      buf.write(c.name);
      buf.write(':');
      buf.write(c.limit.toString());
    }
    return buf.toString();
  }

  @override
  Stream<List<BudgetCategoryRecord>> watchBudgetCategoriesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<BudgetCategoryRecord>> _createWatchStream(String familyId) {
    late StreamController<List<BudgetCategoryRecord>> controller;
    String? lastFp;

    void emit() {
      final next = budgetCategoriesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<BudgetCategoryRecord>>.broadcast(
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
  Future<void> upsert(BudgetCategoryRecord item) async {
    final db = _data.db;
    final next = db.copyWith(
      budgetCategories: [...db.budgetCategories.where((c) => c.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.budgetCategories});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      budgetCategories: [...db.budgetCategories.where((c) => c.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.budgetCategories});
  }
}
