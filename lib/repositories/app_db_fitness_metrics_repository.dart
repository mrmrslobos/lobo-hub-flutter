import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'fitness_metrics_repository.dart';

class AppDbFitnessMetricsRepository implements FitnessMetricsRepository {
  AppDbFitnessMetricsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<FitnessMetric>>> _streamsByUserId = {};

  @override
  List<FitnessMetric> fitnessMetricsForUser(String userId) {
    return _data.db.fitness.where((m) => m.userId == userId).toList();
  }

  String _fingerprint(List<FitnessMetric> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final m = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(m.id);
      buf.write(':');
      buf.write(m.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(m.type);
    }
    return buf.toString();
  }

  @override
  Stream<List<FitnessMetric>> watchFitnessMetricsForUser(String userId) {
    return _streamsByUserId.putIfAbsent(userId, () => _createWatchStream(userId));
  }

  Stream<List<FitnessMetric>> _createWatchStream(String userId) {
    late StreamController<List<FitnessMetric>> controller;
    String? lastFp;

    void emit() {
      final next = fitnessMetricsForUser(userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<FitnessMetric>>.broadcast(
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
  Future<void> upsert(FitnessMetric item) async {
    final db = _data.db;
    final next = db.copyWith(
      fitness: [...db.fitness.where((m) => m.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.fitness});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      fitness: [...db.fitness.where((m) => m.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.fitness});
  }
}
