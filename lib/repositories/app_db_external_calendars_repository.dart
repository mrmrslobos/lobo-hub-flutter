import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'external_calendars_repository.dart';

class AppDbExternalCalendarsRepository implements ExternalCalendarsRepository {
  AppDbExternalCalendarsRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<ExternalCalendar>>> _streamsByFamilyId = {};

  @override
  List<ExternalCalendar> externalCalendarsForFamily(String familyId) {
    return _data.db.externalCalendars.where((c) => c.familyId == familyId).toList();
  }

  String _fingerprint(List<ExternalCalendar> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final c = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(c.id);
      buf.write(':');
      buf.write(c.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(c.name);
    }
    return buf.toString();
  }

  @override
  Stream<List<ExternalCalendar>> watchExternalCalendarsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<ExternalCalendar>> _createWatchStream(String familyId) {
    late StreamController<List<ExternalCalendar>> controller;
    String? lastFp;

    void emit() {
      final next = externalCalendarsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ExternalCalendar>>.broadcast(
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
  Future<void> upsert(ExternalCalendar item) async {
    final db = _data.db;
    final next = db.copyWith(
      externalCalendars: [...db.externalCalendars.where((c) => c.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.externalCalendars});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      externalCalendars: [...db.externalCalendars.where((c) => c.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.externalCalendars});
  }
}
