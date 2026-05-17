import '../models/models.dart';

abstract class PeriodSymptomsRepository {
  List<PeriodSymptomLog> periodSymptomsForUser(String userId);

  Stream<List<PeriodSymptomLog>> watchPeriodSymptomsForUser(String userId);

  Future<void> upsert(PeriodSymptomLog item);

  Future<void> softDelete(String id);
}
