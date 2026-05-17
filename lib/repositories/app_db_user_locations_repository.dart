import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'user_locations_repository.dart';

class AppDbUserLocationsRepository implements UserLocationsRepository {
  AppDbUserLocationsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<UserLocation>>> _streamsByUserId = {};

  @override
  List<UserLocation> userLocationsForUser(String userId) {
    return _data.db.userLocations.where((l) => l.userId == userId).toList();
  }

  String _fingerprint(List<UserLocation> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(l.id);
      buf.write(':');
      buf.write(l.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(l.latitude.toString());
    }
    return buf.toString();
  }

  @override
  Stream<List<UserLocation>> watchUserLocationsForUser(String userId) {
    return _streamsByUserId.putIfAbsent(userId, () => _createWatchStream(userId));
  }

  Stream<List<UserLocation>> _createWatchStream(String userId) {
    late StreamController<List<UserLocation>> controller;
    String? lastFp;

    void emit() {
      final next = userLocationsForUser(userId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<UserLocation>>.broadcast(
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
  Future<void> upsert(UserLocation item) async {
    final db = _data.db;
    final next = db.copyWith(
      userLocations: [...db.userLocations.where((l) => l.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.userLocations});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      userLocations: [...db.userLocations.where((l) => l.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.userLocations});
  }
}
