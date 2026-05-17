import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'chores_repository.dart';

class AppDbChoresRepository implements ChoresRepository {
  AppDbChoresRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<Chore>>> _streamsByFamilyId = {};

  @override
  List<Chore> choresForFamily(String familyId) {
    return _data.db.chores.where((c) => c.familyId == familyId).toList();
  }

  String _fingerprint(List<Chore> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(c.id);
      buf.write(':');
      buf.write(c.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(c.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<Chore>> watchChoresForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<Chore>> _createWatchStream(String familyId) {
    late StreamController<List<Chore>> controller;
    String? lastFp;

    void emit() {
      final next = choresForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Chore>>.broadcast(
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
  Future<void> upsert(Chore item) async {
    final db = _data.db;
    final next = db.copyWith(
      chores: [...db.chores.where((c) => c.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.chores});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      chores: [...db.chores.where((c) => c.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.chores});
  }
}
