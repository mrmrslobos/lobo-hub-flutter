import '../models/models.dart';

abstract class FitnessLogsRepository {
  List<FitnessLog> fitnessLogsForFamily(String familyId, String userId);

  Stream<List<FitnessLog>> watchFitnessLogsForFamily(String familyId, String userId);

  Future<void> upsert(FitnessLog item);

  Future<void> delete(String id);
}
