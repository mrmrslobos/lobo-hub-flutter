import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'prayer_wall_repository.dart';

class AppDbPrayerWallRepository implements PrayerWallRepository {
  AppDbPrayerWallRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<PrayerWallEntry>>> _streamsByFamilyId = {};

  @override
  List<PrayerWallEntry> prayerWallForFamily(String familyId) {
    return _data.db.prayerWall.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<PrayerWallEntry> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.date.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.prayedByIds.length);
      buf.write(':');
      buf.write(p.reactions.length);
      buf.write(':');
      buf.write(p.answeredAt?.microsecondsSinceEpoch ?? 0);
    }
    return buf.toString();
  }

  @override
  Stream<List<PrayerWallEntry>> watchPrayerWallForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<PrayerWallEntry>> _createWatchStream(String familyId) {
    late StreamController<List<PrayerWallEntry>> controller;
    String? lastFp;

    void emit() {
      final next = prayerWallForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<PrayerWallEntry>>.broadcast(
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
  Future<void> upsert(PrayerWallEntry item) async {
    final db = _data.db;
    final next = db.copyWith(
      prayerWall: [...db.prayerWall.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.prayerWall});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      prayerWall: [...db.prayerWall.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.prayerWall});
  }
}
