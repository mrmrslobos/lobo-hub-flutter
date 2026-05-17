import '../models/models.dart';

abstract class ChoresRepository {
  List<Chore> choresForFamily(String familyId);

  Stream<List<Chore>> watchChoresForFamily(String familyId);

  Future<void> upsert(Chore item);

  Future<void> softDelete(String id);
}
