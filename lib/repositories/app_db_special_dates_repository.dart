import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'special_dates_repository.dart';

class AppDbSpecialDatesRepository implements SpecialDatesRepository {
  AppDbSpecialDatesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<SpecialDate>>> _streamsByFamilyId = {};

  @override
  List<SpecialDate> specialDatesForFamily(String familyId) {
    return _data.db.specialDates.where((s) => s.familyId == familyId).toList();
  }

  String _fingerprint(List<SpecialDate> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(s.id);
      buf.write(':');
      buf.write(s.createdAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(s.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<SpecialDate>> watchSpecialDatesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<SpecialDate>> _createWatchStream(String familyId) {
    late StreamController<List<SpecialDate>> controller;
    String? lastFp;

    void emit() {
      final next = specialDatesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<SpecialDate>>.broadcast(
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
  Future<void> upsert(SpecialDate item) async {
    final db = _data.db;
    final next = db.copyWith(
      specialDates: [...db.specialDates.where((s) => s.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.specialDates});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      specialDates: [...db.specialDates.where((s) => s.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.specialDates});
  }
}
