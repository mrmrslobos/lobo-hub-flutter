import '../models/models.dart';

abstract class AIHistoryRepository {
  List<AIHistory> aiHistoryForFamily(String familyId);

  Stream<List<AIHistory>> watchAIHistoryForFamily(String familyId);

  Future<void> upsert(AIHistory item);

  Future<void> delete(String id);
}
