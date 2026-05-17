import '../models/models.dart';

abstract class WorkoutExercisesRepository {
  List<WorkoutExercise> workoutExercisesForSession(String sessionId);

  Stream<List<WorkoutExercise>> watchWorkoutExercisesForFamily(String familyId, String userId);

  Future<void> upsert(WorkoutExercise item);

  Future<void> delete(String id);
}
