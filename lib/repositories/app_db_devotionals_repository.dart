import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'devotionals_repository.dart';

class AppDbDevotionalsRepository implements DevotionalsRepository {
  AppDbDevotionalsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<DevotionalEntry>>> _streamsByFamilyId = {};

  @override
  List<DevotionalEntry> devotionalsForFamily(String familyId) {
    return _data.db.devotionals.where((d) => d.familyId == familyId).toList();
  }

  String _fingerprint(List<DevotionalEntry> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final d = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(d.id);
      buf.write(':');
      buf.write(d.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(d.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<DevotionalEntry>> watchDevotionalsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<DevotionalEntry>> _createWatchStream(String familyId) {
    late StreamController<List<DevotionalEntry>> controller;
    String? lastFp;

    void emit() {
      final next = devotionalsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<DevotionalEntry>>.broadcast(
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
  Future<void> upsert(DevotionalEntry item) async {
    final db = _data.db;
    final next = db.copyWith(
      devotionals: [...db.devotionals.where((d) => d.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.devotionals});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      devotionals: [...db.devotionals.where((d) => d.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.devotionals});
  }
}
