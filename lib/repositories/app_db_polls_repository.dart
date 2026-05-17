import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'polls_repository.dart';

class AppDbPollsRepository implements PollsRepository {
  AppDbPollsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<Poll>>> _streamsByFamilyId = {};

  @override
  List<Poll> pollsForFamily(String familyId) {
    return _data.db.polls.where((p) => p.familyId == familyId).toList();
  }

  String _fingerprint(List<Poll> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(p.id);
      buf.write(':');
      buf.write(p.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(p.question);
      buf.write(':');
      buf.write(p.options.length);
    }
    return buf.toString();
  }

  @override
  Stream<List<Poll>> watchPollsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<Poll>> _createWatchStream(String familyId) {
    late StreamController<List<Poll>> controller;
    String? lastFp;

    void emit() {
      final next = pollsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Poll>>.broadcast(
      onListen: () {
        _data.addListener(emit);
        emit();
      },
      onCancel: () {
        if (!controller.hasListener) _data.removeListener(emit);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> upsert(Poll item) async {
    final db = _data.db;
    final next = db.copyWith(
      polls: [...db.polls.where((p) => p.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.polls});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      polls: [...db.polls.where((p) => p.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.polls});
  }
}
