import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'budget_entries_repository.dart';

class AppDbBudgetEntriesRepository implements BudgetEntriesRepository {
  AppDbBudgetEntriesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<BudgetEntry>>> _streamsByFamilyId = {};

  @override
  List<BudgetEntry> budgetEntriesForFamily(String familyId) {
    return _data.db.budgetEntries.where((e) => e.familyId == familyId).toList();
  }

  String _fingerprint(List<BudgetEntry> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(e.id);
      buf.write(':');
      buf.write(e.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(e.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<BudgetEntry>> watchBudgetEntriesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<BudgetEntry>> _createWatchStream(String familyId) {
    late StreamController<List<BudgetEntry>> controller;
    String? lastFp;

    void emit() {
      final next = budgetEntriesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<BudgetEntry>>.broadcast(
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
  Future<void> upsert(BudgetEntry item) async {
    final db = _data.db;
    final next = db.copyWith(
      budgetEntries: [...db.budgetEntries.where((e) => e.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.budgetEntries});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      budgetEntries: [...db.budgetEntries.where((e) => e.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.budgetEntries});
  }
}
