import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'family_photos_repository.dart';

class AppDbFamilyPhotosRepository implements FamilyPhotosRepository {
  AppDbFamilyPhotosRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<FamilyPhoto>>> _streamsByFamilyId = {};

  @override
  List<FamilyPhoto> familyPhotosForFamily(String familyId) {
    return _data.db.familyPhotos.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<FamilyPhoto> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.url);
    }
    return buf.toString();
  }

  @override
  Stream<List<FamilyPhoto>> watchFamilyPhotosForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<FamilyPhoto>> _createWatchStream(String familyId) {
    late StreamController<List<FamilyPhoto>> controller;
    String? lastFp;

    void emit() {
      final next = familyPhotosForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<FamilyPhoto>>.broadcast(
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
  Future<void> upsert(FamilyPhoto item) async {
    final db = _data.db;
    final next = db.copyWith(
      familyPhotos: [...db.familyPhotos.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.familyPhotos});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      familyPhotos: [...db.familyPhotos.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.familyPhotos});
  }
}
