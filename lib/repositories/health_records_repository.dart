import '../models/models.dart';

abstract class HealthRecordsRepository {
  List<HealthRecord> healthRecordsForFamily(String familyId);

  Stream<List<HealthRecord>> watchHealthRecordsForFamily(String familyId);

  Future<void> upsert(HealthRecord item);

  Future<void> softDelete(String id);
}
