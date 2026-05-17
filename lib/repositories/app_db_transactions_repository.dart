import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'transactions_repository.dart';

class AppDbTransactionsRepository implements TransactionsRepository {
  AppDbTransactionsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<Transaction>>> _streamsByFamilyId = {};

  @override
  List<Transaction> transactionsForFamily(String familyId) {
    return _data.db.transactions.where((t) => t.familyId == familyId).toList();
  }

  String _fingerprint(List<Transaction> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(t.id);
      buf.write(':');
      buf.write(t.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(t.description);
    }
    return buf.toString();
  }

  @override
  Stream<List<Transaction>> watchTransactionsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<Transaction>> _createWatchStream(String familyId) {
    late StreamController<List<Transaction>> controller;
    String? lastFp;

    void emit() {
      final next = transactionsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Transaction>>.broadcast(
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
  Future<void> upsert(Transaction item) async {
    final db = _data.db;
    final next = db.copyWith(
      transactions: [...db.transactions.where((t) => t.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.transactions});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      transactions: [...db.transactions.where((t) => t.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.transactions});
  }
}
