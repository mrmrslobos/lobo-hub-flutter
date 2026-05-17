import '../models/models.dart';

abstract class RewardRedemptionsRepository {
  List<RewardRedemption> rewardRedemptionsForFamily(String familyId);

  Stream<List<RewardRedemption>> watchRewardRedemptionsForFamily(String familyId);

  Future<void> upsert(RewardRedemption item);

  Future<void> delete(String id);
}
