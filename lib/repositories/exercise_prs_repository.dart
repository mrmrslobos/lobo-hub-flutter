import '../models/models.dart';

abstract class ExercisePRsRepository {
  List<ExercisePR> exercisePRsForFamily(String familyId);

  Stream<List<ExercisePR>> watchExercisePRsForFamily(String familyId);

  Future<void> upsert(ExercisePR item);

  Future<void> delete(String id);
}
