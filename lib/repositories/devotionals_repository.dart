import '../models/models.dart';

abstract class DevotionalsRepository {
  List<DevotionalEntry> devotionalsForFamily(String familyId);

  Stream<List<DevotionalEntry>> watchDevotionalsForFamily(String familyId);

  Future<void> upsert(DevotionalEntry item);

  Future<void> softDelete(String id);
}
