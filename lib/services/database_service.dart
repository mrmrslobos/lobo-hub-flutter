// lib/services/database_service.dart
// Huddle - Local storage service with Supabase sync

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent;

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import 'local_store/local_store_resolver.dart';
import '../utils/app_db_isolate_codec.dart';
import '../utils/app_log.dart';
import '../utils/fitness_plan_storage.dart';
import 'exercise_plan_media_service.dart';
import 'field_encryption_service.dart';
import 'list_items_cloud.dart';
import 'supabase_service.dart';
import 'sync_echo_tracker.dart';
import 'sync_outbox.dart';

/// Row shape for Supabase `fitness_plans` (AI weekly plan per user).
Map<String, dynamic> fitnessPlanRowForCloud(
  Map<String, dynamic> plan,
  String familyId,
) {
  final uid = plan['user_id']?.toString() ?? '';
  final created = plan['created_at']?.toString() ?? '';
  final id = fitnessPlanCloudRowId(plan, familyId);
  dynamic weekly = plan['weeklyPlan'] ?? plan['weekly_plan'] ?? [];
  if (weekly is! List) {
    weekly = [];
  } else {
    weekly =
        ExercisePlanMediaService.weeklyPlanForCloud(List<dynamic>.from(weekly));
  }
  dynamic tips = plan['tips'] ?? [];
  if (tips is! List) tips = [];
  dynamic profile = plan['profile'] ?? {};
  if (profile is! Map) profile = <String, dynamic>{};
  return {
    'id': id,
    'user_id': uid,
    'family_id': familyId,
    'plan_id': plan['plan_id']?.toString() ?? '',
    'summary': plan['summary']?.toString() ?? '',
    'weekly_plan': weekly,
    'tips': tips,
    'profile': profile,
    'created_at': created.isNotEmpty ? created : DateTime.now().toIso8601String(),
  };
}

class DatabaseService {
  /// One cloud sync at a time per family — parallel syncs can finish out of order
  /// and overwrite a newer row (e.g. list created empty then items added quickly).
  static final Map<String, Future<void>> _syncTailByFamily = {};

  /// Families columns omitted on cloud upsert.
  /// [subscription_tier] must only change via [SupabaseService.syncFamilySubscriptionTier]
  /// or the revenuecat-webhook edge function (P0 trigger on families UPDATE).
  static const _familiesCloudOmit = {
    'currency',
    'subscription_tier',
  };

  /// plan_id: migration 25 (optional on older DBs).
  static const _fitnessPlansCloudOmit = {'plan_id'};

  /// Tasks columns some older DBs lack (PGRST204).
  static const _tasksCloudOmit = {'completed_by', 'updated_by', 'due_time', 'reminder_minutes'};

  /// Chores columns older DBs may lack until migration.
  static const _choresCloudOmit = {'rotation_enabled', 'rotation_cursor'};

  /// Workout exercise columns older DBs may lack until migration 16.
  static const _workoutExerciseCloudOmit = {
    'technique_notes',
    'reference_url',
    'technique_image_url',
  };

  /// Meal plan columns older DBs may lack until migration 16 / 17.
  static const _mealPlanCloudOmit = {
    'repeat_rule',
    'source_meal_plan_id',
    'leftover_meal_plan_id',
  };

  /// Recipe macro columns until migration 17.
  static const _recipeCloudOmit = {
    'kcal',
    'protein_g',
    'carbs_g',
    'fat_g',
    'fiber_g',
  };

  /// workout_sessions.health_synced_at until migration 17.
  static const _workoutSessionCloudOmit = {'health_synced_at'};

  static const _usersCloudOmit = <String>{};

  /// Events columns some older DBs lack (PGRST204) — shared_with is required for SPECIFIC visibility sync.
  static const _eventsCloudOmit = <String>{};

  /// Prayer wall columns some older DBs lack (PGRST204).
  static const _prayerWallCloudOmit = {'prayed_by_ids'};

  static const String _dbKey = 'huddle_db';
  /// Pre-rebrand local DB key; [loadLocal] migrates into [_dbKey] once.
  static const String _legacyDbKey = 'familyhub_db';
  static const String _tombstoneKey = 'fh_merge_tombstones';
  static AppDB? _cache;

  /// Keys intentionally removed locally. Persisted so restarts + failed cloud
  /// deletes don't let merged pulls resurrect rows (family members, tasks, …).
  ///
  /// Bounded LRU keyed by insertion order. On overflow we evict the OLDEST
  /// entries — never `.clear()` the whole set, which would let an
  /// offline-deleted row resurrect after a cloud merge.
  static final LinkedHashSet<String> _deletedKeys = LinkedHashSet<String>();

  static const int _tombstoneCap = 2000;

  /// External hook: realtime soft-delete handler can mark a key without
  /// touching local state directly. The next reconcile's `_mergeById` will
  /// drop the local row whose key matches.
  static void markTombstone(String key) => _recordTombstone(key);

  /// Add one tombstone key. If already present, bump it to MRU. Evict oldest
  /// until size ≤ cap.
  static void _recordTombstone(String key) {
    if (key.isEmpty) return;
    _deletedKeys.remove(key);
    _deletedKeys.add(key);
    while (_deletedKeys.length > _tombstoneCap) {
      _deletedKeys.remove(_deletedKeys.first);
    }
  }

  static void _recordTombstones(Iterable<String> keys) {
    for (final k in keys) {
      _recordTombstone(k);
    }
  }

  /// Evict oldest entries until under cap. Used after hydration when the
  /// persisted set is larger than the current cap (e.g. cap was lowered).
  static void _trimTombstones() {
    while (_deletedKeys.length > _tombstoneCap) {
      _deletedKeys.remove(_deletedKeys.first);
    }
  }

  // ── Sync cursors (per-table last_synced_at for incremental pulls) ─────────

  /// In-memory cache of all cursors. Keyed `"$familyId:$table"` → ISO string.
  /// Lazy-loaded on first read; persisted on every write so a crash never
  /// loses more than the in-flight pull.
  static Map<String, String>? _cursors;

  static String _cursorKey(String familyId, String table) =>
      '$familyId:$table';

  static Future<Map<String, String>> _loadCursors() async {
    _cursors ??= await (await resolvedLocalPersistence()).readCursors();
    return _cursors!;
  }

  /// Cursors that apply to [familyId] and a table the client treats as
  /// incremental-eligible. Tables without a cursor entry → full pull.
  static Future<Map<String, DateTime>> _cursorsForFamily(String familyId) async {
    final all = await _loadCursors();
    final out = <String, DateTime>{};
    final prefix = '$familyId:';
    for (final entry in all.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final table = entry.key.substring(prefix.length);
      if (!CloudSyncScope.incrementalEligibleTables.contains(table)) continue;
      final ts = DateTime.tryParse(entry.value);
      if (ts != null) out[table] = ts;
    }
    return out;
  }

  /// Update cursors from the latest cloud response. For each incremental
  /// table that has rows in the response, advance the cursor to
  /// `max(updated_at)`. Rows with `deleted_at != null` count too — their
  /// updated_at is set by `softDeleteRows`, so a soft-delete bumps the cursor.
  static Future<void> _advanceCursors(
    String familyId,
    Map<String, dynamic> cloudData,
    Set<String> incrementalTables,
  ) async {
    if (incrementalTables.isEmpty) return;
    final cursors = await _loadCursors();
    var dirty = false;
    for (final table in incrementalTables) {
      final rows = cloudData[table];
      if (rows is! List || rows.isEmpty) continue;
      DateTime? maxTs;
      for (final row in rows) {
        if (row is! Map) continue;
        final raw = row['updated_at'];
        DateTime? ts;
        if (raw is String && raw.isNotEmpty) {
          ts = DateTime.tryParse(raw);
        } else if (raw is DateTime) {
          ts = raw;
        }
        if (ts == null) continue;
        if (maxTs == null || ts.isAfter(maxTs)) maxTs = ts;
      }
      if (maxTs == null) continue;
      final key = _cursorKey(familyId, table);
      final iso = maxTs.toUtc().toIso8601String();
      if (cursors[key] != iso) {
        cursors[key] = iso;
        dirty = true;
      }
    }
    if (dirty) {
      await (await resolvedLocalPersistence()).writeCursors(cursors);
    }
  }

  /// Drop all cursors. Called on logout / wipe so a different account starts
  /// from a clean slate.
  static Future<void> _clearCursors() async {
    _cursors = <String, String>{};
    await (await resolvedLocalPersistence()).writeCursors(_cursors!);
  }

  static AppDB get db => _cache ?? AppDB.empty();

  static void _debugCatch(String context, Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('[DatabaseService] $context: $e\n$st');
    }
  }

  /// Pantry writes are limited to family owner/admin (matches Supabase RLS).
  static bool _canSyncPantryItems(AppDB db, String familyId, String? userId) {
    if (userId == null || userId.isEmpty) return false;
    for (final f in db.families) {
      if (f.id == familyId && f.ownerId == userId) return true;
    }
    for (final m in db.familyMembers) {
      if (m.familyId == familyId && m.userId == userId) {
        return m.role == Role.OWNER || m.role == Role.ADMIN;
      }
    }
    return false;
  }

  // ── Local persistence ─────────────────────────────────────────────────────

  static Future<void> _hydrateTombstonesFromPrefs(SharedPreferences prefs) async {
    try {
      final list = prefs.getStringList(_tombstoneKey);
      if (list != null && list.isNotEmpty) {
        _deletedKeys.clear();
        // Preserve order; oldest first since we'll evict from front.
        for (final k in list) {
          _deletedKeys.add(k);
        }
        _trimTombstones();
      }
    } on Object catch (e, st) {
      _debugCatch('tombstones load (prefs)', e, st);
    }
  }

  static Future<void> _hydrateTombstonesFromPersistence() async {
    try {
      await (await resolvedLocalPersistence()).readTombstonesInto(_deletedKeys);
      if (_deletedKeys.length > _tombstoneCap) {
        _trimTombstones();
        await (await resolvedLocalPersistence()).writeTombstones(_deletedKeys);
      }
    } on Object catch (e, st) {
      _debugCatch('tombstones load (local store)', e, st);
    }
  }

  static Future<void> _persistTombstones() async {
    try {
      await (await resolvedLocalPersistence()).writeTombstones(_deletedKeys);
    } on Object catch (e, st) {
      _debugCatch('tombstones persist', e, st);
    }
  }

  static Future<AppDB> loadLocal() async {
    final persist = await resolvedLocalPersistence();
    if (await persist.hasStoredAppDb()) {
      await _hydrateTombstonesFromPersistence();
      _cache = await persist.readAppDb();
      return _cache!;
    }

    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_dbKey);
    if (raw == null || raw.isEmpty) {
      final legacy = prefs.getString(_legacyDbKey);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await prefs.setString(_dbKey, legacy);
        await prefs.remove(_legacyDbKey);
      }
    }

    await _hydrateTombstonesFromPrefs(prefs);

    if (raw != null && raw.isNotEmpty) {
      _cache = await loadAppDbFromPrefsJson(raw);
      await persist.writeAppDb(_cache!);
      await persist.writeTombstones(_deletedKeys);
      await prefs.remove(_dbKey);
      await prefs.remove(_legacyDbKey);
      await prefs.remove(_tombstoneKey);
      return _cache!;
    }

    _cache = AppDB.empty();
    return _cache!;
  }

  static Future<void> saveLocal(AppDB db, {AppDB? tombstoneBase}) async {
    // Track keys that disappeared (intentional deletes) so cloud merge
    // doesn't re-add them. [tombstoneBase] = state before merge (e.g. reconcile).
    final base = tombstoneBase ?? _cache;
    if (base != null) {
      final oldKeys = _collectKeys(base);
      final newKeys = _collectKeys(db);
      _recordTombstones(oldKeys.difference(newKeys));
    }
    _cache = db;
    await (await resolvedLocalPersistence()).writeAppDb(db);
    await _persistTombstones();
  }

  static Future<void> clearLocal() async {
    _cache = AppDB.empty();
    _deletedKeys.clear();
    await _clearCursors();
    await SyncOutbox.clear();
    await (await resolvedLocalPersistence()).clearAppRecords();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dbKey);
    await prefs.remove(_legacyDbKey);
    await prefs.remove(_tombstoneKey);
  }

  /// Clears cached DB state and **every** SharedPreferences key (theme, locale,
  /// notification prefs, etc.). Use for destructive "reset app data" flows;
  /// [clearLocal] is enough for normal logout.
  static Future<void> wipeAllLocalStorage() async {
    _cache = AppDB.empty();
    _deletedKeys.clear();
    _cursors = <String, String>{};
    await SyncOutbox.clear();
    await (await resolvedLocalPersistence()).deletePhysicalDatabase();
    resetResolvedLocalPersistence();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // ── Cloud sync ────────────────────────────────────────────────────────────

  /// Save locally and attempt a background cloud sync.
  static Future<void> saveAndSync(
    AppDB db,
    String familyId, {
    Set<String>? tableScope,
  }) async {
    await saveLocal(db);
    await syncToCloud(db, familyId, tableScope: tableScope);
  }

  static Map<String, dynamic> _taskRowForCloud(Task t) {
    final m = Map<String, dynamic>.from(t.toJson());
    for (final k in _tasksCloudOmit) {
      m.remove(k);
    }
    return m;
  }

  /// Shared rules for Supabase upserts (must match [syncToCloud]).
  static List<Map<String, dynamic>> sanitizeRowsForCloudUpsert(
    List<Map<String, dynamic>> rows,
    String table,
  ) {
    const keepUpdatedAt = {
      'user_locations',
      'lists',
      'list_items',
      'families',
      'tasks',
      'devotional_thoughts',
    };
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      if (keepUpdatedAt.contains(table)) {
        final u = m['updated_at'];
        if (u == null ||
            (u is String && u.isEmpty) ||
            (u is! String && u is! DateTime)) {
          m['updated_at'] = DateTime.now().toUtc().toIso8601String();
        } else if (u is DateTime) {
          m['updated_at'] = u.toUtc().toIso8601String();
        }
      } else {
        m.remove('updated_at');
      }
      // Record self-write for postgres-change echo suppression. Read the
      // updated_at we're about to send (or fall back to now for tables where
      // we drop it client-side and Postgres regenerates it).
      final rowId = m['id']?.toString() ?? '';
      if (rowId.isNotEmpty) {
        DateTime? ts;
        final outU = m['updated_at'];
        if (outU is String && outU.isNotEmpty) {
          ts = DateTime.tryParse(outU);
        } else if (outU is DateTime) {
          ts = outU;
        }
        SyncEchoTracker.record(table, rowId, ts ?? DateTime.now().toUtc());
      }
      if (table == 'families') {
        for (final k in _familiesCloudOmit) {
          m.remove(k);
        }
      }
      if (table == 'tasks') {
        for (final k in _tasksCloudOmit) {
          m.remove(k);
        }
      }
      if (table == 'events') {
        for (final k in _eventsCloudOmit) {
          m.remove(k);
        }
      }
      if (table == 'prayer_wall') {
        for (final k in _prayerWallCloudOmit) {
          m.remove(k);
        }
      }
      if (table == 'users') {
        for (final k in _usersCloudOmit) {
          m.remove(k);
        }
      }
      if (table == 'devotional_thoughts') {
        final nk = m['note_kind'];
        if (nk == null || (nk is String && nk.isEmpty)) {
          m['note_kind'] = 'thought';
        }
      }
      return m;
    }).toList();
  }

  /// Serialize **all** Supabase writes for [familyId]: [syncToCloud],
  /// [pushFamilyListsToCloudNow], and [pushFamilyTasksToCloudNow] share one queue.
  /// Without this, a targeted list push could finish first and an older full sync’s
  /// parallel `lists` upsert could complete later and overwrite fresh item state.
  static Future<void> _enqueueFamilyCloudWrite(
    String familyId,
    Future<void> Function() work,
  ) async {
    final previous = _syncTailByFamily[familyId] ?? Future<void>.value();
    final completer = Completer<void>();
    _syncTailByFamily[familyId] = completer.future;
    try {
      await previous.catchError((Object e, StackTrace st) {
        _debugCatch('queued cloud write (previous tail)', e, st);
      });
      await work();
    } finally {
      completer.complete();
      if (identical(_syncTailByFamily[familyId], completer.future)) {
        _syncTailByFamily.remove(familyId);
      }
    }
  }

  static List<ShoppingList> _familyListsForCloud(AppDB db, String familyId) =>
      db.lists.where((l) => l.familyId == familyId).toList();

  static bool _isMissingCloudTableError(Object e) {
    final msg = e.toString();
    return msg.contains('PGRST205') || msg.contains('Could not find the table');
  }

  /// List headers must exist before [list_items] rows (FK). Never run in parallel.
  static Future<void> _upsertFamilyListHeaders(
    List<ShoppingList> familyLists,
    String familyId,
  ) async {
    if (familyLists.isEmpty) return;
    final headerRows = familyLists
        .map((l) => Map<String, dynamic>.from({
              ...l.toCloudHeaderJson(),
              'family_id': familyId,
            }))
        .toList();
    try {
      await SupabaseService.upsertTable(
        'lists',
        sanitizeRowsForCloudUpsert(headerRows, 'lists'),
      );
    } on Object catch (e, st) {
      debugPrint('[DatabaseService] lists upsert failed: $e\n$st');
      rethrow;
    }
  }

  static Future<void> _upsertFamilyListItems(
    List<ShoppingList> familyLists,
    String familyId,
  ) async {
    final itemRows = ListItemsCloud.flattenFromLists(familyLists, familyId)
        .map((i) => {...i.toJson(), 'family_id': familyId})
        .toList();
    if (itemRows.isEmpty) return;
    try {
      await SupabaseService.upsertTable(
        'list_items',
        sanitizeRowsForCloudUpsert(itemRows, 'list_items'),
      );
    } on Object catch (e, st) {
      debugPrint('[DatabaseService] list_items upsert failed: $e\n$st');
      rethrow;
    }
  }

  static Future<void> _syncFamilyListsBundleToCloud(
    AppDB db,
    String familyId, {
    required bool pushHeaders,
    required bool pushItems,
  }) async {
    final familyLists = _familyListsForCloud(db, familyId);
    final listIds = familyLists.map((l) => l.id).toSet();

    if (pushHeaders) {
      try {
        await _upsertFamilyListHeaders(familyLists, familyId);
      } on Object catch (e, st) {
        if (_isMissingCloudTableError(e)) return;
        _debugCatch('list headers push', e, st);
      }
      await _deleteRemovedRows('lists', listIds, familyId);
      await _softDeleteListItemsForTombstonedLists(familyId, listIds);
    }

    if (!pushItems) return;

    // FK: parent list row must exist before line items (also covers item-only push).
    try {
      await _upsertFamilyListHeaders(familyLists, familyId);
    } on Object catch (e, st) {
      if (_isMissingCloudTableError(e)) return;
      _debugCatch('list headers before items', e, st);
      return;
    }

    try {
      await _upsertFamilyListItems(familyLists, familyId);
    } on Object catch (e, st) {
      if (_isMissingCloudTableError(e)) return;
      _debugCatch('list_items push', e, st);
      return;
    }
    final itemIds = ListItemsCloud.flattenFromLists(familyLists, familyId)
        .map((r) => r.id)
        .toSet();
    await _deleteRemovedRows('list_items', itemIds, familyId);
    await _softDeleteListItemsForTombstonedLists(familyId, listIds);
  }

  /// Await after list edits so checked state reaches Supabase before the next pull
  /// (same idea as [pushFamilyTasksToCloudNow]).
  static Future<void> pushFamilyListsToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    await _enqueueFamilyCloudWrite(familyId, () async {
      await _syncFamilyListsBundleToCloud(
        db,
        familyId,
        pushHeaders: true,
        pushItems: true,
      );
    });
  }

  /// Item-only push after check/uncheck or line edits (headers upserted first for FK).
  static Future<void> pushFamilyListItemsToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    await _enqueueFamilyCloudWrite(familyId, () async {
      await _syncFamilyListsBundleToCloud(
        db,
        familyId,
        pushHeaders: false,
        pushItems: true,
      );
    });
  }

  static Map<String, dynamic> _choreRowForCloud(Chore c) {
    final m = Map<String, dynamic>.from(c.toJson());
    for (final k in _choresCloudOmit) {
      m.remove(k);
    }
    return m;
  }

  /// Upserts all tasks for [familyId] and applies tombstone deletes. Await after
  /// saves so new tasks reach Supabase even when the full background sync fails
  /// (RLS batch issues, payload size, or tasks from other families polluting the batch).
  /// Scoped push through the per-family write queue (tasks/lists use specialized helpers).
  static Future<void> pushTablesToCloudNow(
    AppDB db,
    String familyId,
    Set<String> tables,
  ) async {
    if (!SupabaseService.isConfigured || tables.isEmpty) return;
    await _enqueueFamilyCloudWrite(familyId, () async {
      await _syncToCloud(db, familyId, tableScope: tables);
    });
  }

  static Future<void> pushFamilyTasksToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    await _enqueueFamilyCloudWrite(familyId, () async {
      final familyTasks = db.tasks.where((t) => t.familyId == familyId).toList();
      final localIds = familyTasks.map((t) => t.id).toSet();
      const chunk = 40;
      for (var i = 0; i < familyTasks.length; i += chunk) {
        final slice = familyTasks.sublist(
            i, math.min(i + chunk, familyTasks.length));
        final rows = slice.map(_taskRowForCloud).toList();
        try {
          await SupabaseService.upsertTable(
            'tasks',
            sanitizeRowsForCloudUpsert(rows, 'tasks'),
          );
        } on Object catch (e, st) {
          debugPrint('[DatabaseService] tasks chunk upsert failed, retry per row: $e\n$st');
          for (final t in slice) {
            try {
              await SupabaseService.upsertTable(
                'tasks',
                sanitizeRowsForCloudUpsert([_taskRowForCloud(t)], 'tasks'),
              );
            } on Object catch (e2, st2) {
              debugPrint('[DatabaseService] task ${t.id} sync failed: $e2\n$st2');
            }
          }
        }
      }
      await _deleteRemovedRows('tasks', localIds, familyId);
    });
  }

  /// Push local data to Supabase. Safe to fire-and-forget.
  /// Syncs for the same [familyId] are serialized so concurrent [saveAndSync]
  /// calls cannot leave Supabase with an older snapshot.
  static Future<void> syncToCloud(
    AppDB db,
    String familyId, {
    Set<String>? tableScope,
  }) async {
    if (!SupabaseService.isConfigured) return;
    await _enqueueFamilyCloudWrite(familyId, () async {
      try {
        await _syncToCloud(db, familyId, tableScope: tableScope);
      } on Object catch (e, st) {
        AppLog.sync('DatabaseService: Cloud sync failed: $e\n$st');
      }
    });
  }

  static Map<String, dynamic> _devotionalEntryRowForCloud(
    DevotionalEntry d,
    String familyId,
  ) {
    final m = Map<String, dynamic>.from({...d.toJson(), 'family_id': familyId});
    m.remove('user_prayer');
    return m;
  }

  static Future<void> _syncToCloud(
    AppDB db,
    String familyId, {
    Set<String>? tableScope,
  }) async {
    bool pick(String table) =>
        tableScope == null || tableScope.contains(table);
    Future<void> up(String table, List<Map<String, dynamic>> rows,
        {String onConflict = 'id'}) async {
      if (rows.isNotEmpty) {
        try {
          await SupabaseService.upsertTable(
              table, sanitizeRowsForCloudUpsert(rows, table), onConflict: onConflict);
        } on Object catch (e, st) {
          final msg = e.toString();
          if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
            return; // table not in schema — skip quietly
          }
          AppLog.sync('DatabaseService: Failed to sync $table: $e\n$st');
        }
      }
    }

    final fid = familyId;
    final currentUserId = SupabaseService.currentUser?.id;
    String mealPlanCreatedByFallback() {
      for (final f in db.families) {
        if (f.id == fid && f.ownerId.isNotEmpty) return f.ownerId;
      }
      return currentUserId ?? '';
    }

    // Helper to upsert then delete removed rows in one step
    Future<void> upAndClean(String table, List<Map<String, dynamic>> rows,
        Set<String> localIds, {String onConflict = 'id'}) async {
      await up(table, rows, onConflict: onConflict);
      await _deleteRemovedRows(table, localIds, fid);
    }

    Future<void> upAndCleanUser(
      String table,
      List<Map<String, dynamic>> rows,
      Set<String> localIds, {
      required String userId,
      String onConflict = 'id',
    }) async {
      await up(table, rows, onConflict: onConflict);
      await _deleteRemovedUserRows(table, localIds, userId);
    }

    // Core identity tables first (other tables may reference these)
    await Future.wait([
      up('users', db.users.map((u) => u.toJson()).toList()),
      up('families', db.families.map((f) => f.toJson()).toList()),
      _syncFamilyMembers(db, fid),
    ]);

    // All other tables in parallel — they're independent of each other
    await Future.wait([
      if (pick('tasks'))
        upAndClean(
            'tasks',
            db.tasks
                .where((t) => t.familyId == fid)
                .map((t) => t.toJson())
                .toList(),
            db.tasks.where((t) => t.familyId == fid).map((t) => t.id).toSet()),
      if (pick('events'))
        upAndClean('events',
            db.events.map((e) => {...e.toJson(), 'family_id': fid}).toList(),
            db.events.map((e) => e.id).toSet()),
      if (pick('recipes'))
        upAndClean(
            'recipes',
            db.recipes
                .map((r) {
                  final row = Map<String, dynamic>.from(r.toJson());
                  row['family_id'] = fid;
                  for (final k in _recipeCloudOmit) {
                    row.remove(k);
                  }
                  final cb = row['created_by'];
                  final cbStr = cb is String ? cb : '';
                  if (cbStr.isEmpty) {
                    final fb = (currentUserId != null &&
                            currentUserId.isNotEmpty)
                        ? currentUserId
                        : mealPlanCreatedByFallback();
                    if (fb.isNotEmpty) row['created_by'] = fb;
                  }
                  return row;
                })
                .toList(),
            db.recipes.map((r) => r.id).toSet()),
      if (pick('meal_plans'))
        upAndClean(
            'meal_plans',
            db.mealPlans
                .where((m) => m.familyId == fid)
                .map((m) {
                  final row = Map<String, dynamic>.from(m.toJson());
                  row['family_id'] = fid;
                  for (final k in _mealPlanCloudOmit) {
                    row.remove(k);
                  }
                  final cb = row['created_by'];
                  final cbStr = cb is String ? cb : '';
                  if (cbStr.isEmpty) {
                    final fb = (currentUserId != null && currentUserId.isNotEmpty)
                        ? currentUserId
                        : mealPlanCreatedByFallback();
                    if (fb.isNotEmpty) row['created_by'] = fb;
                  }
                  return row;
                })
                .toList(),
            db.mealPlans.where((m) => m.familyId == fid).map((m) => m.id).toSet()),
      if (pick('lists') || pick('list_items'))
        _syncFamilyListsBundleToCloud(
          db,
          fid,
          pushHeaders: pick('lists'),
          pushItems: pick('lists') || pick('list_items'),
        ),
      if (pick('devotionals'))
        upAndClean(
            'devotionals',
            db.devotionals
                .map((d) => _devotionalEntryRowForCloud(d, fid))
                .toList(),
            db.devotionals.map((d) => d.id).toSet()),
      if (pick('devotional_thoughts'))
        (() async {
          final thoughtRows = db.devotionalThoughts
              .where((t) => t.familyId == fid)
              .map((t) => {...t.toJson(), 'family_id': fid})
              .toList();
          final thoughtIds = db.devotionalThoughts
              .where((t) => t.familyId == fid)
              .map((t) => t.id)
              .toSet();
          if (thoughtRows.isNotEmpty) {
            try {
              await SupabaseService.upsertTable(
                'devotional_thoughts',
                sanitizeRowsForCloudUpsert(thoughtRows, 'devotional_thoughts'),
                onConflict: 'devotional_id,user_id,note_kind',
              );
            } on Object catch (e, st) {
              final msg = e.toString();
              if (!msg.contains('PGRST205') &&
                  !msg.contains('Could not find the table')) {
                debugPrint(
                    '[DatabaseService] Failed to sync devotional_thoughts: $e\n$st');
              }
            }
          }
          await _deleteRemovedRows('devotional_thoughts', thoughtIds, fid);
        })(),
      if (currentUserId != null &&
          (pick('fitness') || pick('fitness_plans')))
        Future.wait([
          if (pick('fitness'))
            upAndCleanUser(
              'fitness',
              db.fitness
                  .where((f) => f.userId == currentUserId)
                  .map((f) => {...f.toJson(), 'family_id': fid}).toList(),
              db.fitness
                  .where((f) => f.userId == currentUserId)
                  .map((f) => f.id)
                  .toSet(),
              userId: currentUserId,
            ),
          if (pick('fitness_plans'))
            upAndCleanUser(
              'fitness_plans',
              db.fitnessPlans
                  .whereType<Map>()
                  .where((p) => p['user_id'] == currentUserId)
                  .map((p) {
                    final row = fitnessPlanRowForCloud(
                      Map<String, dynamic>.from(p), // FIXED: whereType<Map> element
                      fid,
                    );
                    for (final k in _fitnessPlansCloudOmit) {
                      row.remove(k);
                    }
                    return row;
                  })
                  .toList(),
              db.fitnessPlans
                  .whereType<Map>()
                  .where((p) => p['user_id'] == currentUserId)
                  .map((p) => fitnessPlanCloudRowId(p, fid))
                  .toSet(),
              userId: currentUserId,
            ),
        ])
      else
        Future.value(),
      if (pick('fitness_logs'))
        upAndClean(
          'fitness_logs',
          db.fitnessLogs
              .where((l) => l.familyId == fid && l.userId == SupabaseService.currentUser?.id)
              .map((l) => {...l.toJson(), 'family_id': fid}).toList(),
          db.fitnessLogs
              .where((l) => l.familyId == fid && l.userId == SupabaseService.currentUser?.id)
              .map((l) => l.id)
              .toSet(),
        ),
      // Strong integration: family-visible workouts, owner-only writes via RLS
      if (pick('workout_sessions'))
        upAndClean(
          'workout_sessions',
          db.workoutSessions
              .where((s) => s.familyId == fid && s.userId == SupabaseService.currentUser?.id)
              .map((s) {
                final row = Map<String, dynamic>.from(s.toJson());
                row['family_id'] = fid;
                for (final k in _workoutSessionCloudOmit) {
                  row.remove(k);
                }
                return row;
              })
              .toList(),
          db.workoutSessions
              .where((s) => s.familyId == fid && s.userId == SupabaseService.currentUser?.id)
              .map((s) => s.id)
              .toSet(),
        ),
      if (pick('workout_exercises'))
        upAndClean(
          'workout_exercises',
          db.workoutExercises
              .where((e) => e.familyId == fid && e.userId == SupabaseService.currentUser?.id)
              .map((e) {
                final row = Map<String, dynamic>.from(e.toJson());
                row['family_id'] = fid;
                for (final k in _workoutExerciseCloudOmit) {
                  row.remove(k);
                }
                return row;
              })
              .toList(),
          db.workoutExercises
              .where((e) => e.familyId == fid && e.userId == SupabaseService.currentUser?.id)
              .map((e) => e.id)
              .toSet(),
        ),
      if (pick('workout_sets'))
        upAndClean(
          'workout_sets',
          db.workoutSets
              .where((set) => set.familyId == fid && set.userId == SupabaseService.currentUser?.id)
              .map((set) => {...set.toJson(), 'family_id': fid}).toList(),
          db.workoutSets
              .where((set) => set.familyId == fid && set.userId == SupabaseService.currentUser?.id)
              .map((set) => set.id)
              .toSet(),
        ),
      if (pick('exercise_prs') && currentUserId != null)
        upAndCleanUser(
          'exercise_prs',
          db.exercisePrs
              .where((p) => p.familyId == fid && p.userId == currentUserId)
              .map((p) => p.toJson())
              .toList(),
          db.exercisePrs
              .where((p) => p.familyId == fid && p.userId == currentUserId)
              .map((p) => p.id)
              .toSet(),
          userId: currentUserId,
        ),
      if (pick('budget_categories'))
        upAndClean(
            'budget_categories',
            db.budgetCategories.map((b) => {...b.toJson(), 'family_id': fid}).toList(),
            db.budgetCategories.map((b) => b.id).toSet()),
      if (pick('budget_entries'))
        upAndClean(
            'budget_entries',
            db.budgetEntries.map((b) => {...b.toJson(), 'family_id': fid}).toList(),
            db.budgetEntries.map((b) => b.id).toSet()),
      if (pick('transactions'))
        upAndClean(
            'transactions',
            db.transactions.map((t) => {...t.toJson(), 'family_id': fid}).toList(),
            db.transactions.map((t) => t.id).toSet()),
      if (pick('ai_history') && currentUserId != null)
        upAndCleanUser(
          'ai_history',
          db.aiHistory
              .where((a) => a.userId == currentUserId)
              .map((a) => a.toJson())
              .toList(),
          db.aiHistory
              .where((a) => a.userId == currentUserId)
              .map((a) => a.id)
              .toSet(),
          userId: currentUserId,
        ),
      if (pick('daily_habits') && currentUserId != null)
        upAndCleanUser(
          'daily_habits',
          db.dailyHabits
              .where((h) => h.userId == currentUserId)
              .map((h) => h.toJson())
              .toList(),
          db.dailyHabits
              .where((h) => h.userId == currentUserId)
              .map((h) => h.id)
              .toSet(),
          userId: currentUserId,
        ),
      if (currentUserId != null && pick('daily_habit_completions'))
        upAndCleanUser(
          'daily_habit_completions',
          db.dailyHabitCompletions
              .where((c) => c.userId == currentUserId)
              .map((c) {
                final habitFam =
                    db.dailyHabits.firstWhereOrNull((h) => h.id == c.habitId)?.familyId;
                final fam = (habitFam != null && habitFam.isNotEmpty)
                    ? habitFam
                    : fid;
                return {...c.toJson(), 'family_id': fam};
              })
              .toList(),
          db.dailyHabitCompletions
              .where((c) => c.userId == currentUserId)
              .map((c) => c.id)
              .toSet(),
          userId: currentUserId,
        )
      else
        Future.value(),
      if (pick('chores'))
        upAndClean(
            'chores',
            db.chores
                .where((c) => c.familyId == fid)
                .map((c) => _choreRowForCloud(c))
                .toList(),
            db.chores.where((c) => c.familyId == fid).map((c) => c.id).toSet()),
      if (pick('chore_completions'))
        upAndClean(
            'chore_completions',
            db.choreCompletions.map((c) => c.toJson()).toList(),
            db.choreCompletions.map((c) => c.id).toSet()),
      if (pick('polls'))
        upAndClean(
            'polls',
            db.polls.map((p) => {...p.toJson(), 'family_id': fid}).toList(),
            db.polls.map((p) => p.id).toSet()),
      if (pick('poll_votes'))
        upAndClean(
            'poll_votes',
            db.pollVotes.map((v) => v.toJson()).toList(),
            db.pollVotes.map((v) => v.id).toSet()),
      if (pick('reward_items'))
        upAndClean(
            'reward_items',
            db.rewardItems.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
            db.rewardItems.map((r) => r.id).toSet()),
      if (pick('reward_redemptions'))
        upAndClean(
            'reward_redemptions',
            db.rewardRedemptions.map((r) => r.toJson()).toList(),
            db.rewardRedemptions.map((r) => r.id).toSet()),
      if (pick('savings_goals'))
        upAndClean(
            'savings_goals',
            db.savingsGoals.map((g) => {...g.toJson(), 'family_id': fid}).toList(),
            db.savingsGoals.map((g) => g.id).toSet()),
      if (pick('prayer_wall'))
        upAndClean(
            'prayer_wall',
            db.prayerWall.map((p) => {...p.toJson(), 'family_id': fid}).toList(),
            db.prayerWall.map((p) => p.id).toSet()),
      if (pick('special_dates'))
        upAndClean(
            'special_dates',
            db.specialDates.map((s) => {...s.toJson(), 'family_id': fid}).toList(),
            db.specialDates.map((s) => s.id).toSet()),
      if (pick('family_photos'))
        upAndClean(
            'family_photos',
            db.familyPhotos.map((p) => {...p.toJson(), 'family_id': fid}).toList(),
            db.familyPhotos.map((p) => p.id).toSet()),
      if (pick('milestones'))
        upAndClean(
            'milestones',
            db.milestones.map((m) => {...m.toJson(), 'family_id': fid}).toList(),
            db.milestones.map((m) => m.id).toSet()),
      if (pick('saved_places'))
        upAndClean(
            'saved_places',
            db.savedPlaces.map((s) => {...s.toJson(), 'family_id': fid}).toList(),
            db.savedPlaces.map((s) => s.id).toSet()),
      if (pick('user_locations'))
        upAndClean(
            'user_locations',
            db.userLocations.map((u) => u.toJson()).toList(),
            db.userLocations.map((u) => u.id).toSet()),
      if (pick('messages'))
        upAndClean(
            'messages',
            db.messages.map((m) => {...m.toJson(), 'family_id': fid}).toList(),
            db.messages.map((m) => m.id).toSet()),
      if (pick('health_records'))
        upAndClean(
            'health_records',
            db.healthRecords.map((h) => {...h.toJson(), 'family_id': fid}).toList(),
            db.healthRecords.map((h) => h.id).toSet()),
      if (pick('period_cycles'))
        upAndClean(
            'period_cycles',
            db.periodCycles.map((c) => c.toJson()).toList(),
            db.periodCycles.map((c) => c.id).toSet()),
      if (pick('period_symptoms'))
        upAndClean(
            'period_symptoms',
            db.periodSymptoms.map((s) => s.toJson()).toList(),
            db.periodSymptoms.map((s) => s.id).toSet()),
      if (pick('external_calendars'))
        upAndClean(
            'external_calendars',
            db.externalCalendars.map((c) => {...c.toJson(), 'family_id': fid}).toList(),
            db.externalCalendars.map((c) => c.id).toSet()),
      if (pick('rewards'))
        upAndClean(
            'rewards',
            db.rewards.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
            db.rewards.map((r) => r.id).toSet()),
      if (pick('reading_plans'))
        upAndClean(
            'reading_plans',
            db.readingPlans.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
            db.readingPlans.map((r) => r.id).toSet()),
      if (pick('reading_plan_progress'))
        upAndClean(
            'reading_plan_progress',
            db.readingPlanProgress.map((r) => r.toJson()).toList(),
            db.readingPlanProgress.map((r) => r.id).toSet()),
      if (pick('pantry_items') && _canSyncPantryItems(db, fid, currentUserId))
        upAndClean(
            'pantry_items',
            db.pantryItems
                .where((p) => p.familyId == fid)
                .map((p) => p.toJson())
                .toList(),
            db.pantryItems.where((p) => p.familyId == fid).map((p) => p.id).toSet()),
      if (pick('family_activity_logs'))
        upAndClean(
            'family_activity_logs',
            db.familyActivityLogs
                .where((a) => a.familyId == fid)
                .map((a) => a.toJson())
                .toList(),
            db.familyActivityLogs
                .where((a) => a.familyId == fid)
                .map((a) => a.id)
                .toSet()),
      if (pick('wellness_check_ins'))
        upAndClean(
            'wellness_check_ins',
            db.wellnessCheckIns
                .where((w) => w.familyId == fid)
                .map((w) => w.toJson())
                .toList(),
            db.wellnessCheckIns
                .where((w) => w.familyId == fid)
                .map((w) => w.id)
                .toSet()),
    ]);
  }

  /// Collapse duplicate `(user_id, family_id)` rows, keeping the highest role.
  /// Join-with-code used to append MEMBER after reconcile had OWNER; upsert then
  /// overwrote OWNER in Postgres with MEMBER.
  static List<FamilyMember> dedupeFamilyMembers(List<FamilyMember> members) {
    int rank(Role r) {
      switch (r) {
        case Role.OWNER:
          return 3;
        case Role.ADMIN:
          return 2;
        case Role.MEMBER:
          return 1;
      }
    }

    FamilyMember prefer(FamilyMember a, FamilyMember b) =>
        rank(b.role) > rank(a.role) ? b : a;

    final map = <String, FamilyMember>{};
    for (final m in members) {
      final k = m.mergeKey;
      map[k] = map[k] == null ? m : prefer(map[k]!, m);
    }
    return map.values.toList();
  }

  /// Upsert family members and delete removed ones (composite key: userId+familyId).
  static Future<void> _syncFamilyMembers(AppDB db, String familyId) async {
    final members = dedupeFamilyMembers(db.familyMembers);
    if (members.isNotEmpty) {
      try {
        await SupabaseService.upsertTable(
          'family_members',
          members.map((m) => m.toJson()).toList(),
          onConflict: 'user_id,family_id',
        );
      } on Object catch (e, st) {
        debugPrint('[DatabaseService] Failed to sync family_members: $e\n$st');
      }
    }
    // Delete members removed locally
    try {
      final cloudRows = await SupabaseService.client
          .from('family_members')
          .select('user_id, family_id')
          .eq('family_id', familyId);
      final localKeys = members
          .where((m) => m.familyId == familyId)
          .map((m) => m.mergeKey)
          .toSet();
      for (final row in (cloudRows as List)) {
        final uid = row['user_id'] as String?;
        final fid = row['family_id'] as String?;
        if (uid == null || fid == null) continue;
        final key = '${uid}_$fid';
        // Never delete server members just because this device has a stale /
        // partial list (that wiped other people's rows). Only delete when the
        // user explicitly removed someone and we recorded a tombstone.
        if (!localKeys.contains(key) && _deletedKeys.contains(key)) {
          await SupabaseService.deleteRows('family_members', {
            'user_id': uid,
            'family_id': fid,
          });
        }
      }
    } on Object catch (e, st) {
      debugPrint('[DatabaseService] Failed to delete removed family_members: $e\n$st');
    }
  }

  /// Soft-delete [list_items] rows whose parent list was tombstoned locally.
  static Future<void> _softDeleteListItemsForTombstonedLists(
    String familyId,
    Set<String> aliveListIds,
  ) async {
    if (!SupabaseService.isConfigured || _deletedKeys.isEmpty) return;
    final tombstonedListIds =
        _deletedKeys.where((k) => !aliveListIds.contains(k)).toSet();
    if (tombstonedListIds.isEmpty) return;
    try {
      final rows = await SupabaseService.client
          .from('list_items')
          .select('id, list_id')
          .eq('family_id', familyId)
          .isFilter('deleted_at', null);
      for (final row in rows as List) {
        final id = row['id']?.toString() ?? '';
        final listId = row['list_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (!tombstonedListIds.contains(listId) &&
            !_deletedKeys.contains(id)) {
          continue;
        }
        await SyncOutbox.enqueue(
          table: 'list_items',
          rowKey: id,
          op: OutboxOp.softDelete,
          payload: {'id': id},
        );
      }
      unawaited(SyncOutbox.drain());
    } on Object catch (e, st) {
      if (_isMissingCloudTableError(e)) return;
      debugPrint(
        '[DatabaseService] list_items cascade delete failed: $e\n$st',
      );
    }
  }

  /// Delete cloud rows for a family-scoped table that were intentionally
  /// removed locally (tracked in [_deletedKeys]).
  ///
  /// Previously this deleted ANY cloud row not present locally, which caused
  /// server-generated content (e.g. daily devotionals created by the
  /// daily-devotional edge function) to be wiped before the app ever saw it.
  /// Now it only deletes rows whose keys are in [_deletedKeys].
  static Future<void> _deleteRemovedRows(
    String table, Set<String> localIds, String familyId,
  ) async {
    if (!SupabaseService.isConfigured || _deletedKeys.isEmpty) return;
    final softDelete = CloudSyncScope.softDeleteTables.contains(table);
    try {
      final selectQ = SupabaseService.client
          .from(table)
          .select('id')
          .eq('family_id', familyId);
      // Skip already-soft-deleted rows so we don't re-touch them every sync.
      final cloudRows = softDelete
          ? await selectQ.isFilter('deleted_at', null)
          : await selectQ;
      final cloudIds = (cloudRows as List).map((r) => r['id'] as String).toSet();
      // Only delete cloud rows that were intentionally deleted locally
      final removed = cloudIds.intersection(_deletedKeys);
      for (final id in removed) {
        // Route through the outbox so a per-row failure (RLS, transient
        // 5xx) gets retried with backoff instead of silently lost.
        await SyncOutbox.enqueue(
          table: table,
          rowKey: id,
          op: softDelete ? OutboxOp.softDelete : OutboxOp.hardDelete,
          payload: {'id': id},
        );
      }
      if (removed.isNotEmpty) {
        // Best-effort immediate drain; failures stay queued for later.
        unawaited(SyncOutbox.drain());
      }
    } on Object catch (e, st) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e\n$st');
    }
  }

  /// Delete cloud rows for a user-scoped table that were intentionally removed
  /// locally (tracked in [_deletedKeys]).
  ///
  /// This is the non-family variant for tables that don't have `family_id`.
  static Future<void> _deleteRemovedUserRows(
    String table,
    Set<String> localIds,
    String userId,
  ) async {
    if (!SupabaseService.isConfigured || _deletedKeys.isEmpty) return;
    final softDelete = CloudSyncScope.softDeleteTables.contains(table);
    try {
      final selectQ = SupabaseService.client
          .from(table)
          .select('id')
          .eq('user_id', userId);
      final cloudRows = softDelete
          ? await selectQ.isFilter('deleted_at', null)
          : await selectQ;
      final cloudIds = (cloudRows as List)
          .map((r) => r['id'] as String)
          .toSet();
      final removed = cloudIds.intersection(_deletedKeys);
      for (final id in removed) {
        await SyncOutbox.enqueue(
          table: table,
          rowKey: id,
          op: softDelete ? OutboxOp.softDelete : OutboxOp.hardDelete,
          payload: {'id': id},
        );
      }
      if (removed.isNotEmpty) {
        unawaited(SyncOutbox.drain());
      }
    } on Object catch (e, st) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e\n$st');
    }
  }

  // ── Cloud reconcile ───────────────────────────────────────────────────────

  /// Fetch cloud data, merge with local DB, and persist the result.
  /// [lastError] is set if a non-fatal parse error occurred (for debugging).
  static String? lastError;

  /// Ensures every [family_members] row for [familyId] has a matching [users]
  /// row (tasks/chores join on `users` for names). Fetches missing profiles
  /// from Supabase, then stubs from `display_name` so UI never shows generic
  /// "Member" for everyone after a partial sync.
  static Future<AppDB> backfillMissingUsersForFamily(AppDB db, String familyId) async {
    final memberIds = <String>{};
    for (final m in db.familyMembers) {
      if (m.familyId == familyId) memberIds.add(m.userId);
    }
    final missing = memberIds
        .where((id) => !db.users.any((u) => u.id == id))
        .toList();
    if (missing.isEmpty) return db;

    FamilyMember? fmFor(String uid) {
      for (final m in db.familyMembers) {
        if (m.userId == uid && m.familyId == familyId) return m;
      }
      return null;
    }

    String stubName(FamilyMember? fm) {
      final d = fm?.displayName?.trim();
      if (d != null && d.isNotEmpty) return d;
      return 'Family member';
    }

    var users = List<User>.from(db.users);
    final have = users.map((u) => u.id).toSet();

    try {
      if (SupabaseService.isConfigured) {
        final response = await SupabaseService.client
            .from('users')
            .select()
            .inFilter('id', missing);
        final rows = response as List;
        for (final raw in rows) {
          if (raw is! Map) continue;
          try {
            final u = User.fromJson(Map<String, dynamic>.from(raw));
            if (u.id.isEmpty || have.contains(u.id)) continue;
            users.add(u);
            have.add(u.id);
          } on Object catch (e, st) {
            _debugCatch('backfill User.fromJson', e, st);
          }
        }
      }
    } on Object catch (e, st) {
      debugPrint('[DatabaseService] backfillMissingUsersForFamily fetch: $e\n$st');
    }

    for (final id in missing) {
      if (have.contains(id)) continue;
      users.add(User(id: id, name: stubName(fmFor(id)), email: ''));
      have.add(id);
    }

    return db.copyWith(users: users);
  }

  static Future<AppDB> reconcileCloud(
    AppDB local,
    String familyId, {
    Set<String>? pullTables,
    /// Called **after** the cloud HTTP fetch completes, to merge against the
    /// latest in-memory DB. Prevents losing edits (e.g. a new list) made while
    /// the network request was in flight — the initial [local] snapshot can be
    /// stale by tens of seconds on slow links or right after a deferred startup pull.
    AppDB Function()? getLocalAfterFetch,
  }) async {
    lastError = null;
    if (!SupabaseService.isConfigured) return local;
    try {
      final cursors = await _cursorsForFamily(familyId);
      // The set of tables we actually used cursors for in this pull.
      final usedCursors = <String, DateTime>{};
      for (final entry in cursors.entries) {
        // Only count cursors for tables we're about to fetch.
        if (pullTables == null ||
            pullTables.isEmpty ||
            pullTables.contains(entry.key)) {
          usedCursors[entry.key] = entry.value;
        }
      }

      final Map<String, dynamic> cloudData;
      final bool partial;
      if (pullTables != null && pullTables.isNotEmpty) {
        partial = true;
        cloudData = await SupabaseService.fetchTablesForFamily(
          familyId,
          pullTables,
          cursors: usedCursors.isEmpty ? null : usedCursors,
        );
      } else {
        partial = false;
        cloudData = await SupabaseService.fetchAllTables(
          familyId,
          cursors: usedCursors.isEmpty ? null : usedCursors,
        );
      }
      final localForMerge = getLocalAfterFetch?.call() ?? local;
      _pruneTombstonesAgainstCloud(
        cloudData,
        partial: partial,
        incrementalTables: usedCursors.keys.toSet(),
      );
      await _persistTombstones();
      var merged = _mergeWithCloud(localForMerge, cloudData, familyId);
      if (FieldEncryption.isReady(familyId)) {
        merged = merged.applySensitiveDecryption(familyId);
      }
      merged = await backfillMissingUsersForFamily(merged, familyId);
      await saveLocal(merged, tombstoneBase: localForMerge);
      // Advance cursors for tables we just successfully merged. For tables
      // without an existing cursor, this is the first pull — record their
      // max(updated_at) so the NEXT pull is incremental.
      final tablesToTrack = CloudSyncScope.incrementalEligibleTables
          .where((t) =>
              cloudData.containsKey(t) &&
              (pullTables == null ||
                  pullTables.isEmpty ||
                  pullTables.contains(t)))
          .toSet();
      await _advanceCursors(familyId, cloudData, tablesToTrack);
      return merged;
    } on Object catch (e, st) {
      lastError = '$e\n$st';
      return local;
    }
  }

  /// Drop tombstones once Supabase no longer has that row (delete succeeded).
  ///
  /// [incrementalTables] are tables whose cloud payload is a `gte(updated_at,
  /// cursor)` delta — absence of an id from such a response means "not
  /// modified since cursor", NOT "deleted". Pruning these would silently drop
  /// valid tombstones, so we skip them.
  static void _pruneTombstonesAgainstCloud(
    Map<String, dynamic> cloud, {
    bool partial = false,
    Set<String> incrementalTables = const {},
  }) {
    final fmKeys = <String>{};
    for (final m in (cloud['family_members'] as List?) ?? []) {
      if (m is Map) {
        final u = m['user_id']?.toString() ?? '';
        final f = m['family_id']?.toString() ?? '';
        if (u.isNotEmpty && f.isNotEmpty) fmKeys.add('${u}_$f');
      }
    }
    final fmRe = RegExp(
      r'^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
      caseSensitive: false,
    );
    if (!partial || cloud.containsKey('family_members')) {
      _deletedKeys.removeWhere((k) => fmRe.hasMatch(k) && !fmKeys.contains(k));
    }

    void pruneTable(String tableKey) {
      final ids = (cloud[tableKey] as List?)
              ?.map((x) => (x as Map)['id']?.toString())
              .whereType<String>()
              .toSet() ??
          {};
      final uuidRe = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      _deletedKeys.removeWhere((k) => uuidRe.hasMatch(k) && !ids.contains(k));
    }

    void maybePrune(String tableKey) {
      if (partial && !cloud.containsKey(tableKey)) return;
      if (incrementalTables.contains(tableKey)) return;
      pruneTable(tableKey);
    }

    maybePrune('tasks');
    maybePrune('events');
    maybePrune('lists');
    maybePrune('list_items');
    maybePrune('recipes');
    maybePrune('chores');
    maybePrune('devotionals');
    maybePrune('devotional_thoughts');
    maybePrune('messages');
    maybePrune('polls');
    maybePrune('family_photos');
    maybePrune('milestones');
    maybePrune('saved_places');
    maybePrune('prayer_wall');
    maybePrune('special_dates');
    maybePrune('reward_items');
    maybePrune('savings_goals');
    maybePrune('external_calendars');
    maybePrune('reading_plan_progress');
    maybePrune('pantry_items');
    maybePrune('fitness_plans');
    maybePrune('family_activity_logs');
    maybePrune('wellness_check_ins');
    // User-scoped tables
    maybePrune('fitness');
    maybePrune('daily_habit_completions');
    maybePrune('workout_sessions');
    maybePrune('workout_exercises');
    maybePrune('workout_sets');
    maybePrune('exercise_prs');
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Per-record version for last-write-wins across family devices.
  static DateTime _entityVersion(dynamic o) {
    if (o == null) return _epoch;
    if (o is ChatMessage) return o.editedAt ?? o.createdAt;
    if (o is Family) return o.updatedAt;
    if (o is Task) return o.updatedAt;
    if (o is ReadingPlanProgress) return o.lastCompletedAt ?? o.startedAt;
    try {
      final u = (o as dynamic).updatedAt;
      if (u is DateTime && u.millisecondsSinceEpoch > 0) return u;
    } on TypeError {
      // Model has no usable updatedAt.
    }
    try {
      final c = (o as dynamic).createdAt;
      if (c is DateTime) return c;
    } on TypeError {
      // Model has no createdAt.
    }
    try {
      final d = (o as dynamic).date;
      if (d is DateTime) return d;
    } on TypeError {
      // Model has no date.
    }
    try {
      final d = (o as dynamic).start;
      if (d is DateTime) return d;
    } on TypeError {
      // Model has no start.
    }
    return _epoch;
  }

  /// Merge two lists by [id] using last-write-wins on [_entityVersion].
  ///
  /// - Same id: keep whichever record has the newer [updatedAt]/createdAt/date.
  /// - Tie → prefer cloud by default so another family member's push applies;
  ///   pass [preferLocalOnTimestampTie] for nested-document rows (shopping lists).
  /// - Only in cloud: add (unless [_deletedKeys]).
  /// - Only in local: keep (offline-created).
  /// Prefer [mergeKey] when the model defines it (composite keys); otherwise [id].
  ///
  /// Uses dynamic dispatch and catches any failure — [User], [Family], and several
  /// other types have no `mergeKey`; only `TypeError` was caught before, so
  /// `NoSuchMethodError` escaped and broke cloud merge.
  static String _mergeKeyOf(dynamic item) {
    if (item == null) return '';
    try {
      final mk = (item as dynamic).mergeKey;
      if (mk != null && mk.toString().isNotEmpty) {
        return mk as String;
      }
    } on Object {
      // No mergeKey getter or invalid value — fall through to id.
    }
    try {
      final id = (item as dynamic).id;
      if (id != null) return id.toString();
    } on Object catch (e, st) {
      _debugCatch('_mergeKeyOf id fallback', e, st);
    }
    return '';
  }

  static List<T> _mergeById<T>(
    List<T> local,
    List<T> cloud, {
    /// When timestamps tie, [_mergeById] normally prefers cloud so another
    /// device’s simultaneous edit wins. Shopping lists nest line items in one
    /// JSON row — ties happen often after Postgres rounding / skew and caused
    /// cleared checked items to resurrect from an older cloud snapshot.
    bool preferLocalOnTimestampTie = false,
  }) {
    if (cloud.isEmpty && _deletedKeys.isEmpty) return local;
    final localMap = <String, T>{};
    for (final item in local) {
      try {
        localMap[_mergeKeyOf(item)] = item;
      } on TypeError catch (e, st) {
        _debugCatch('_mergeById localMap', e, st);
      }
    }
    if (local.isEmpty && _deletedKeys.isEmpty) return cloud;
    final map = <String, T>{...localMap};
    for (final item in cloud) {
      try {
        final key = _mergeKeyOf(item);
        if (_deletedKeys.contains(key)) continue;
        final loc = localMap[key];
        if (loc == null) {
          map[key] = item;
          continue;
        }
        final tc = _entityVersion(item);
        final tl = _entityVersion(loc);
        if (tc.isAfter(tl)) {
          map[key] = item;
        } else if (tl.isAfter(tc)) {
          map[key] = loc;
        } else {
          map[key] = preferLocalOnTimestampTie ? loc : item;
        }
      } on Object catch (e, st) {
        _debugCatch('_mergeById cloud item', e, st);
      }
    }
    // Drop any tombstoned key still in the merged map. The local-only-and-
    // tombstoned case happens when a realtime soft-delete event ran before
    // this merge: the row never reaches `cloud` (filtered by deleted_at IS
    // NULL) but the tombstone was registered out-of-band.
    if (_deletedKeys.isNotEmpty) {
      map.removeWhere((key, _) => _deletedKeys.contains(key));
    }
    return map.values.toList();
  }

  /// How many day→devotional links the plan has (used to avoid empty cloud
  /// rows wiping a full plan after sync — the root cause of "only day 1").
  static int _readingPlanRichness(ReadingPlan p) {
    if (p.entryIds.isNotEmpty) return p.entryIds.length;
    var n = 0;
    for (final x in p.days) {
      if (x is Map && (x['devotional_id']?.toString().isNotEmpty ?? false)) n++;
    }
    return n;
  }

  static List<ReadingPlan> _mergeReadingPlans(
    List<ReadingPlan> local,
    List<ReadingPlan> cloud,
  ) {
    if (cloud.isEmpty) return local;
    final localMap = <String, ReadingPlan>{};
    for (final p in local) {
      localMap[p.id] = p;
    }
    final map = Map<String, ReadingPlan>.from(localMap);
    for (final c in cloud) {
      try {
        if (_deletedKeys.contains(c.id)) continue;
        final loc = localMap[c.id];
        if (loc == null) {
          map[c.id] = c;
          continue;
        }
        final rl = _readingPlanRichness(loc);
        final rc = _readingPlanRichness(c);
        if (rl > 0 && rc == 0) {
          map[c.id] = loc;
          continue;
        }
        if (rc > 0 && rl == 0) {
          map[c.id] = c;
          continue;
        }
        if (rl > 0 && rc > 0 && rl != rc) {
          map[c.id] = rl >= rc ? loc : c;
          continue;
        }
        final tc = c.createdAt;
        final tl = loc.createdAt;
        if (tc.isAfter(tl)) {
          map[c.id] = c;
        } else if (tl.isAfter(tc)) {
          map[c.id] = loc;
        } else {
          map[c.id] = rc > rl ? c : loc;
        }
      } on Object catch (e, st) {
        _debugCatch('_mergeReadingPlans item', e, st);
      }
    }
    return map.values.toList();
  }

  /// Collect all merge keys from an AppDB snapshot.
  static Set<String> _collectKeys(AppDB db) {
    final keys = <String>{};
    void addAll(List items) {
      for (final item in items) {
        try {
          keys.add(_mergeKeyOf(item));
        } on TypeError catch (e, st) {
          _debugCatch('_collectKeys mergeKey', e, st);
        }
      }
    }
    addAll(db.users); addAll(db.families); addAll(db.familyMembers);
    addAll(db.tasks); addAll(db.events); addAll(db.recipes);
    addAll(db.mealPlans);
    for (final list in db.lists) {
      try {
        keys.add(_mergeKeyOf(list));
        for (final item in list.items) {
          if (item.id.isNotEmpty) keys.add(item.id);
        }
      } on TypeError catch (e, st) {
        _debugCatch('_collectKeys list items', e, st);
      }
    }
    addAll(db.devotionals);
    addAll(db.devotionalThoughts);
    addAll(db.fitness); addAll(db.budgetCategories); addAll(db.budgetEntries); addAll(db.transactions);
    addAll(db.aiHistory); addAll(db.dailyHabits); addAll(db.dailyHabitCompletions);
    addAll(db.chores); addAll(db.choreCompletions); addAll(db.polls);
    addAll(db.pollVotes); addAll(db.rewardItems); addAll(db.rewardRedemptions);
    addAll(db.savingsGoals); addAll(db.prayerWall); addAll(db.specialDates);
    addAll(db.familyPhotos); addAll(db.milestones); addAll(db.savedPlaces);
    addAll(db.userLocations); addAll(db.messages); addAll(db.healthRecords);
    addAll(db.periodCycles); addAll(db.periodSymptoms);
    addAll(db.rewards); addAll(db.readingPlans); addAll(db.readingPlanProgress); addAll(db.externalCalendars);
    addAll(db.pantryItems);
    addAll(db.familyActivityLogs);
    addAll(db.wellnessCheckIns);
    addAll(db.exercisePrs);
    for (final p in db.fitnessPlans) {
      if (p is Map) {
        keys.add('fitness_plan_${fitnessPlanStableId(p)}');
      }
    }
    return keys;
  }

  /// Normalize stored AI plan (local JSON or Supabase row) to one map shape.
  static Map<String, dynamic> _normalizeFitnessPlanMap(Map<dynamic, dynamic> raw) {
    dynamic wp = raw['weeklyPlan'] ?? raw['weekly_plan'];
    if (wp is! List) wp = <dynamic>[];
    dynamic tips = raw['tips'];
    if (tips is! List) tips = <dynamic>[];
    dynamic prof = raw['profile'];
    if (prof is! Map) prof = <String, dynamic>{};
    return {
      'summary': raw['summary']?.toString() ?? '',
      'weeklyPlan': wp,
      'tips': tips,
      'profile': Map<String, dynamic>.from(prof), // FIXED: prof is Map after guard
      'user_id': raw['user_id']?.toString() ?? '',
      'created_at': raw['created_at']?.toString() ?? '',
      'plan_id': raw['plan_id']?.toString() ?? '',
      if (raw['family_id'] != null) 'family_id': raw['family_id'].toString(),
    };
  }

  static DateTime _fitnessPlanTimestamp(Map<String, dynamic> p) {
    final s = p['created_at']?.toString();
    if (s == null || s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Merge AI fitness plans: one row per [plan_id] (or legacy per-user id), last-write-wins.
  static List<dynamic> _mergeFitnessPlans(
    List<dynamic> local,
    List<dynamic> cloud,
    String activeFamilyId,
  ) {
    bool includeCloudRow(dynamic row) {
      if (row is! Map) return false;
      final f = row['family_id']?.toString();
      return f == null || f.isEmpty || f == activeFamilyId;
    }

    bool includeLocalRow(dynamic row) {
      if (row is! Map) return false;
      final f = row['family_id']?.toString();
      return f == null || f.isEmpty || f == activeFamilyId;
    }

    final byKey = <String, Map<String, dynamic>>{};

    void upsert(Map<String, dynamic> n) {
      final k = fitnessPlanStableId(n);
      final existing = byKey[k];
      if (existing == null) {
        byKey[k] = n;
        return;
      }
      if (!_fitnessPlanTimestamp(n).isBefore(_fitnessPlanTimestamp(existing))) {
        byKey[k] = n;
      }
    }

    for (final p in local) {
      if (p is! Map || !includeLocalRow(p)) continue;
      final n = _normalizeFitnessPlanMap(p);
      final u = n['user_id'] as String? ?? '';
      if (u.isEmpty) continue;
      upsert(n);
    }

    for (final p in cloud) {
      if (p is! Map || !includeCloudRow(p)) continue;
      final n = _normalizeFitnessPlanMap(p);
      final u = n['user_id'] as String? ?? '';
      if (u.isEmpty) continue;
      upsert(n);
    }

    final list = byKey.values.toList();
    list.sort((a, b) => _fitnessPlanTimestamp(b).compareTo(_fitnessPlanTimestamp(a)));
    return list;
  }

  /// One row per (devotional, user, note_kind); canonical [id] so devices agree.
  static List<DevotionalThought> _mergeDevotionalThoughts(
    List<DevotionalThought> local,
    List<DevotionalThought> cloud,
  ) {
    DevotionalThought canonical(DevotionalThought t) {
      final sid =
          DevotionalThought.stableId(t.devotionalId, t.userId, t.kind);
      if (t.id == sid) return t;
      return DevotionalThought(
        id: sid,
        devotionalId: t.devotionalId,
        familyId: t.familyId,
        userId: t.userId,
        kind: t.kind,
        body: t.body,
        updatedAt: t.updatedAt,
      );
    }

    final map = <String, DevotionalThought>{};
    void mergeIn(DevotionalThought raw) {
      final t = canonical(raw);
      final key = '${t.devotionalId}|${t.userId}|${t.kind.wireValue}';
      final existing = map[key];
      if (existing == null) {
        map[key] = t;
        return;
      }
      final tc = _entityVersion(t);
      final te = _entityVersion(existing);
      map[key] = tc.isAfter(te)
          ? t
          : te.isAfter(tc)
              ? existing
              : t;
    }

    for (final t in local) {
      mergeIn(t);
    }
    for (final t in cloud) {
      mergeIn(t);
    }
    return map.values.toList();
  }

  static AppDB _mergeWithCloud(
    AppDB local,
    Map<String, dynamic> cloud,
    String activeFamilyId,
  ) {
    final cloudFm =
        _safeParse(cloud['family_members'], FamilyMember.fromJson);
    final membersThisFamily =
        cloudFm.where((m) => m.familyId == activeFamilyId).toList();
    final localThisFamily = local.familyMembers
        .where((m) => m.familyId == activeFamilyId)
        .toList();
    // Union local + cloud by (user_id, family_id). Cloud overwrites the same
    // key so server stays authoritative, but **partial** cloud responses (e.g.
    // only the owner) must not drop everyone else who still exists locally or
    // on other devices — that hid Ana/Grayson/Scarlett in Manage Members.
    final byMemberKey = <String, FamilyMember>{};
    for (final m in localThisFamily) {
      byMemberKey[m.mergeKey] = m;
    }
    for (final m in membersThisFamily) {
      byMemberKey[m.mergeKey] = m;
    }
    final membersForActiveFamily =
        dedupeFamilyMembers(byMemberKey.values.toList());
    final membersOtherFamilies = local.familyMembers
        .where((m) => m.familyId != activeFamilyId)
        .toList();
    final mergedFamilyMembers = [
      ...membersOtherFamilies,
      ...membersForActiveFamily,
    ];

    // Parse each table individually so one bad table doesn't kill everything.
    // Merge by ID so offline-created items aren't lost.
    return AppDB(
      users: _mergeById(local.users, _safeParse(cloud['users'], User.fromJson)),
      families: _mergeById(local.families, _safeParse(cloud['families'], Family.fromJson)),
      familyMembers: mergedFamilyMembers,
      tasks: _mergeById(local.tasks, _safeParse(cloud['tasks'], Task.fromJson)),
      events: _mergeById(local.events, _safeParse(cloud['events'], CalendarEvent.fromJson)),
      recipes: _mergeById(local.recipes, _safeParse(cloud['recipes'], Recipe.fromJson)),
      mealPlans: _mergeById(local.mealPlans, _safeParse(cloud['meal_plans'], MealPlanEntry.fromJson)),
      lists: _mergeListsWithCloud(local, cloud, activeFamilyId),
      devotionals: _mergeById(local.devotionals, _safeParse(cloud['devotionals'], DevotionalEntry.fromJson)),
      devotionalThoughts: _mergeDevotionalThoughts(
          local.devotionalThoughts,
          _safeParse(cloud['devotional_thoughts'], DevotionalThought.fromJson)),
      fitness: _mergeById(local.fitness, _safeParse(cloud['fitness'], FitnessMetric.fromJson)),
      fitnessLogs: _mergeById(
          local.fitnessLogs, _safeParse(cloud['fitness_logs'], FitnessLog.fromJson)),
      workoutSessions: _mergeById(
          local.workoutSessions,
          _safeParse(cloud['workout_sessions'], WorkoutSession.fromJson)),
      workoutExercises: _mergeById(
          local.workoutExercises,
          _safeParse(cloud['workout_exercises'], WorkoutExercise.fromJson)),
      workoutSets: _mergeById(
          local.workoutSets, _safeParse(cloud['workout_sets'], WorkoutSet.fromJson)),
      exercisePrs: _mergeById(
          local.exercisePrs, _safeParse(cloud['exercise_prs'], ExercisePR.fromJson)),
      budgetCategories: _mergeById(local.budgetCategories, _safeParse(cloud['budget_categories'], BudgetCategoryRecord.fromJson)),
      budgetEntries: _mergeById(local.budgetEntries, _safeParse(cloud['budget_entries'], BudgetEntry.fromJson)),
      transactions: _mergeById(local.transactions, _safeParse(cloud['transactions'], Transaction.fromJson)),
      aiHistory: _mergeById(local.aiHistory, _safeParse(cloud['ai_history'], AIHistory.fromJson)),
      dailyHabits: _mergeById(local.dailyHabits, _safeParse(cloud['daily_habits'], DailyHabit.fromJson)),
      dailyHabitCompletions: _mergeById(local.dailyHabitCompletions, _safeParse(cloud['daily_habit_completions'], DailyHabitCompletion.fromJson)),
      chores: _mergeById(local.chores, _safeParse(cloud['chores'], Chore.fromJson)),
      choreCompletions: _mergeById(local.choreCompletions, _safeParse(cloud['chore_completions'], ChoreCompletion.fromJson)),
      polls: _mergeById(local.polls, _safeParse(cloud['polls'], Poll.fromJson)),
      pollVotes: _mergeById(local.pollVotes, _safeParse(cloud['poll_votes'], PollVote.fromJson)),
      rewardItems: _mergeById(local.rewardItems, _safeParse(cloud['reward_items'], RewardItem.fromJson)),
      rewardRedemptions: _mergeById(local.rewardRedemptions, _safeParse(cloud['reward_redemptions'], RewardRedemption.fromJson)),
      savingsGoals: _mergeById(local.savingsGoals, _safeParse(cloud['savings_goals'], SavingsGoal.fromJson)),
      prayerWall: _mergeById(local.prayerWall, _safeParse(cloud['prayer_wall'], PrayerWallEntry.fromJson)),
      specialDates: _mergeById(local.specialDates, _safeParse(cloud['special_dates'], SpecialDate.fromJson)),
      familyPhotos: _mergeById(local.familyPhotos, _safeParse(cloud['family_photos'], FamilyPhoto.fromJson)),
      milestones: _mergeById(local.milestones, _safeParse(cloud['milestones'], Milestone.fromJson)),
      savedPlaces: _mergeById(local.savedPlaces, _safeParse(cloud['saved_places'], SavedPlace.fromJson)),
      userLocations: _mergeById(local.userLocations, _safeParse(cloud['user_locations'], UserLocation.fromJson)),
      messages: _mergeById(local.messages, _safeParse(cloud['messages'], ChatMessage.fromJson)),
      healthRecords: _mergeById(local.healthRecords, _safeParse(cloud['health_records'], HealthRecord.fromJson)),
      periodCycles: _mergeById(local.periodCycles, _safeParse(cloud['period_cycles'], PeriodCycle.fromJson)),
      periodSymptoms: _mergeById(local.periodSymptoms, _safeParse(cloud['period_symptoms'], PeriodSymptomLog.fromJson)),
      rewards: _mergeById(local.rewards, _safeParse(cloud['rewards'], Reward.fromJson)),
      readingPlans: _mergeReadingPlans(
          local.readingPlans,
          _safeParse(cloud['reading_plans'], ReadingPlan.fromJson)),
      readingPlanProgress: _mergeById(
          local.readingPlanProgress,
          _safeParse(cloud['reading_plan_progress'], ReadingPlanProgress.fromJson)),
      externalCalendars: _mergeById(local.externalCalendars, _safeParse(cloud['external_calendars'], ExternalCalendar.fromJson)),
      pantryItems: _mergeById(local.pantryItems, _safeParse(cloud['pantry_items'], PantryItem.fromJson)),
      familyActivityLogs: _mergeById(
          local.familyActivityLogs,
          _safeParse(cloud['family_activity_logs'], FamilyActivityLog.fromJson)),
      wellnessCheckIns: _mergeById(
          local.wellnessCheckIns,
          _safeParse(cloud['wellness_check_ins'], WellnessCheckIn.fromJson)),
      fitnessPlans: _mergeFitnessPlans(
        local.fitnessPlans,
        cloud['fitness_plans'] is List ? cloud['fitness_plans'] as List : [],
        activeFamilyId,
      ),
    );
  }

  /// Parse a list from cloud data, skipping individual items that fail.
  ///
  /// Rows with `deleted_at != null` are tombstoned (their id is added to
  /// `_deletedKeys`) and skipped — incremental pulls surface soft-deletes
  /// this way, and the post-merge sweep in `_mergeById` drops them from
  /// any local-only state.
  static List<T> _safeParse<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw is! List) return [];
    final results = <T>[];
    for (final item in raw) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final deletedAt = m['deleted_at'];
        if (deletedAt != null && !(deletedAt is String && deletedAt.isEmpty)) {
          final id = m['id']?.toString();
          if (id != null && id.isNotEmpty) {
            _recordTombstone(id);
          }
          continue;
        }
        try {
          results.add(fromJson(m));
        } on Object catch (e, st) {
          final prev = lastError ?? '';
          lastError =
              '${prev}Parse error in ${T.toString()}: $e\n$st\n';
        }
      }
    }
    return results;
  }

  static List<ShoppingList> _mergeListsWithCloud(
    AppDB local,
    Map<String, dynamic> cloud,
    String familyId,
  ) {
    final rawHeaders = cloud['lists'] is List ? cloud['lists'] as List : [];
    final cloudHeaders = ListItemsCloud.parseListHeaders(rawHeaders);
    final mergedHeaders = _mergeById(
      local.lists,
      cloudHeaders,
      preferLocalOnTimestampTie: true,
    );

    final localItems = ListItemsCloud.flattenFromLists(local.lists, familyId);
    final cloudItemRows =
        _safeParse(cloud['list_items'], ShoppingListItem.fromJson);
    final mergedItems = _mergeById(localItems, cloudItemRows);

    final cloudHeaderIds = cloudHeaders.map((h) => h.id).toSet();
    final hydrated = ListItemsCloud.hydrate(mergedHeaders, mergedItems);

    // Offline-created list not on server yet — keep local lines until first push.
    return hydrated.map((h) {
      if (cloudHeaderIds.contains(h.id) || h.items.isNotEmpty) return h;
      for (final l in local.lists) {
        if (l.id == h.id && l.items.isNotEmpty) {
          return h.copyWith(items: l.items);
        }
      }
      return h;
    }).toList();
  }

  // ── Incremental realtime (Phase 3) ─────────────────────────────────────────

  /// Merge a single postgres realtime row into [local] without a full reconcile.
  /// Returns null when [table] is unsupported or the payload cannot be parsed.
  static AppDB? applyRealtimeRowChange({
    required AppDB local,
    required String table,
    required String familyId,
    String? userId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    if (!CloudSyncScope.incrementalRealtimeApplyTables.contains(table)) {
      return null;
    }
    try {
      switch (table) {
        case CloudSyncScope.tasks:
          return _applyRealtimeFamilyScopedRow<Task>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.tasks,
            write: (d, v) => d.copyWith(tasks: v),
            parse: (j) => Task.fromJson(j),
          );
        case CloudSyncScope.messages:
          return _applyRealtimeFamilyScopedRow<ChatMessage>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.messages,
            write: (d, v) => d.copyWith(messages: v),
            parse: (j) => ChatMessage.fromJson(j),
          );
        case CloudSyncScope.lists:
          return _applyRealtimeListHeaderRow(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
          );
        case CloudSyncScope.listItems:
          return _applyRealtimeListItemRow(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
          );
        case CloudSyncScope.chores:
          return _applyRealtimeFamilyScopedRow<Chore>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.chores,
            write: (d, v) => d.copyWith(chores: v),
            parse: (j) => Chore.fromJson(j),
          );
        case CloudSyncScope.choreCompletions:
          return _applyRealtimeFamilyScopedRow<ChoreCompletion>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.choreCompletions,
            write: (d, v) => d.copyWith(choreCompletions: v),
            parse: (j) => ChoreCompletion.fromJson(j),
          );
        case CloudSyncScope.polls:
          return _applyRealtimeFamilyScopedRow<Poll>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.polls,
            write: (d, v) => d.copyWith(polls: v),
            parse: (j) => Poll.fromJson(j),
            preferLocalOnTimestampTie: true,
          );
        case CloudSyncScope.pollVotes:
          return _applyRealtimeFamilyScopedRow<PollVote>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.pollVotes,
            write: (d, v) => d.copyWith(pollVotes: v),
            parse: (j) => PollVote.fromJson(j),
          );
        case CloudSyncScope.events:
          return _applyRealtimeFamilyScopedRow<CalendarEvent>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.events,
            write: (d, v) => d.copyWith(events: v),
            parse: (j) => CalendarEvent.fromJson(j),
          );
        case CloudSyncScope.externalCalendars:
          return _applyRealtimeFamilyScopedRow<ExternalCalendar>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.externalCalendars,
            write: (d, v) => d.copyWith(externalCalendars: v),
            parse: (j) => ExternalCalendar.fromJson(j),
          );
        case CloudSyncScope.users:
          return _applyRealtimeUserRow(
            local,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
          );
        case CloudSyncScope.recipes:
          return _applyRealtimeFamilyScopedRow<Recipe>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.recipes,
            write: (d, v) => d.copyWith(recipes: v),
            parse: (j) => Recipe.fromJson(j),
          );
        case CloudSyncScope.mealPlans:
          return _applyRealtimeFamilyScopedRow<MealPlanEntry>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.mealPlans,
            write: (d, v) => d.copyWith(mealPlans: v),
            parse: (j) => MealPlanEntry.fromJson(j),
          );
        case CloudSyncScope.prayerWall:
          return _applyRealtimeFamilyScopedRow<PrayerWallEntry>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.prayerWall,
            write: (d, v) => d.copyWith(prayerWall: v),
            parse: (j) => PrayerWallEntry.fromJson(j),
          );
        case CloudSyncScope.dailyHabits:
          return _applyRealtimeFamilyScopedRow<DailyHabit>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.dailyHabits,
            write: (d, v) => d.copyWith(dailyHabits: v),
            parse: (j) => DailyHabit.fromJson(j),
          );
        case CloudSyncScope.dailyHabitCompletions:
          return _applyRealtimeFamilyScopedRow<DailyHabitCompletion>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.dailyHabitCompletions,
            write: (d, v) => d.copyWith(dailyHabitCompletions: v),
            parse: (j) => DailyHabitCompletion.fromJson(j),
          );
        case CloudSyncScope.budgetCategories:
          return _applyRealtimeFamilyScopedRow<BudgetCategoryRecord>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.budgetCategories,
            write: (d, v) => d.copyWith(budgetCategories: v),
            parse: (j) => BudgetCategoryRecord.fromJson(j),
          );
        case CloudSyncScope.budgetEntries:
          return _applyRealtimeFamilyScopedRow<BudgetEntry>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.budgetEntries,
            write: (d, v) => d.copyWith(budgetEntries: v),
            parse: (j) => BudgetEntry.fromJson(j),
          );
        case CloudSyncScope.transactions:
          return _applyRealtimeFamilyScopedRow<Transaction>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.transactions,
            write: (d, v) => d.copyWith(transactions: v),
            parse: (j) => Transaction.fromJson(j),
          );
        case CloudSyncScope.rewardItems:
          return _applyRealtimeFamilyScopedRow<RewardItem>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.rewardItems,
            write: (d, v) => d.copyWith(rewardItems: v),
            parse: (j) => RewardItem.fromJson(j),
          );
        case CloudSyncScope.rewardRedemptions:
          return _applyRealtimeFamilyScopedRow<RewardRedemption>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.rewardRedemptions,
            write: (d, v) => d.copyWith(rewardRedemptions: v),
            parse: (j) => RewardRedemption.fromJson(j),
          );
        case CloudSyncScope.pantryItems:
          return _applyRealtimeFamilyScopedRow<PantryItem>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.pantryItems,
            write: (d, v) => d.copyWith(pantryItems: v),
            parse: (j) => PantryItem.fromJson(j),
          );
        case CloudSyncScope.devotionals:
          return _applyRealtimeFamilyScopedRow<DevotionalEntry>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.devotionalEntries,
            write: (d, v) => d.copyWith(devotionalEntries: v),
            parse: (j) => DevotionalEntry.fromJson(j),
          );
        case CloudSyncScope.devotionalThoughts:
          return _applyRealtimeFamilyScopedRow<DevotionalThought>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.devotionalThoughts,
            write: (d, v) => d.copyWith(devotionalThoughts: v),
            parse: (j) => DevotionalThought.fromJson(j),
          );
        case CloudSyncScope.savingsGoals:
          return _applyRealtimeFamilyScopedRow<SavingsGoal>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.savingsGoals,
            write: (d, v) => d.copyWith(savingsGoals: v),
            parse: (j) => SavingsGoal.fromJson(j),
          );
        case CloudSyncScope.rewards:
          return _applyRealtimeFamilyScopedRow<Reward>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.rewards,
            write: (d, v) => d.copyWith(rewards: v),
            parse: (j) => Reward.fromJson(j),
          );
        case CloudSyncScope.specialDates:
          return _applyRealtimeFamilyScopedRow<SpecialDate>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.specialDates,
            write: (d, v) => d.copyWith(specialDates: v),
            parse: (j) => SpecialDate.fromJson(j),
          );
        case CloudSyncScope.familyPhotos:
          return _applyRealtimeFamilyScopedRow<FamilyPhoto>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.familyPhotos,
            write: (d, v) => d.copyWith(familyPhotos: v),
            parse: (j) => FamilyPhoto.fromJson(j),
          );
        case CloudSyncScope.milestones:
          return _applyRealtimeFamilyScopedRow<Milestone>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.milestones,
            write: (d, v) => d.copyWith(milestones: v),
            parse: (j) => Milestone.fromJson(j),
          );
        case CloudSyncScope.readingPlans:
          return _applyRealtimeFamilyScopedRow<ReadingPlan>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.readingPlans,
            write: (d, v) => d.copyWith(readingPlans: v),
            parse: (j) => ReadingPlan.fromJson(j),
          );
        case CloudSyncScope.readingPlanProgress:
          return _applyRealtimeFamilyScopedRow<ReadingPlanProgress>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.readingPlanProgress,
            write: (d, v) => d.copyWith(readingPlanProgress: v),
            parse: (j) => ReadingPlanProgress.fromJson(j),
          );
        case CloudSyncScope.healthRecords:
          return _applyRealtimeFamilyScopedRow<HealthRecord>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.healthRecords,
            write: (d, v) => d.copyWith(healthRecords: v),
            parse: (j) => HealthRecord.fromJson(j),
          );
        case CloudSyncScope.periodCycles:
          return _applyRealtimeFamilyScopedRow<PeriodCycle>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.periodCycles,
            write: (d, v) => d.copyWith(periodCycles: v),
            parse: (j) => PeriodCycle.fromJson(j),
          );
        case CloudSyncScope.periodSymptoms:
          return _applyRealtimeFamilyScopedRow<PeriodSymptomLog>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.periodSymptoms,
            write: (d, v) => d.copyWith(periodSymptoms: v),
            parse: (j) => PeriodSymptomLog.fromJson(j),
          );
        case CloudSyncScope.wellnessCheckIns:
          return _applyRealtimeFamilyScopedRow<WellnessCheckIn>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.wellnessCheckIns,
            write: (d, v) => d.copyWith(wellnessCheckIns: v),
            parse: (j) => WellnessCheckIn.fromJson(j),
          );
        case CloudSyncScope.familyActivityLogs:
          return _applyRealtimeFamilyScopedRow<FamilyActivityLog>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.familyActivityLogs,
            write: (d, v) => d.copyWith(familyActivityLogs: v),
            parse: (j) => FamilyActivityLog.fromJson(j),
          );
        case CloudSyncScope.savedPlaces:
          return _applyRealtimeFamilyScopedRow<SavedPlace>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: true,
            read: (d) => d.savedPlaces,
            write: (d, v) => d.copyWith(savedPlaces: v),
            parse: (j) => SavedPlace.fromJson(j),
          );
        case CloudSyncScope.familyMembers:
          return _applyRealtimeFamilyMemberRow(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
          );
        case CloudSyncScope.exercisePrs:
          return _applyRealtimeFamilyScopedRow<ExercisePR>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.exercisePrs,
            write: (d, v) => d.copyWith(exercisePrs: v),
            parse: (j) => ExercisePR.fromJson(j),
          );
        case CloudSyncScope.workoutSessions:
          return _applyRealtimeFamilyScopedRow<WorkoutSession>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.workoutSessions,
            write: (d, v) => d.copyWith(workoutSessions: v),
            parse: (j) => WorkoutSession.fromJson(j),
          );
        case CloudSyncScope.workoutExercises:
          return _applyRealtimeFamilyScopedRow<WorkoutExercise>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.workoutExercises,
            write: (d, v) => d.copyWith(workoutExercises: v),
            parse: (j) => WorkoutExercise.fromJson(j),
          );
        case CloudSyncScope.workoutSets:
          return _applyRealtimeFamilyScopedRow<WorkoutSet>(
            local,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.workoutSets,
            write: (d, v) => d.copyWith(workoutSets: v),
            parse: (j) => WorkoutSet.fromJson(j),
          );
        case CloudSyncScope.fitness:
          if (userId == null || userId.isEmpty) return null;
          return _applyRealtimeUserScopedRow<FitnessMetric>(
            local,
            userId: userId,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.fitness,
            write: (d, v) => d.copyWith(fitness: v),
            parse: (j) => FitnessMetric.fromJson(j),
          );
        case CloudSyncScope.fitnessPlans:
          return _applyRealtimeFitnessPlanRow(
            local,
            userId: userId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
          );
        case CloudSyncScope.fitnessLogs:
          if (userId == null || userId.isEmpty) return null;
          return _applyRealtimeUserScopedRow<FitnessLog>(
            local,
            userId: userId,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            requireFamilyMatch: true,
            read: (d) => d.fitnessLogs,
            write: (d, v) => d.copyWith(fitnessLogs: v),
            parse: (j) => FitnessLog.fromJson(j),
          );
        case CloudSyncScope.aiHistory:
          if (userId == null || userId.isEmpty) return null;
          return _applyRealtimeUserScopedRow<AIHistory>(
            local,
            userId: userId,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.aiHistory,
            write: (d, v) => d.copyWith(aiHistory: v),
            parse: (j) => AIHistory.fromJson(j),
          );
        case CloudSyncScope.userLocations:
          if (userId == null || userId.isEmpty) return null;
          return _applyRealtimeUserScopedRow<UserLocation>(
            local,
            userId: userId,
            familyId: familyId,
            eventType: eventType,
            newRecord: newRecord,
            oldRecord: oldRecord,
            tombstoneOnRemove: false,
            read: (d) => d.userLocations,
            write: (d, v) => d.copyWith(userLocations: v),
            parse: (j) => UserLocation.fromJson(j),
          );
        default:
          return null;
      }
    } on Object catch (e, st) {
      _debugCatch('applyRealtimeRowChange $table', e, st);
      return null;
    }
  }

  static String? _realtimeRowId(
    PostgresChangeEvent eventType, {
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    final raw = eventType == PostgresChangeEvent.delete
        ? oldRecord['id']
        : newRecord['id'];
    final id = raw?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  static bool _realtimeRowSoftDeleted(Map<String, dynamic> row) {
    final deletedAt = row['deleted_at'];
    if (deletedAt == null) return false;
    if (deletedAt is String) return deletedAt.isNotEmpty;
    return true;
  }

  static AppDB _removeRowById<T>(
    AppDB db,
    String id,
    List<T> Function(AppDB) getter,
    AppDB Function(AppDB, List<T>) setter,
  ) {
    final next =
        getter(db).where((e) => _mergeKeyOf(e) != id).toList();
    return setter(db, next);
  }

  static AppDB? _applyRealtimeFamilyScopedRow<T>(
    AppDB local, {
    required String familyId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
    required bool tombstoneOnRemove,
    required List<T> Function(AppDB db) read,
    required AppDB Function(AppDB db, List<T> items) write,
    required T Function(Map<String, dynamic> json) parse,
    bool preferLocalOnTimestampTie = false,
  }) {
    final id = _realtimeRowId(eventType,
        newRecord: newRecord, oldRecord: oldRecord);
    if (id == null) return null;

    if (eventType == PostgresChangeEvent.delete) {
      if (tombstoneOnRemove) markTombstone(id);
      return _removeRowById(local, id, read, write);
    }

    if (newRecord.isEmpty) return null;
    if (newRecord['family_id']?.toString() != familyId) return null;

    if (tombstoneOnRemove && _realtimeRowSoftDeleted(newRecord)) {
      markTombstone(id);
      return _removeRowById(local, id, read, write);
    }

    final remote = parse(Map<String, dynamic>.from(newRecord));
    return write(
      local,
      _mergeById(
        read(local),
        [remote],
        preferLocalOnTimestampTie: preferLocalOnTimestampTie,
      ),
    );
  }

  static AppDB? _applyRealtimeListHeaderRow(
    AppDB local, {
    required String familyId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    final id = _realtimeRowId(eventType,
        newRecord: newRecord, oldRecord: oldRecord);
    if (id == null) return null;

    if (eventType == PostgresChangeEvent.delete) {
      markTombstone(id);
      return _removeRowById(
        local,
        id,
        (d) => d.lists,
        (d, list) => d.copyWith(lists: list),
      );
    }

    if (newRecord.isEmpty) return null;
    if (newRecord['family_id']?.toString() != familyId) return null;

    if (_realtimeRowSoftDeleted(newRecord)) {
      markTombstone(id);
      return _removeRowById(
        local,
        id,
        (d) => d.lists,
        (d, list) => d.copyWith(lists: list),
      );
    }

    final headerJson = Map<String, dynamic>.from(newRecord)..['items'] = [];
    final remote = ShoppingList.fromJson(headerJson);
    final lists = local.lists.map((l) {
      if (l.id != remote.id) return l;
      return l.copyWith(
        title: remote.title,
        category: remote.category,
        visibility: remote.visibility,
        sharedWith: remote.sharedWith,
        creatorId: remote.creatorId,
        updatedAt: remote.updatedAt,
      );
    }).toList();
    if (!lists.any((l) => l.id == remote.id)) {
      lists.add(remote);
    }
    return local.copyWith(lists: lists);
  }

  static AppDB? _applyRealtimeListItemRow(
    AppDB local, {
    required String familyId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    final id = _realtimeRowId(eventType,
        newRecord: newRecord, oldRecord: oldRecord);
    if (id == null) return null;

    if (eventType == PostgresChangeEvent.delete) {
      return _patchListItemsOnList(
        local,
        listId: oldRecord['list_id']?.toString() ?? '',
        patch: (items) => items.where((i) => i.id != id).toList(),
      );
    }

    if (newRecord.isEmpty) return null;
    if (newRecord['family_id']?.toString() != familyId) return null;

    final listId = newRecord['list_id']?.toString() ?? '';
    if (listId.isEmpty) return null;

    if (_realtimeRowSoftDeleted(newRecord)) {
      return _patchListItemsOnList(
        local,
        listId: listId,
        patch: (items) => items.where((i) => i.id != id).toList(),
      );
    }

    final row = ShoppingListItem.fromJson(Map<String, dynamic>.from(newRecord));
    return _patchListItemsOnList(
      local,
      listId: listId,
      patch: (items) {
        final asRows = items
            .map(
              (i) => ShoppingListItem.fromListItem(
                i,
                listId: listId,
                familyId: familyId,
              ),
            )
            .toList();
        final merged = _mergeById(asRows, [row]);
        merged.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return merged.map((r) => r.toListItem()).toList();
      },
    );
  }

  static AppDB? _patchListItemsOnList(
    AppDB local, {
    required String listId,
    required List<ListItem> Function(List<ListItem> items) patch,
  }) {
    if (listId.isEmpty) return null;
    var touched = false;
    final lists = local.lists.map((l) {
      if (l.id != listId) return l;
      touched = true;
      return l.copyWith(items: patch(l.items));
    }).toList();
    if (!touched) return null;
    return local.copyWith(lists: lists);
  }

  static AppDB? _applyRealtimeFamilyMemberRow(
    AppDB local, {
    required String familyId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    if (eventType == PostgresChangeEvent.delete) {
      final userId = oldRecord['user_id']?.toString() ?? '';
      if (userId.isEmpty || oldRecord['family_id']?.toString() != familyId) {
        return null;
      }
      return local.copyWith(
        familyMembers: local.familyMembers
            .where((m) => !(m.userId == userId && m.familyId == familyId))
            .toList(),
      );
    }

    if (newRecord.isEmpty) return null;
    if (newRecord['family_id']?.toString() != familyId) return null;

    final remote = FamilyMember.fromJson(Map<String, dynamic>.from(newRecord));
    return local.copyWith(
      familyMembers: _mergeById(local.familyMembers, [remote]),
    );
  }

  static AppDB? _applyRealtimeFitnessPlanRow(
    AppDB local, {
    required String? userId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    if (eventType == PostgresChangeEvent.delete) {
      final key = fitnessPlanStableId(Map<String, dynamic>.from(oldRecord));
      final plans = local.fitnessPlans
          .where((p) => p is! Map || fitnessPlanStableId(p) != key)
          .toList();
      return local.copyWith(fitnessPlans: plans);
    }

    if (newRecord.isEmpty) return null;
    final rowUserId = newRecord['user_id']?.toString() ?? '';
    if (userId != null && userId.isNotEmpty && rowUserId != userId) return null;

    final normalized = _normalizeFitnessPlanMap(
      Map<String, dynamic>.from(newRecord),
    );
    final key = fitnessPlanStableId(normalized);
    final plans = <dynamic>[...local.fitnessPlans];
    final idx = plans.indexWhere(
      (p) => p is Map && fitnessPlanStableId(p) == key,
    );
    if (idx >= 0) {
      plans[idx] = normalized;
    } else {
      plans.add(normalized);
    }
    return local.copyWith(fitnessPlans: plans);
  }

  static AppDB? _applyRealtimeUserScopedRow<T>(
    AppDB local, {
    required String userId,
    String? familyId,
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
    required bool tombstoneOnRemove,
    required List<T> Function(AppDB db) read,
    required AppDB Function(AppDB db, List<T> items) write,
    required T Function(Map<String, dynamic> json) parse,
    bool requireFamilyMatch = false,
  }) {
    final id = _realtimeRowId(eventType,
        newRecord: newRecord, oldRecord: oldRecord);
    if (id == null) return null;

    if (eventType == PostgresChangeEvent.delete) {
      if (oldRecord['user_id']?.toString() != userId) return null;
      if (requireFamilyMatch &&
          familyId != null &&
          oldRecord['family_id']?.toString() != familyId) {
        return null;
      }
      if (tombstoneOnRemove) markTombstone(id);
      return _removeRowById(local, id, read, write);
    }

    if (newRecord.isEmpty) return null;
    if (newRecord['user_id']?.toString() != userId) return null;
    if (requireFamilyMatch && familyId != null) {
      final fid = newRecord['family_id']?.toString();
      if (fid != null && fid.isNotEmpty && fid != familyId) return null;
    }

    if (tombstoneOnRemove && _realtimeRowSoftDeleted(newRecord)) {
      markTombstone(id);
      return _removeRowById(local, id, read, write);
    }

    final remote = parse(Map<String, dynamic>.from(newRecord));
    return write(
      local,
      _mergeById(read(local), [remote]),
    );
  }

  static AppDB? _applyRealtimeUserRow(
    AppDB local, {
    required PostgresChangeEvent eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) {
    final id = _realtimeRowId(eventType,
        newRecord: newRecord, oldRecord: oldRecord);
    if (id == null) return null;

    if (eventType == PostgresChangeEvent.delete) {
      return local.copyWith(
        users: local.users.where((u) => u.id != id).toList(),
      );
    }

    if (newRecord.isEmpty) return null;
    final remote = User.fromJson(Map<String, dynamic>.from(newRecord));
    return local.copyWith(
      users: _mergeById(local.users, [remote]),
    );
  }

  // ── Join code ─────────────────────────────────────────────────────────────

  /// Generate a unique 6-character alphanumeric join code.
  static String generateJoinCode(List<Family> existing) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = math.Random();
    String code;
    do {
      code = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    } while (existing.any((f) => f.joinCode == code));
    return code;
  }
}
