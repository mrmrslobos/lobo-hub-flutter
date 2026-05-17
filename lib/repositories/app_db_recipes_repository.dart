import 'dart:async';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../providers/data_provider.dart';
import 'recipes_repository.dart';

class AppDbRecipesRepository implements RecipesRepository {
  AppDbRecipesRepository({required DataProvider dataProvider}) : _data = dataProvider;

  final DataProvider _data;
  final Map<String, Stream<List<Recipe>>> _streamsByFamilyId = {};

  @override
  List<Recipe> recipesForFamily(String familyId) {
    return _data.db.recipes.where((r) => r.familyId == familyId).toList();
  }

  String _fingerprint(List<Recipe> items) {
    final sorted = [...items]..sort((a, b) => a.id.compareTo(b.id));
    final buf = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      if (i > 0) buf.write('\x1e');
      buf.write(r.id);
      buf.write(':');
      buf.write(r.updatedAt.microsecondsSinceEpoch);
      buf.write(':');
      buf.write(r.title);
    }
    return buf.toString();
  }

  @override
  Stream<List<Recipe>> watchRecipesForFamily(String familyId) {
    return _streamsByFamilyId.putIfAbsent(familyId, () => _createWatchStream(familyId));
  }

  Stream<List<Recipe>> _createWatchStream(String familyId) {
    late StreamController<List<Recipe>> controller;
    String? lastFp;

    void emit() {
      final next = recipesForFamily(familyId);
      final fp = _fingerprint(next);
      if (fp == lastFp) return;
      lastFp = fp;
      controller.add(next);
    }

    controller = StreamController<List<Recipe>>.broadcast(
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
  Future<void> upsert(Recipe item) async {
    final db = _data.db;
    final next = db.copyWith(
      recipes: [...db.recipes.where((r) => r.id != item.id), item],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.recipes});
  }

  @override
  Future<void> softDelete(String id) async {
    final db = _data.db;
    final next = db.copyWith(
      recipes: [...db.recipes.where((r) => r.id != id)],
    );
    await _data.saveAndSync(next, pushTableScope: {CloudSyncScope.recipes});
  }
}
