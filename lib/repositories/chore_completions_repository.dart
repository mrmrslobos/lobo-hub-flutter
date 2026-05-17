import '../models/models.dart';

abstract class ChoreCompletionsRepository {
  List<ChoreCompletion> choreCompletionsForFamily(String familyId);

  Stream<List<ChoreCompletion>> watchChoreCompletionsForFamily(String familyId);

  Future<void> upsert(ChoreCompletion item);

  Future<void> delete(String id);
}
