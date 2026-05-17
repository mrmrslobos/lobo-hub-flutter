import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'messages_repository.dart';

class AppDbMessagesRepository implements MessagesRepository {
  AppDbMessagesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<ChatMessage>>> _streamsByFamilyId = {};

  @override
  List<ChatMessage> messagesForFamily(String familyId) {
    return _data.db.messages.where((m) => m.familyId == familyId).toList();
  }

  String _fingerprint(List<ChatMessage> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final m = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(m.id);
      buf.write(':');
      buf.write(m.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(m.reactions.length);
    }
    return buf.toString();
  }

  @override
  Stream<List<ChatMessage>> watchMessagesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<ChatMessage>> _createWatchStream(String familyId) {
    late StreamController<List<ChatMessage>> controller;
    String? lastFp;

    void emit() {
      final next = messagesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ChatMessage>>.broadcast(
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
  Future<void> upsert(ChatMessage item) async {
    final prev = _data.db.messages.firstWhereOrNull((m) => m.id == item.id);
    final next = _data.db.copyWith(
      messages: [..._data.db.messages.where((m) => m.id != item.id), item],
    );
    _data.updateDb(next);
    final hook = _data.onSaveAndSync;
    if (hook == null) return;
    unawaited(Future<void>(() async {
      try {
        await hook(next, pushTableScope: {CloudSyncScope.messages});
      } catch (_) {
        final cur = _data.db;
        if (prev != null) {
          _data.updateDb(cur.copyWith(
            messages: [...cur.messages.where((m) => m.id != item.id), prev],
          ));
        } else {
          _data.updateDb(cur.copyWith(
            messages: cur.messages.where((m) => m.id != item.id).toList(),
          ));
        }
      }
    }));
  }

  @override
  Future<void> delete(String id) async {
    final prev = _data.db.messages.firstWhereOrNull((m) => m.id == id);
    if (prev == null) return;
    final next = _data.db.copyWith(
      messages: _data.db.messages.where((m) => m.id != id).toList(),
    );
    _data.updateDb(next);
    final hook = _data.onSaveAndSync;
    if (hook == null) return;
    unawaited(Future<void>(() async {
      try {
        await hook(next, pushTableScope: {CloudSyncScope.messages});
      } catch (_) {
        final cur = _data.db;
        _data.updateDb(cur.copyWith(
          messages: [...cur.messages.where((m) => m.id != id), prev],
        ));
      }
    }));
  }
}
