import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'period_symptoms_repository.dart';

class AppDbPeriodSymptomsRepository implements PeriodSymptomsRepository {
  AppDbPeriodSymptomsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<PeriodSymptomLog>>> _streamsByUserId = {};

  @override
  List<PeriodSymptomLog> periodSymptomsForUser(String userId) {
    return _data.db.periodSymptoms.where((s) => s.userId == userId).toList();
  }

  String _fingerprint(List<PeriodSymptomLog> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(s.id);
      buf.write(':');
      buf.write(s.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(s.date.microsecondsSinceEpoch);
    }
    return buf.toString();
  }

  @override
  Stream<List<PeriodSymptomLog>> watchPeriodSymptomsForUser(String userId) {
    return _streamsByUserId.putIfAbsent(userId, () => _createWatchStream(userId));
  }

  Stream<List<PeriodSymptomLog>> _createWatchStream(String userId) {
    late StreamController<List<PeriodSymptomLog>> controller;
    String? lastFp;

    void emit() {
      final next = periodSymptomsForUser(userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<PeriodSymptomLog>>.broadcast(
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
  Future<void> upsert(PeriodSymptomLog item) async {
    final db = _data.db;
    final next = db.copyWith(
      periodSymptoms: [...db.periodSymptoms.where((s) => s.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.periodSymptoms});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      periodSymptoms: [...db.periodSymptoms.where((s) => s.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.periodSymptoms});
  }
}
