import '../models/models.dart';

abstract class RewardItemsRepository {
  List<RewardItem> rewardItemsForFamily(String familyId);

  Stream<List<RewardItem>> watchRewardItemsForFamily(String familyId);

  Future<void> upsert(RewardItem item);

  Future<void> softDelete(String id);
}
