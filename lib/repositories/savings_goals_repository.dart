import '../models/models.dart';

abstract class SavingsGoalsRepository {
  List<SavingsGoal> savingsGoalsForFamily(String familyId);

  Stream<List<SavingsGoal>> watchSavingsGoalsForFamily(String familyId);

  Future<void> upsert(SavingsGoal item);

  Future<void> softDelete(String id);
}
