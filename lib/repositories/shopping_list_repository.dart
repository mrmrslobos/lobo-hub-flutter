import '../models/models.dart';

/// Per-family shopping list reads/writes. Implementations may start on monolithic [AppDB]
/// and later swap to Drift/Isar without touching screens.
abstract class ShoppingListsRepository {
  List<ShoppingList> listsForFamily(String familyId);

  Stream<List<ShoppingList>> watchListsForFamily(String familyId);

  Future<void> upsert(ShoppingList item);

  Future<void> softDelete(String id);
}
