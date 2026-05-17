import '../models/models.dart';

abstract class DailyHabitCompletionsRepository {
  List<DailyHabitCompletion> dailyHabitCompletionsForUser(String userId);

  Stream<List<DailyHabitCompletion>> watchDailyHabitCompletionsForUser(String userId);

  Future<void> upsert(DailyHabitCompletion item);

  Future<void> delete(String id);
}
