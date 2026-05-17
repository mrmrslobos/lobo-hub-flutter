import '../models/models.dart';

abstract class BudgetCategoriesRepository {
  List<BudgetCategoryRecord> budgetCategoriesForFamily(String familyId);

  Stream<List<BudgetCategoryRecord>> watchBudgetCategoriesForFamily(String familyId);

  Future<void> upsert(BudgetCategoryRecord item);

  Future<void> softDelete(String id);
}
