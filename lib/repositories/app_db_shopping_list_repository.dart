import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'shopping_list_repository.dart';

/// [ShoppingListsRepository] backed by [DataProvider] / monolithic [AppDB].
///
/// Soft-deleted rows are omitted server-side on pull; locally we only filter by [familyId].
class AppDbShoppingListsRepository implements ShoppingListsRepository {
  AppDbShoppingListsRepository({required DataProvider dataProvider})
      : _data = dataProvider;

  final DataProvider _data;

  final Map<String, Stream<List<ShoppingList>>> _streamsByFamilyId = {};

  @override
  List<ShoppingList> listsForFamily(String familyId) {
    return _data.db.lists.where((l) => l.familyId == familyId).toList();
  }

  String _fingerprint(List<ShoppingList> lists) {
    final sorted = [...lists]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(l.id);
      buf.write(':');
      buf.write(l.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(l.title);
      buf.write(':');
      buf.write(l.visibility.name);
      buf.write(':');
      buf.write(l.category.name);
      buf.write(':');
      buf.write(l.sharedWith.join(','));
      final items = [...l.items]..sort((a, b) => a.id.compareTo(b.id));
      for (final it in items) {
        buf.write('|');
        buf.write(it.id);
        buf.write('/');
        buf.write(it.text);
        buf.write('/');
        buf.write(it.checked);
        buf.write('/');
        buf.write(it.quantity ?? '');
        buf.write('/');
        buf.write(it.aiCategory ?? '');
      }
    }
    return buf.toString();
  }

  @override
  Stream<List<ShoppingList>> watchListsForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(
      familyId,
      () => _createWatchStream(familyId),
    );
  }

  Stream<List<ShoppingList>> _createWatchStream(String familyId) {
    late StreamController<List<ShoppingList>> controller;
    String? lastFp;

    void emit() {
      final next = listsForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<ShoppingList>>.broadcast(
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
  Future<void> upsert(ShoppingList item) async {
    final db = _data.db;
    final next = db.copyWith(
      lists: [...db.lists.where((l) => l.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.lists});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      lists: [...db.lists.where((l) => l.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.lists});
  }
}
