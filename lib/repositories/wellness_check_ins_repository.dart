import '../models/models.dart';

abstract class WellnessCheckInsRepository {
  List<WellnessCheckIn> wellnessCheckInsForFamily(String familyId);

  Stream<List<WellnessCheckIn>> watchWellnessCheckInsForFamily(String familyId);

  Future<void> upsert(WellnessCheckIn item);

  Future<void> softDelete(String id);
}
