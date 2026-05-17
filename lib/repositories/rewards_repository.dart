import '../models/models.dart';

abstract class RewardsRepository {
  List<Reward> rewardsForFamily(String familyId);

  Stream<List<Reward>> watchRewardsForFamily(String familyId);

  Future<void> upsert(Reward item);

  Future<void> softDelete(String id);
}
