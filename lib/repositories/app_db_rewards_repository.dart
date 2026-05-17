import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'rewards_repository.dart';

class AppDbRewardsRepository implements RewardsRepository {
  AppDbRewardsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<Reward>>> _streamsByFamilyId = {};

  @override
  List<Reward> rewardsForFamily(String familyId) {
    return _data.db.rewards.where((r) => r.familyId == familyId).toList();
  }

  String _fingerprint(List<Reward> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(r.id);
      buf.write(':');
      buf.write(r.title);
      buf.write(':');
      buf.write(r.pointCost.toString());
      buf.write(':');
      buf.write(r.redeemedBy.length);
    }
    return buf.toString();
  }

  @override
  Stream<List<Reward>> watchRewardsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<Reward>> _createWatchStream(String familyId) {
    late StreamController<List<Reward>> controller;
    String? lastFp;

    void emit() {
      final next = rewardsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Reward>>.broadcast(
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
  Future<void> upsert(Reward item) async {
    final db = _data.db;
    final next = db.copyWith(
      rewards: [...db.rewards.where((r) => r.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.rewards});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      rewards: [...db.rewards.where((r) => r.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.rewards});
  }
}
