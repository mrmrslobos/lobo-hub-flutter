import '../models/models.dart';

/// Per-family task reads/writes. Implementations may start on monolithic [AppDB]
/// and later swap to Drift/Isar without touching screens.
abstract class TasksRepository {
  List<Task> tasksForFamily(String familyId);

  Stream<List<Task>> watchTasksForFamily(String familyId);

  Future<void> upsert(Task task);

  Future<void> softDelete(String taskId);
}
