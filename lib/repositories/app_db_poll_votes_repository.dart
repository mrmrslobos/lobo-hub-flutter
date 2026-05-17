import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'poll_votes_repository.dart';

class AppDbPollVotesRepository implements PollVotesRepository {
  AppDbPollVotesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<PollVote>>> _streamsByFamilyId = {};

  @override
  List<PollVote> pollVotesForFamily(String familyId) {
    return _data.db.pollVotes.where((v) => v.familyId == familyId).toList();
  }

  String _fingerprint(List<PollVote> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final v = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(v.id);
      buf.write(':');
      buf.write(v.votedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(v.optionId);
    }
    return buf.toString();
  }

  @override
  Stream<List<PollVote>> watchPollVotesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<PollVote>> _createWatchStream(String familyId) {
    late StreamController<List<PollVote>> controller;
    String? lastFp;

    void emit() {
      final next = pollVotesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<PollVote>>.broadcast(
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
  Future<void> upsert(PollVote item) async {
    final db = _data.db;
    final next = db.copyWith(
      pollVotes: [...db.pollVotes.where((v) => v.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.pollVotes});
  }

  @override
  Future<void> delete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      pollVotes: [...db.pollVotes.where((v) => v.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.pollVotes});
  }
}
