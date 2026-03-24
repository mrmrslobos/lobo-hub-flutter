// lib/services/database_service.dart
// FamilyHub - Local storage service with Supabase sync

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'field_encryption_service.dart';
import 'supabase_service.dart';

/// Row shape for Supabase `fitness_plans` (AI weekly plan per user).
Map<String, dynamic> fitnessPlanRowForCloud(
  Map<String, dynamic> plan,
  String familyId,
) {
  final uid = plan['user_id']?.toString() ?? '';
  final created = plan['created_at']?.toString() ?? '';
  final id = '${uid}_$familyId';
  dynamic weekly = plan['weeklyPlan'] ?? plan['weekly_plan'] ?? [];
  if (weekly is! List) weekly = [];
  dynamic tips = plan['tips'] ?? [];
  if (tips is! List) tips = [];
  dynamic profile = plan['profile'] ?? {};
  if (profile is! Map) profile = <String, dynamic>{};
  return {
    'id': id,
    'user_id': uid,
    'family_id': familyId,
    'summary': plan['summary']?.toString() ?? '',
    'weekly_plan': weekly,
    'tips': tips,
    'profile': profile,
    'created_at': created.isNotEmpty ? created : DateTime.now().toIso8601String(),
  };
}

class DatabaseService {
  /// Families columns omitted on upsert until DB has them (see migrations/06).
  static const _familiesCloudOmit = {'currency', 'trial_start_date'};

  /// fitness_plans.family_id until migration 18 is applied everywhere.
  static const _fitnessPlansCloudOmit = {'family_id'};

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

  /// users.settings may not exist on all deployments.
  static const _usersCloudOmit = {'settings'};

  /// Events columns some older DBs lack (PGRST204).
  static const _eventsCloudOmit = {'shared_with'};

  /// Prayer wall columns some older DBs lack (PGRST204).
  static const _prayerWallCloudOmit = {'prayed_by_ids'};

  static const String _dbKey = 'familyhub_db';
  static const String _tombstoneKey = 'fh_merge_tombstones';
  static AppDB? _cache;

  /// Keys intentionally removed locally. Persisted so restarts + failed cloud
  /// deletes don't let merged pulls resurrect rows (family members, tasks, …).
  static final Set<String> _deletedKeys = {};

  static AppDB get db => _cache ?? AppDB.empty();

  // ── Local persistence ─────────────────────────────────────────────────────

  static Future<void> _loadTombstones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_tombstoneKey);
      if (list != null && list.isNotEmpty) {
        _deletedKeys
          ..clear()
          ..addAll(list);
        if (_deletedKeys.length > 800) {
          _deletedKeys.clear();
          await prefs.remove(_tombstoneKey);
        }
      }
    } catch (_) {}
  }

  static Future<void> _persistTombstones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_tombstoneKey, _deletedKeys.toList());
    } catch (_) {}
  }

  static Future<AppDB> loadLocal() async {
    await _loadTombstones();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dbKey);
    if (raw == null) {
      _cache = AppDB.empty();
      return _cache!;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cache = AppDB.fromJson(json);
      return _cache!;
    } catch (_) {
      _cache = AppDB.empty();
      return _cache!;
    }
  }

  static Future<void> saveLocal(AppDB db, {AppDB? tombstoneBase}) async {
    // Track keys that disappeared (intentional deletes) so cloud merge
    // doesn't re-add them. [tombstoneBase] = state before merge (e.g. reconcile).
    final base = tombstoneBase ?? _cache;
    if (base != null) {
      final oldKeys = _collectKeys(base);
      final newKeys = _collectKeys(db);
      _deletedKeys.addAll(oldKeys.difference(newKeys));
    }
    _cache = db;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dbKey, jsonEncode(db.toJson()));
    await _persistTombstones();
  }

  static Future<void> clearLocal() async {
    _cache = AppDB.empty();
    _deletedKeys.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dbKey);
    await prefs.remove(_tombstoneKey);
  }

  // ── Cloud sync ────────────────────────────────────────────────────────────

  /// Save locally and attempt a background cloud sync.
  static Future<void> saveAndSync(AppDB db, String familyId) async {
    await saveLocal(db);
    await syncToCloud(db, familyId);
  }

  static Map<String, dynamic> _taskRowForCloud(Task t) {
    final m = Map<String, dynamic>.from(t.toJson());
    m.remove('updated_at');
    for (final k in _tasksCloudOmit) {
      m.remove(k);
    }
    return m;
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
  static Future<void> pushFamilyTasksToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    final familyTasks = db.tasks.where((t) => t.familyId == familyId).toList();
    final localIds = familyTasks.map((t) => t.id).toSet();
    const chunk = 40;
    for (var i = 0; i < familyTasks.length; i += chunk) {
      final slice = familyTasks.sublist(
          i, math.min(i + chunk, familyTasks.length));
      final rows = slice.map(_taskRowForCloud).toList();
      try {
        await SupabaseService.upsertTable('tasks', rows);
      } catch (e) {
        debugPrint('[DatabaseService] tasks chunk upsert failed, retry per row: $e');
        for (final t in slice) {
          try {
            await SupabaseService.upsertTable('tasks', [_taskRowForCloud(t)]);
          } catch (e2) {
            debugPrint('[DatabaseService] task ${t.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('tasks', localIds, familyId);
  }

  /// Push local data to Supabase. Safe to fire-and-forget.
  static Future<void> syncToCloud(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await _syncToCloud(db, familyId);
      // Tombstones stay until prune (server row gone) so failed deletes
      // don't resurrect rows on the next pull.
    } catch (e) {
      debugPrint('[DatabaseService] Cloud sync failed: $e');
    }
  }

  static Future<void> _syncToCloud(AppDB db, String familyId) async {
    /// Strip columns the app model sends but many Supabase DBs don't have yet
    /// (see migrations/05_row_updated_at_for_sync.sql). Unknown columns make the
    /// entire batch fail — tables look empty in the dashboard.
    /// Strip [updated_at] for tables where the column may not exist yet.
    /// Keep it for [user_locations] — NOT NULL; omitting it on upsert sets NULL.
    List<Map<String, dynamic>> _sanitizeForUpsert(
      List<Map<String, dynamic>> rows,
      String table,
    ) {
      const keepUpdatedAt = {'user_locations'};
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
        return m;
      }).toList();
    }

    Future<void> up(String table, List<Map<String, dynamic>> rows,
        {String onConflict = 'id'}) async {
      if (rows.isNotEmpty) {
        try {
          await SupabaseService.upsertTable(
              table, _sanitizeForUpsert(rows, table), onConflict: onConflict);
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
            return; // table not in schema — skip quietly
          }
          debugPrint('[DatabaseService] Failed to sync $table: $e');
        }
      }
    }

    final fid = familyId;
    final currentUserId = SupabaseService.currentUser?.id;

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
      upAndClean(
          'tasks',
          db.tasks
              .where((t) => t.familyId == fid)
              .map((t) => t.toJson())
              .toList(),
          db.tasks.where((t) => t.familyId == fid).map((t) => t.id).toSet()),
      upAndClean('events',
          db.events.map((e) => {...e.toJson(), 'family_id': fid}).toList(),
          db.events.map((e) => e.id).toSet()),
      upAndClean(
          'recipes',
          db.recipes
              .map((r) {
                final row = Map<String, dynamic>.from(r.toJson());
                row['family_id'] = fid;
                for (final k in _recipeCloudOmit) {
                  row.remove(k);
                }
                return row;
              })
              .toList(),
          db.recipes.map((r) => r.id).toSet()),
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
                return row;
              })
              .toList(),
          db.mealPlans.where((m) => m.familyId == fid).map((m) => m.id).toSet()),
      upAndClean('lists',
          db.lists.map((l) => {...l.toJson(), 'family_id': fid}).toList(),
          db.lists.map((l) => l.id).toSet()),
      upAndClean('devotionals',
          db.devotionals.map((d) => {...d.toJson(), 'family_id': fid}).toList(),
          db.devotionals.map((d) => d.id).toSet()),
      if (currentUserId != null)
        Future.wait([
          upAndCleanUser(
            'fitness',
            db.fitness
                .where((f) => f.userId == currentUserId)
                .map((f) => f.toJson())
                .toList(),
            db.fitness
                .where((f) => f.userId == currentUserId)
                .map((f) => f.id)
                .toSet(),
            userId: currentUserId,
          ),
          upAndCleanUser(
            'fitness_plans',
            db.fitnessPlans
                .whereType<Map>()
                .where((p) => p['user_id'] == currentUserId)
                .map((p) {
                  final row = fitnessPlanRowForCloud(
                    Map<String, dynamic>.from(p as Map),
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
                .map((p) => '${p['user_id']}_$fid')
                .toSet(),
            userId: currentUserId,
          ),
        ])
      else
        Future.value(),
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
      upAndClean(
        'exercise_prs',
        db.exercisePrs
            .where((p) => p.familyId == fid)
            .map((p) => p.toJson())
            .toList(),
        db.exercisePrs.where((p) => p.familyId == fid).map((p) => p.id).toSet(),
      ),
      upAndClean('budget_categories',
          db.budgetCategories.map((b) => {...b.toJson(), 'family_id': fid}).toList(),
          db.budgetCategories.map((b) => b.id).toSet()),
      upAndClean('budget_entries',
          db.budgetEntries.map((b) => {...b.toJson(), 'family_id': fid}).toList(),
          db.budgetEntries.map((b) => b.id).toSet()),
      upAndClean('transactions',
          db.transactions.map((t) => {...t.toJson(), 'family_id': fid}).toList(),
          db.transactions.map((t) => t.id).toSet()),
      upAndClean('ai_history',
          db.aiHistory.map((a) => a.toJson()).toList(),
          db.aiHistory.map((a) => a.id).toSet()),
      upAndClean('daily_habits',
          db.dailyHabits.map((h) => h.toJson()).toList(),
          db.dailyHabits.map((h) => h.id).toSet()),
      if (currentUserId != null)
        upAndCleanUser(
          'daily_habit_completions',
          db.dailyHabitCompletions
              .where((c) => c.userId == currentUserId)
              .map((c) => c.toJson())
              .toList(),
          db.dailyHabitCompletions
              .where((c) => c.userId == currentUserId)
              .map((c) => c.id)
              .toSet(),
          userId: currentUserId,
        )
      else
        Future.value(),
      upAndClean(
          'chores',
          db.chores
              .where((c) => c.familyId == fid)
              .map((c) => _choreRowForCloud(c))
              .toList(),
          db.chores.where((c) => c.familyId == fid).map((c) => c.id).toSet()),
      upAndClean('chore_completions',
          db.choreCompletions.map((c) => c.toJson()).toList(),
          db.choreCompletions.map((c) => c.id).toSet()),
      upAndClean('polls',
          db.polls.map((p) => {...p.toJson(), 'family_id': fid}).toList(),
          db.polls.map((p) => p.id).toSet()),
      upAndClean('poll_votes',
          db.pollVotes.map((v) => v.toJson()).toList(),
          db.pollVotes.map((v) => v.id).toSet()),
      upAndClean('reward_items',
          db.rewardItems.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
          db.rewardItems.map((r) => r.id).toSet()),
      upAndClean('reward_redemptions',
          db.rewardRedemptions.map((r) => r.toJson()).toList(),
          db.rewardRedemptions.map((r) => r.id).toSet()),
      upAndClean('savings_goals',
          db.savingsGoals.map((g) => {...g.toJson(), 'family_id': fid}).toList(),
          db.savingsGoals.map((g) => g.id).toSet()),
      upAndClean('prayer_wall',
          db.prayerWall.map((p) => {...p.toJson(), 'family_id': fid}).toList(),
          db.prayerWall.map((p) => p.id).toSet()),
      upAndClean('special_dates',
          db.specialDates.map((s) => {...s.toJson(), 'family_id': fid}).toList(),
          db.specialDates.map((s) => s.id).toSet()),
      upAndClean('family_photos',
          db.familyPhotos.map((p) => {...p.toJson(), 'family_id': fid}).toList(),
          db.familyPhotos.map((p) => p.id).toSet()),
      upAndClean('milestones',
          db.milestones.map((m) => {...m.toJson(), 'family_id': fid}).toList(),
          db.milestones.map((m) => m.id).toSet()),
      upAndClean('saved_places',
          db.savedPlaces.map((s) => {...s.toJson(), 'family_id': fid}).toList(),
          db.savedPlaces.map((s) => s.id).toSet()),
      upAndClean('user_locations',
          db.userLocations.map((u) => u.toJson()).toList(),
          db.userLocations.map((u) => u.id).toSet()),
      upAndClean('messages',
          db.messages.map((m) => {...m.toJson(), 'family_id': fid}).toList(),
          db.messages.map((m) => m.id).toSet()),
      upAndClean('health_records',
          db.healthRecords.map((h) => {...h.toJson(), 'family_id': fid}).toList(),
          db.healthRecords.map((h) => h.id).toSet()),
      upAndClean('period_cycles',
          db.periodCycles.map((c) => c.toJson()).toList(),
          db.periodCycles.map((c) => c.id).toSet()),
      upAndClean('period_symptoms',
          db.periodSymptoms.map((s) => s.toJson()).toList(),
          db.periodSymptoms.map((s) => s.id).toSet()),
      upAndClean('external_calendars',
          db.externalCalendars.map((c) => {...c.toJson(), 'family_id': fid}).toList(),
          db.externalCalendars.map((c) => c.id).toSet()),
      upAndClean('rewards',
          db.rewards.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
          db.rewards.map((r) => r.id).toSet()),
      upAndClean('reading_plans',
          db.readingPlans.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
          db.readingPlans.map((r) => r.id).toSet()),
      upAndClean(
          'pantry_items',
          db.pantryItems
              .where((p) => p.familyId == fid)
              .map((p) => p.toJson())
              .toList(),
          db.pantryItems.where((p) => p.familyId == fid).map((p) => p.id).toSet()),
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
      } catch (e) {
        debugPrint('[DatabaseService] Failed to sync family_members: $e');
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
    } catch (e) {
      debugPrint('[DatabaseService] Failed to delete removed family_members: $e');
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
    try {
      final cloudRows = await SupabaseService.client
          .from(table)
          .select('id')
          .eq('family_id', familyId);
      final cloudIds = (cloudRows as List).map((r) => r['id'] as String).toSet();
      // Only delete cloud rows that were intentionally deleted locally
      final removed = cloudIds.intersection(_deletedKeys);
      for (final id in removed) {
        await SupabaseService.deleteRows(table, {'id': id});
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e');
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
    try {
      final cloudRows = await SupabaseService.client
          .from(table)
          .select('id')
          .eq('user_id', userId);
      final cloudIds = (cloudRows as List)
          .map((r) => r['id'] as String)
          .toSet();
      final removed = cloudIds.intersection(_deletedKeys);
      for (final id in removed) {
        await SupabaseService.deleteRows(table, {'id': id});
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e');
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
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[DatabaseService] backfillMissingUsersForFamily fetch: $e');
    }

    for (final id in missing) {
      if (have.contains(id)) continue;
      users.add(User(id: id, name: stubName(fmFor(id)), email: ''));
      have.add(id);
    }

    return db.copyWith(users: users);
  }

  static Future<AppDB> reconcileCloud(AppDB local, String familyId) async {
    lastError = null;
    if (!SupabaseService.isConfigured) return local;
    try {
      final cloudData = await SupabaseService.fetchAllTables(familyId);
      _pruneTombstonesAgainstCloud(cloudData);
      await _persistTombstones();
      var merged = _mergeWithCloud(local, cloudData, familyId);
      if (FieldEncryption.isReady(familyId)) {
        merged = merged.applySensitiveDecryption(familyId);
      }
      merged = await backfillMissingUsersForFamily(merged, familyId);
      await saveLocal(merged, tombstoneBase: local);
      return merged;
    } catch (e, st) {
      lastError = '$e\n$st';
      return local;
    }
  }

  /// Drop tombstones once Supabase no longer has that row (delete succeeded).
  static void _pruneTombstonesAgainstCloud(Map<String, dynamic> cloud) {
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
    _deletedKeys.removeWhere((k) => fmRe.hasMatch(k) && !fmKeys.contains(k));

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

    pruneTable('tasks');
    pruneTable('events');
    pruneTable('lists');
    pruneTable('recipes');
    pruneTable('chores');
    pruneTable('devotionals');
    pruneTable('messages');
    pruneTable('polls');
    pruneTable('family_photos');
    pruneTable('milestones');
    pruneTable('saved_places');
    pruneTable('prayer_wall');
    pruneTable('special_dates');
    pruneTable('reward_items');
    pruneTable('savings_goals');
    pruneTable('external_calendars');
    pruneTable('pantry_items');
    pruneTable('fitness_plans');
    pruneTable('family_activity_logs');
    pruneTable('wellness_check_ins');
    // User-scoped tables
    pruneTable('fitness');
    pruneTable('daily_habit_completions');
    pruneTable('workout_sessions');
    pruneTable('workout_exercises');
    pruneTable('workout_sets');
    pruneTable('exercise_prs');
  }

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Per-record version for last-write-wins across family devices.
  static DateTime _entityVersion(dynamic o) {
    if (o == null) return _epoch;
    if (o is ChatMessage) return o.editedAt ?? o.createdAt;
    if (o is Task) return o.updatedAt;
    try {
      final u = (o as dynamic).updatedAt;
      if (u is DateTime && u.millisecondsSinceEpoch > 0) return u;
    } catch (_) {}
    try {
      final c = (o as dynamic).createdAt;
      if (c is DateTime) return c;
    } catch (_) {}
    try {
      final d = (o as dynamic).date;
      if (d is DateTime) return d;
    } catch (_) {}
    try {
      final d = (o as dynamic).start;
      if (d is DateTime) return d;
    } catch (_) {}
    return _epoch;
  }

  /// Merge two lists by [id] using last-write-wins on [_entityVersion].
  ///
  /// - Same id: keep whichever record has the newer [updatedAt]/createdAt/date.
  /// - Tie → prefer cloud so the other family member's latest push applies.
  /// - Only in cloud: add (unless [_deletedKeys]).
  /// - Only in local: keep (offline-created).
  static String _mergeKeyOf(dynamic item) {
    try { return item.mergeKey as String; } catch (_) {}
    return item.id as String;
  }

  static List<T> _mergeById<T>(List<T> local, List<T> cloud) {
    if (cloud.isEmpty) return local;
    final localMap = <String, T>{};
    for (final item in local) {
      try { localMap[_mergeKeyOf(item)] = item; } catch (_) {}
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
          map[key] = item;
        }
      } catch (_) {}
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
      } catch (_) {}
    }
    return map.values.toList();
  }

  /// Collect all merge keys from an AppDB snapshot.
  static Set<String> _collectKeys(AppDB db) {
    final keys = <String>{};
    void addAll(List items) {
      for (final item in items) {
        try { keys.add(_mergeKeyOf(item)); } catch (_) {}
      }
    }
    addAll(db.users); addAll(db.families); addAll(db.familyMembers);
    addAll(db.tasks); addAll(db.events); addAll(db.recipes);
    addAll(db.mealPlans); addAll(db.lists); addAll(db.devotionals);
    addAll(db.fitness); addAll(db.budgetCategories); addAll(db.budgetEntries); addAll(db.transactions);
    addAll(db.aiHistory); addAll(db.dailyHabits); addAll(db.dailyHabitCompletions);
    addAll(db.chores); addAll(db.choreCompletions); addAll(db.polls);
    addAll(db.pollVotes); addAll(db.rewardItems); addAll(db.rewardRedemptions);
    addAll(db.savingsGoals); addAll(db.prayerWall); addAll(db.specialDates);
    addAll(db.familyPhotos); addAll(db.milestones); addAll(db.savedPlaces);
    addAll(db.userLocations); addAll(db.messages); addAll(db.healthRecords);
    addAll(db.periodCycles); addAll(db.periodSymptoms);
    addAll(db.rewards); addAll(db.readingPlans); addAll(db.externalCalendars);
    addAll(db.pantryItems);
    addAll(db.familyActivityLogs);
    addAll(db.wellnessCheckIns);
    addAll(db.exercisePrs);
    for (final p in db.fitnessPlans) {
      if (p is Map) {
        final uid = p['user_id']?.toString() ?? '';
        if (uid.isNotEmpty) keys.add('fitness_plan_$uid');
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
      'profile': Map<String, dynamic>.from(prof as Map),
      'user_id': raw['user_id']?.toString() ?? '',
      'created_at': raw['created_at']?.toString() ?? '',
      if (raw['family_id'] != null) 'family_id': raw['family_id'].toString(),
    };
  }

  static DateTime _fitnessPlanTimestamp(Map<String, dynamic> p) {
    final s = p['created_at']?.toString();
    if (s == null || s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Merge per-user AI plans for the active family (Supabase uses `user_id` + optional `family_id`).
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

    final byUser = <String, Map<String, dynamic>>{};

    for (final p in local) {
      if (p is! Map || !includeLocalRow(p)) continue;
      final n = _normalizeFitnessPlanMap(p);
      final u = n['user_id'] as String? ?? '';
      if (u.isEmpty) continue;
      byUser[u] = n;
    }

    for (final p in cloud) {
      if (p is! Map || !includeCloudRow(p)) continue;
      final n = _normalizeFitnessPlanMap(p);
      final u = n['user_id'] as String? ?? '';
      if (u.isEmpty) continue;
      final existing = byUser[u];
      if (existing == null) {
        byUser[u] = n;
        continue;
      }
      if (!_fitnessPlanTimestamp(n).isBefore(_fitnessPlanTimestamp(existing))) {
        byUser[u] = n;
      }
    }

    return byUser.values.toList();
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
      lists: _mergeById(local.lists, _safeParse(cloud['lists'], ShoppingList.fromJson)),
      devotionals: _mergeById(local.devotionals, _safeParse(cloud['devotionals'], DevotionalEntry.fromJson)),
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
  static List<T> _safeParse<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw is! List) return [];
    final results = <T>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          results.add(fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          lastError = (lastError ?? '') + 'Parse error in ${T.toString()}: $e\n';
        }
      }
    }
    return results;
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
