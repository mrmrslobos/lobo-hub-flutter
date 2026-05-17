import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'chore_completions_repository.dart';

class AppDbChoreCompletionsRepository implements ChoreCompletionsRepository {
  AppDbChoreCompletionsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<ChoreCompletion>>> _streamsByFamilyId = {};

  @override
  List<ChoreCompletion> choreCompletionsForFamily(String familyId) {
    return _data.db.choreCompletions.where((c) => c.familyId == familyId).toList();
  }

  String _fingerprint(List<ChoreCompletion> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(c.id);
      buf.write(':');
      buf.write(c.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(c.approvalStatus.name);
    }
    return buf.toString();
  }

  @override
  Stream<List<ChoreCompletion>> watchChoreCompletionsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<ChoreCompletion>> _createWatchStream(String familyId) {
    late StreamController<List<ChoreCompletion>> controller;
    String? lastFp;

    void emit() {
      final next = choreCompletionsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ChoreCompletion>>.broadcast(
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
  Future<void> upsert(ChoreCompletion item) async {
    final db = _data.db;
    final next = db.copyWith(
      choreCompletions: [...db.choreCompletions.where((c) => c.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.choreCompletions});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      choreCompletions: [...db.choreCompletions.where((c) => c.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.choreCompletions});
  }
}
