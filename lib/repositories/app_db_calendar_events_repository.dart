import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'calendar_events_repository.dart';

class AppDbCalendarEventsRepository implements CalendarEventsRepository {
  AppDbCalendarEventsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<CalendarEvent>>> _streamsByFamilyId = {};

  @override
  List<CalendarEvent> eventsForFamily(String familyId) {
    return _data.db.events.where((e) => e.familyId == familyId).toList();
  }

  String _fingerprint(List<CalendarEvent> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(e.id);
      buf.write(':');
      buf.write(e.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(e.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<CalendarEvent>> watchEventsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<CalendarEvent>> _createWatchStream(String familyId) {
    late StreamController<List<CalendarEvent>> controller;
    String? lastFp;

    void emit() {
      final next = eventsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<CalendarEvent>>.broadcast(
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
  Future<void> upsert(CalendarEvent item) async {
    final db = _data.db;
    final next = db.copyWith(
      events: [...db.events.where((e) => e.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.events});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      events: [...db.events.where((e) => e.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.events});
  }
}
