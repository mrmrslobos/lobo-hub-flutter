import '../models/models.dart';

abstract class PeriodCyclesRepository {
  List<PeriodCycle> periodCyclesForUser(String userId);

  Stream<List<PeriodCycle>> watchPeriodCyclesForUser(String userId);

  Future<void> upsert(PeriodCycle item);

  Future<void> softDelete(String id);
}
