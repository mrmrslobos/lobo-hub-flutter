import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'saved_places_repository.dart';

class AppDbSavedPlacesRepository implements SavedPlacesRepository {
  AppDbSavedPlacesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<SavedPlace>>> _streamsByFamilyId = {};

  @override
  List<SavedPlace> savedPlacesForFamily(String familyId) {
    return _data.db.savedPlaces.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<SavedPlace> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.name);
    }
    return buf.toString();
  }

  @override
  Stream<List<SavedPlace>> watchSavedPlacesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<SavedPlace>> _createWatchStream(String familyId) {
    late StreamController<List<SavedPlace>> controller;
    String? lastFp;

    void emit() {
      final next = savedPlacesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<SavedPlace>>.broadcast(
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
  Future<void> upsert(SavedPlace item) async {
    final db = _data.db;
    final next = db.copyWith(
      savedPlaces: [...db.savedPlaces.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.savedPlaces});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      savedPlaces: [...db.savedPlaces.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.savedPlaces});
  }
}
