import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lobohub/models/models.dart';
import 'package:lobohub/services/database_service.dart';
import 'package:uuid/uuid.dart';

import 'package:lobohub/config/cloud_sync_scope.dart';

import '_supabase_test_config.dart';

/// Sequential two-user orchestration inside one isolate (cheap v1 —
/// [DatabaseService] is still static globally).
///
/// Provision two real accounts plus a shared family in the test Supabase project
/// before enabling this harness.
class SyncTestHarness {
  SyncTestHarness._();

  static final _uuid = Uuid();
  static var _supabaseInited = false;

  static Future<void> initSupabaseOnce() async {
    if (!SupabaseTestConfig.isReady) return;
    if (_supabaseInited) return;
    await Supabase.initialize(
      url: SupabaseTestConfig.url,
      anonKey: SupabaseTestConfig.anonKey,
    );
    _supabaseInited = true;
  }

  static Future<void> signIn(String email, String password) async {
    final res =
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
    if (res.user == null) {
      throw StateError('signIn returned no user');
    }
  }

  static Future<void> tearDownLocals() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } on Object catch (e) {
      debugPrint('[SyncTestHarness] signOut skipped: $e');
    }
    await DatabaseService.wipeAllLocalStorage();
  }

  static Future<AppDB> pullFamily(String familyId) async {
    return pullFamilyScoped(familyId, const {});
  }

  static Future<AppDB> pullFamilyScoped(
    String familyId,
    Set<String> pullTables,
  ) async {
    final merged = await DatabaseService.reconcileCloud(
      DatabaseService.db,
      familyId,
      pullTables: pullTables.isEmpty ? null : pullTables,
    );
    final err = DatabaseService.lastError;
    if (err != null && err.isNotEmpty) {
      debugPrint('[SyncTestHarness] reconcileCloud: $err');
      throw StateError('reconcileCloud failed');
    }
    await DatabaseService.saveLocal(merged);
    return merged;
  }

  static Future<Task> deviceACreateTask(String title) async {
    final fid = SupabaseTestConfig.familyId;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) throw StateError('Not signed in as A');

    var db = DatabaseService.db;
    if (!db.familyMembers.any((m) => m.familyId == fid && m.userId == uid)) {
      db = await pullFamily(fid);
    }

    final id = _uuid.v4();
    final task = Task(
      id: id,
      familyId: fid,
      creatorId: uid,
      title: title,
    );
    final next = db.copyWith(
      tasks: [...db.tasks.where((t) => t.id != id), task],
    );
    await DatabaseService.saveLocal(next);
    await DatabaseService.pushFamilyTasksToCloudNow(next, fid);
    return task;
  }

  static Future<void> waitForTask(
    String taskId,
    String familyId, {
    Duration timeout = const Duration(seconds: 15),
    Duration poll = const Duration(milliseconds: 300),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed <= timeout) {
      await DatabaseService.reconcileCloud(DatabaseService.db, familyId);
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        debugPrint('[SyncTestHarness] waitForTask reconcile: $err');
      }
      final t = DatabaseService.db.tasks.any((x) => x.id == taskId && x.familyId == familyId);
      if (t) return;
      await Future<void>.delayed(poll);
    }
    throw TimeoutException('waitForTask $taskId');
  }

  static Future<void> waitForTaskGone(
    String taskId,
    String familyId, {
    Duration timeout = const Duration(seconds: 15),
    Duration poll = const Duration(milliseconds: 300),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed <= timeout) {
      await DatabaseService.reconcileCloud(DatabaseService.db, familyId);
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        debugPrint('[SyncTestHarness] waitForTaskGone reconcile: $err');
      }
      final still = DatabaseService.db.tasks.any((x) => x.id == taskId && x.familyId == familyId);
      if (!still) return;
      await Future<void>.delayed(poll);
    }
    throw TimeoutException('waitForTaskGone $taskId');
  }

  static Future<void> deviceASoftDeleteTask(String taskId) async {
    final fid = SupabaseTestConfig.familyId;
    final db = DatabaseService.db;
    final next =
        db.copyWith(tasks: [...db.tasks.where((t) => !(t.id == taskId && t.familyId == fid))]);
    await DatabaseService.saveLocal(next);
    await DatabaseService.pushFamilyTasksToCloudNow(next, fid);
  }

  static Future<({ShoppingList list, ListItem item})> deviceACreateListWithItem(
    String listTitle,
    String itemText,
  ) async {
    final fid = SupabaseTestConfig.familyId;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) throw StateError('Not signed in as A');

    var db = DatabaseService.db;
    if (!db.familyMembers.any((m) => m.familyId == fid && m.userId == uid)) {
      db = await pullFamily(fid);
    }

    final listId = _uuid.v4();
    final itemId = _uuid.v4();
    final item = ListItem(id: itemId, text: itemText);
    final list = ShoppingList(
      id: listId,
      familyId: fid,
      creatorId: uid,
      title: listTitle,
      items: [item],
    );
    final next = db.copyWith(
      lists: [...db.lists.where((l) => l.id != listId), list],
    );
    await DatabaseService.saveLocal(next);
    await DatabaseService.pushFamilyListsToCloudNow(next, fid);
    return (list: list, item: item);
  }

  static Future<void> waitForListItem(
    String listId,
    String itemId,
    String familyId, {
    Duration timeout = const Duration(seconds: 15),
    Duration poll = const Duration(milliseconds: 300),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed <= timeout) {
      await DatabaseService.reconcileCloud(
        DatabaseService.db,
        familyId,
        pullTables: CloudSyncScope.listsBundle,
      );
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        debugPrint('[SyncTestHarness] waitForListItem reconcile: $err');
      }
      ShoppingList? match;
      for (final l in DatabaseService.db.lists) {
        if (l.id == listId && l.familyId == familyId) {
          match = l;
          break;
        }
      }
      if (match != null && match.items.any((i) => i.id == itemId)) return;
      await Future<void>.delayed(poll);
    }
    throw TimeoutException('waitForListItem $listId/$itemId');
  }

  static Future<void> waitForListItemGone(
    String listId,
    String itemId,
    String familyId, {
    Duration timeout = const Duration(seconds: 15),
    Duration poll = const Duration(milliseconds: 300),
  }) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed <= timeout) {
      await DatabaseService.reconcileCloud(
        DatabaseService.db,
        familyId,
        pullTables: CloudSyncScope.listsBundle,
      );
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        debugPrint('[SyncTestHarness] waitForListItemGone reconcile: $err');
      }
      ShoppingList? match;
      for (final l in DatabaseService.db.lists) {
        if (l.id == listId && l.familyId == familyId) {
          match = l;
          break;
        }
      }
      final still = match?.items.any((i) => i.id == itemId) ?? false;
      if (!still) return;
      await Future<void>.delayed(poll);
    }
    throw TimeoutException('waitForListItemGone $listId/$itemId');
  }

  static Future<void> deviceARemoveListItem(String listId, String itemId) async {
    final fid = SupabaseTestConfig.familyId;
    final db = DatabaseService.db;
    final next = db.copyWith(
      lists: db.lists.map((list) {
        if (list.id != listId || list.familyId != fid) return list;
        return list.copyWith(
          items: list.items.where((i) => i.id != itemId).toList(),
        );
      }).toList(),
    );
    await DatabaseService.saveLocal(next);
    await DatabaseService.pushFamilyListsToCloudNow(next, fid);
  }
}
