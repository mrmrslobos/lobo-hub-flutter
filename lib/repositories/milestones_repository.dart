import '../models/models.dart';

abstract class MilestonesRepository {
  List<Milestone> milestonesForFamily(String familyId);

  Stream<List<Milestone>> watchMilestonesForFamily(String familyId);

  Future<void> upsert(Milestone item);

  Future<void> softDelete(String id);
}
