import '../models/models.dart';

abstract class DailyHabitsRepository {
  List<DailyHabit> dailyHabitsForFamily(String familyId);

  Stream<List<DailyHabit>> watchDailyHabitsForFamily(String familyId);

  Future<void> upsert(DailyHabit item);

  Future<void> softDelete(String id);
}
