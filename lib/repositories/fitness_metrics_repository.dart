import '../models/models.dart';

abstract class FitnessMetricsRepository {
  List<FitnessMetric> fitnessMetricsForUser(String userId);

  Stream<List<FitnessMetric>> watchFitnessMetricsForUser(String userId);

  Future<void> upsert(FitnessMetric item);

  Future<void> delete(String id);
}
