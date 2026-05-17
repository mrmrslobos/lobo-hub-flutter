import '../models/models.dart';

abstract class ReadingPlansRepository {
  List<ReadingPlan> readingPlansForFamily(String familyId);

  Stream<List<ReadingPlan>> watchReadingPlansForFamily(String familyId);

  Future<void> upsert(ReadingPlan item);

  Future<void> softDelete(String id);
}
