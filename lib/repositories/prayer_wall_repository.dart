import '../models/models.dart';

abstract class PrayerWallRepository {
  List<PrayerWallEntry> prayerWallForFamily(String familyId);

  Stream<List<PrayerWallEntry>> watchPrayerWallForFamily(String familyId);

  Future<void> upsert(PrayerWallEntry item);

  Future<void> softDelete(String id);
}
