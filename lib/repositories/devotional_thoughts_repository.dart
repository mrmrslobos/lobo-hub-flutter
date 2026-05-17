import '../models/models.dart';

abstract class DevotionalThoughtsRepository {
  List<DevotionalThought> devotionalThoughtsForFamily(String familyId);

  Stream<List<DevotionalThought>> watchDevotionalThoughtsForFamily(String familyId);

  Future<void> upsert(DevotionalThought item);

  Future<void> delete(String id);
}
