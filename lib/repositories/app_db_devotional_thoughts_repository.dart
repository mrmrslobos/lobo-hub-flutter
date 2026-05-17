import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'devotional_thoughts_repository.dart';

class AppDbDevotionalThoughtsRepository implements DevotionalThoughtsRepository {
  AppDbDevotionalThoughtsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<DevotionalThought>>> _streamsByFamilyId = {};

  @override
  List<DevotionalThought> devotionalThoughtsForFamily(String familyId) {
    return _data.db.devotionalThoughts.where((t) => t.familyId == familyId).toList();
  }

  String _fingerprint(List<DevotionalThought> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(t.id);
      buf.write(':');
      buf.write(t.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(t.kind.wireValue);
    }
    return buf.toString();
  }

  @override
  Stream<List<DevotionalThought>> watchDevotionalThoughtsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<DevotionalThought>> _createWatchStream(String familyId) {
    late StreamController<List<DevotionalThought>> controller;
    String? lastFp;

    void emit() {
      final next = devotionalThoughtsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<DevotionalThought>>.broadcast(
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
  Future<void> upsert(DevotionalThought item) async {
    final db = _data.db;
    final next = db.copyWith(
      devotionalThoughts: [...db.devotionalThoughts.where((t) => t.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.devotionalThoughts});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      devotionalThoughts: [...db.devotionalThoughts.where((t) => t.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.devotionalThoughts});
  }
}
