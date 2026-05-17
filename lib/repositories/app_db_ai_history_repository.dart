import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'ai_history_repository.dart';

class AppDbAIHistoryRepository implements AIHistoryRepository {
  AppDbAIHistoryRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<AIHistory>>> _streamsByFamilyId = {};

  @override
  List<AIHistory> aiHistoryForFamily(String familyId) {
    return _data.db.aiHistory.where((h) => h.familyId == familyId).toList();
  }

  String _fingerprint(List<AIHistory> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final h = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(h.id);
      buf.write(':');
      buf.write(h.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(h.module);
    }
    return buf.toString();
  }

  @override
  Stream<List<AIHistory>> watchAIHistoryForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<AIHistory>> _createWatchStream(String familyId) {
    late StreamController<List<AIHistory>> controller;
    String? lastFp;

    void emit() {
      final next = aiHistoryForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<AIHistory>>.broadcast(
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
  Future<void> upsert(AIHistory item) async {
    final db = _data.db;
    final next = db.copyWith(
      aiHistory: [...db.aiHistory.where((h) => h.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.aiHistory});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      aiHistory: [...db.aiHistory.where((h) => h.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.aiHistory});
  }
}
