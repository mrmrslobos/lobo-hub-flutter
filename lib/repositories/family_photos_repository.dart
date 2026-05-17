import '../models/models.dart';

abstract class FamilyPhotosRepository {
  List<FamilyPhoto> familyPhotosForFamily(String familyId);

  Stream<List<FamilyPhoto>> watchFamilyPhotosForFamily(String familyId);

  Future<void> upsert(FamilyPhoto item);

  Future<void> softDelete(String id);
}
