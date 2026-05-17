import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'wellness_check_ins_repository.dart';

class AppDbWellnessCheckInsRepository implements WellnessCheckInsRepository {
  AppDbWellnessCheckInsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<WellnessCheckIn>>> _streamsByFamilyId = {};

  @override
  List<WellnessCheckIn> wellnessCheckInsForFamily(String familyId) {
    return _data.db.wellnessCheckIns.where((w) => w.familyId == familyId).toList();
  }

  String _fingerprint(List<WellnessCheckIn> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final w = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(w.id);
      buf.write(':');
      buf.write(w.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(w.mood);
    }
    return buf.toString();
  }

  @override
  Stream<List<WellnessCheckIn>> watchWellnessCheckInsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<WellnessCheckIn>> _createWatchStream(String familyId) {
    late StreamController<List<WellnessCheckIn>> controller;
    String? lastFp;

    void emit() {
      final next = wellnessCheckInsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<WellnessCheckIn>>.broadcast(
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
  Future<void> upsert(WellnessCheckIn item) async {
    final db = _data.db;
    final next = db.copyWith(
      wellnessCheckIns: [...db.wellnessCheckIns.where((w) => w.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.wellnessCheckIns});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      wellnessCheckIns: [...db.wellnessCheckIns.where((w) => w.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.wellnessCheckIns});
  }
}
