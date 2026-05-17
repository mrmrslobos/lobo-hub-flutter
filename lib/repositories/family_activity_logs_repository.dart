import '../models/models.dart';

abstract class FamilyActivityLogsRepository {
  List<FamilyActivityLog> familyActivityLogsForFamily(String familyId);

  Stream<List<FamilyActivityLog>> watchFamilyActivityLogsForFamily(String familyId);

  Future<void> upsert(FamilyActivityLog item);

  Future<void> delete(String id);
}
