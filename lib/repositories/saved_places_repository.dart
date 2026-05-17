import '../models/models.dart';

abstract class SavedPlacesRepository {
  List<SavedPlace> savedPlacesForFamily(String familyId);

  Stream<List<SavedPlace>> watchSavedPlacesForFamily(String familyId);

  Future<void> upsert(SavedPlace item);

  Future<void> softDelete(String id);
}
