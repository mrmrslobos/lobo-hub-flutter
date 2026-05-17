import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'fitness_logs_repository.dart';

class AppDbFitnessLogsRepository implements FitnessLogsRepository {
  AppDbFitnessLogsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<FitnessLog>>> _streamsByKey = {};

  @override
  List<FitnessLog> fitnessLogsForFamily(String familyId, String userId) {
    return _data.db.fitnessLogs
        .where((l) => l.familyId == familyId && l.userId == userId)
        .toList();
  }

  String _fingerprint(List<FitnessLog> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(l.id);
      buf.write(':');
      buf.write(l.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(l.activity);
    }
    return buf.toString();
  }

  @override
  Stream<List<FitnessLog>> watchFitnessLogsForFamily(String familyId, String userId) {
    final key = '$familyId|$userId';
    return _streamsByKey.putIfAbsent(key, () => _createWatchStream(familyId, userId));
  }

  Stream<List<FitnessLog>> _createWatchStream(String familyId, String userId) {
    late StreamController<List<FitnessLog>> controller;
    String? lastFp;

    void emit() {
      final next = fitnessLogsForFamily(familyId, userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<FitnessLog>>.broadcast(
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
  Future<void> upsert(FitnessLog item) async {
    final db = _data.db;
    final next = db.copyWith(
      fitnessLogs: [...db.fitnessLogs.where((l) => l.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.fitnessLogs});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      fitnessLogs: [...db.fitnessLogs.where((l) => l.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.fitnessLogs});
  }
}
