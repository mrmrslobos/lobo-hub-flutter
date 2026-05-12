import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'tasks_repository.dart';

/// [TasksRepository] backed by [DataProvider] / monolithic [AppDB].
///
/// Soft-deleted rows are omitted server-side on pull; locally we only filter by [familyId].
class AppDbTasksRepository implements TasksRepository {
  AppDbTasksRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;

  final Map<String, Stream<List<Task>>> _tasksStreamsByFamilyId = {};

  @override
  List<Task> tasksForFamily(String familyId) {
    return _data.db.tasks.where((t) => t.familyId == familyId).toList();
  }

  String _fingerprint(List<Task> tasks) {
    final sorted = [...tasks]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final t = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(t.id);
      buf.write(':');
      buf.write(t.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(t.completed);
      buf.write(':');
      buf.write(t.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<Task>> watchTasksForFamily(String familyId) {
    return _tasksStreamsByFamilyId.putIfAbsent(
      familyId,
      () => _createTasksWatchStream(familyId),
    );
  }

  Stream<List<Task>> _createTasksWatchStream(String familyId) {
    late StreamController<List<Task>> controller;
    String? lastFp;

    void emit() {
      final next = tasksForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Task>>.broadcast(
      onListen: () {
        _data.addListener(emit);
        emit();
      },
      onCancel: () {
        if (!controller.hasListener) {
          _data.removeListener(emit);
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> upsert(Task task) async {
    final db = _data.db;
    final next = db.copyWith(
      tasks: [...db.tasks.where((t) => t.id != task.id), task],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.tasks});
  }

  @override
  Future<void> softDelete(String taskId) async {
    final db = _data.db;
    final next = db.copyWith(
      tasks: [...db.tasks.where((t) => t.id != taskId)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.tasks});
  }
}
