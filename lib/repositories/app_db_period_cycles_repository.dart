import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'period_cycles_repository.dart';

class AppDbPeriodCyclesRepository implements PeriodCyclesRepository {
  AppDbPeriodCyclesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<PeriodCycle>>> _streamsByUserId = {};

  @override
  List<PeriodCycle> periodCyclesForUser(String userId) {
    return _data.db.periodCycles.where((c) => c.userId == userId).toList();
  }

  String _fingerprint(List<PeriodCycle> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(c.id);
      buf.write(':');
      buf.write(c.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(c.startDate.microsecondsSinceEpoch);
    }
    return buf.toString();
  }

  @override
  Stream<List<PeriodCycle>> watchPeriodCyclesForUser(String userId) {
    return _streamsByUserId.putIfAbsent(userId, () => _createWatchStream(userId));
  }

  Stream<List<PeriodCycle>> _createWatchStream(String userId) {
    late StreamController<List<PeriodCycle>> controller;
    String? lastFp;

    void emit() {
      final next = periodCyclesForUser(userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<PeriodCycle>>.broadcast(
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
  Future<void> upsert(PeriodCycle item) async {
    final db = _data.db;
    final next = db.copyWith(
      periodCycles: [...db.periodCycles.where((c) => c.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.periodCycles});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      periodCycles: [...db.periodCycles.where((c) => c.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.periodCycles});
  }
}
