import '../models/models.dart';

abstract class MealPlansRepository {
  List<MealPlanEntry> mealPlansForFamily(String familyId);

  Stream<List<MealPlanEntry>> watchMealPlansForFamily(String familyId);

  Future<void> upsert(MealPlanEntry item);

  Future<void> softDelete(String id);
}
