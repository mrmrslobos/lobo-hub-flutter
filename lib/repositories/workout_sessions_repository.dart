import '../models/models.dart';

abstract class WorkoutSessionsRepository {
  List<WorkoutSession> workoutSessionsForFamily(String familyId, String userId);

  Stream<List<WorkoutSession>> watchWorkoutSessionsForFamily(String familyId, String userId);

  Future<void> upsert(WorkoutSession item);

  Future<void> delete(String id);
}
