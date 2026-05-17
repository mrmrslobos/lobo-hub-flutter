import '../models/models.dart';

abstract class ReadingPlanProgressRepository {
  List<ReadingPlanProgress> readingPlanProgressForFamily(String familyId);

  Stream<List<ReadingPlanProgress>> watchReadingPlanProgressForFamily(String familyId);

  Future<void> upsert(ReadingPlanProgress item);

  Future<void> delete(String id);
}
