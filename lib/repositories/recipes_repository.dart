import '../models/models.dart';

abstract class RecipesRepository {
  List<Recipe> recipesForFamily(String familyId);

  Stream<List<Recipe>> watchRecipesForFamily(String familyId);

  Future<void> upsert(Recipe item);

  Future<void> softDelete(String id);
}
