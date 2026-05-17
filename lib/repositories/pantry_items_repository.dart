import '../models/models.dart';

abstract class PantryItemsRepository {
  List<PantryItem> pantryItemsForFamily(String familyId);

  Stream<List<PantryItem>> watchPantryItemsForFamily(String familyId);

  Future<void> upsert(PantryItem item);

  Future<void> softDelete(String id);
}
