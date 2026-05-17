import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'reward_redemptions_repository.dart';

class AppDbRewardRedemptionsRepository implements RewardRedemptionsRepository {
  AppDbRewardRedemptionsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<RewardRedemption>>> _streamsByFamilyId = {};

  @override
  List<RewardRedemption> rewardRedemptionsForFamily(String familyId) {
    return _data.db.rewardRedemptions.where((r) => r.familyId == familyId).toList();
  }

  String _fingerprint(List<RewardRedemption> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(r.id);
      buf.write(':');
      buf.write(r.requestedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(r.status.name);
    }
    return buf.toString();
  }

  @override
  Stream<List<RewardRedemption>> watchRewardRedemptionsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<RewardRedemption>> _createWatchStream(String familyId) {
    late StreamController<List<RewardRedemption>> controller;
    String? lastFp;

    void emit() {
      final next = rewardRedemptionsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<RewardRedemption>>.broadcast(
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
  Future<void> upsert(RewardRedemption item) async {
    final db = _data.db;
    final next = db.copyWith(
      rewardRedemptions: [...db.rewardRedemptions.where((r) => r.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.rewardRedemptions});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      rewardRedemptions: [...db.rewardRedemptions.where((r) => r.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.rewardRedemptions});
  }
}
