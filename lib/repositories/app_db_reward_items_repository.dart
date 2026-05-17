import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'reward_items_repository.dart';

class AppDbRewardItemsRepository implements RewardItemsRepository {
  AppDbRewardItemsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<RewardItem>>> _streamsByFamilyId = {};

  @override
  List<RewardItem> rewardItemsForFamily(String familyId) {
    return _data.db.rewardItems.where((r) => r.familyId == familyId).toList();
  }

  String _fingerprint(List<RewardItem> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(r.id);
      buf.write(':');
      buf.write(r.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(r.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<RewardItem>> watchRewardItemsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<RewardItem>> _createWatchStream(String familyId) {
    late StreamController<List<RewardItem>> controller;
    String? lastFp;

    void emit() {
      final next = rewardItemsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<RewardItem>>.broadcast(
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
  Future<void> upsert(RewardItem item) async {
    final db = _data.db;
    final next = db.copyWith(
      rewardItems: [...db.rewardItems.where((r) => r.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.rewardItems});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      rewardItems: [...db.rewardItems.where((r) => r.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.rewardItems});
  }
}
