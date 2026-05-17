import '../models/models.dart';

abstract class BudgetEntriesRepository {
  List<BudgetEntry> budgetEntriesForFamily(String familyId);

  Stream<List<BudgetEntry>> watchBudgetEntriesForFamily(String familyId);

  Future<void> upsert(BudgetEntry item);

  Future<void> softDelete(String id);
}
