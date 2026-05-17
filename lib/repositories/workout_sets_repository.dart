import '../models/models.dart';

abstract class WorkoutSetsRepository {
  List<WorkoutSet> workoutSetsForFamily(String familyId, String userId);

  Stream<List<WorkoutSet>> watchWorkoutSetsForFamily(String familyId, String userId);

  Future<void> upsert(WorkoutSet item);

  Future<void> delete(String id);
}
