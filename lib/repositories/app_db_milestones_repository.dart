import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'milestones_repository.dart';

class AppDbMilestonesRepository implements MilestonesRepository {
  AppDbMilestonesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<Milestone>>> _streamsByFamilyId = {};

  @override
  List<Milestone> milestonesForFamily(String familyId) {
    return _data.db.milestones.where((m) => m.familyId == familyId).toList();
  }

  String _fingerprint(List<Milestone> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final m = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(m.id);
      buf.write(':');
      buf.write(m.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(m.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<Milestone>> watchMilestonesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<Milestone>> _createWatchStream(String familyId) {
    late StreamController<List<Milestone>> controller;
    String? lastFp;

    void emit() {
      final next = milestonesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Milestone>>.broadcast(
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
  Future<void> upsert(Milestone item) async {
    final db = _data.db;
    final next = db.copyWith(
      milestones: [...db.milestones.where((m) => m.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.milestones});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      milestones: [...db.milestones.where((m) => m.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.milestones});
  }
}
