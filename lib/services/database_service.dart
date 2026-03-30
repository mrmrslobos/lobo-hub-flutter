// lib/services/database_service.dart
// FamilyHub - Local storage service with Supabase sync

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/fitness_plan_storage.dart';
import 'exercise_plan_media_service.dart';
import 'field_encryption_service.dart';
import 'supabase_service.dart';

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

  /// Families columns omitted on upsert until DB has them (see migrations/06).
  static const _familiesCloudOmit = {'currency', 'trial_start_date'};

  /// fitness_plans.family_id until migration 18 is applied everywhere.
  /// plan_id: migration 25 (optional on older DBs).
  static const _fitnessPlansCloudOmit = {'family_id', 'plan_id'};

  /// Tasks columns some older DBs lack (PGRST204).
  static const _tasksCloudOmit = {'completed_by', 'updated_by', 'due_time', 'reminder_minutes'};

  /// Chores columns older DBs may lack until migration.
  static const _choresCloudOmit = {'rotation_enabled', 'rotation_cursor'};

  /// Workout exercise columns older DBs may lack until migration 16.
  static const _workoutExerciseCloudOmit = {
    'technique_notes',
    'reference_url',
    'technique_image_url',
    'exercise_db_id',
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
  static const _eventsCloudOmit = <String>{};

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

  /// Clears cached DB state and **every** SharedPreferences key (theme, locale,
  /// notification prefs, etc.). Use for destructive "reset app data" flows;
  /// [clearLocal] is enough for normal logout.
  static Future<void> wipeAllLocalStorage() async {
    _cache = AppDB.empty();
    _deletedKeys.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
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

  static Map<String, dynamic> _recipeRowForCloud(Recipe r, String familyId) {
    final row = Map<String, dynamic>.from(r.toJson());
    row['family_id'] = familyId;
    for (final k in _recipeCloudOmit) {
      row.remove(k);
    }
    return row;
  }

  static Map<String, dynamic> _mealPlanRowForCloud(
    MealPlanEntry m,
    String familyId,
  ) {
    final row = Map<String, dynamic>.from(m.toJson());
    row['family_id'] = familyId;
    for (final k in _mealPlanCloudOmit) {
      row.remove(k);
    }
    return row;
  }

  static Map<String, dynamic> _prayerWallRowForCloud(
    PrayerWallEntry p,
    String familyId,
  ) {
    final row = Map<String, dynamic>.from(p.toJson());
    row['family_id'] = familyId;
    for (final k in _prayerWallCloudOmit) {
      row.remove(k);
    }
    return row;
  }

  /// Upserts [recipes], [meal_plans], and [pantry_items] for [familyId] with
  /// tombstone deletes. Await after saves so meal data reaches Supabase even when
  /// the full background sync fails (and so we never upsert another family's
  /// recipes with the active [family_id]).
  static Future<void> pushFamilyMealsToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    const chunk = 40;

    final recipes = db.recipes.where((r) => r.familyId == familyId).toList();
    final recipeRows =
        recipes.map((r) => _recipeRowForCloud(r, familyId)).toList();
    final recipeIds = recipes.map((r) => r.id).toSet();
    for (var i = 0; i < recipeRows.length; i += chunk) {
      final slice =
          recipeRows.sublist(i, math.min(i + chunk, recipeRows.length));
      try {
        await SupabaseService.upsertTable('recipes', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] recipes chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('recipes', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] recipe ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('recipes', recipeIds, familyId);

    final meals =
        db.mealPlans.where((m) => m.familyId == familyId).toList();
    final mealRows =
        meals.map((m) => _mealPlanRowForCloud(m, familyId)).toList();
    final mealIds = meals.map((m) => m.id).toSet();
    for (var i = 0; i < mealRows.length; i += chunk) {
      final slice = mealRows.sublist(i, math.min(i + chunk, mealRows.length));
      try {
        await SupabaseService.upsertTable('meal_plans', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] meal_plans chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('meal_plans', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] meal_plan ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('meal_plans', mealIds, familyId);

    final pantry =
        db.pantryItems.where((p) => p.familyId == familyId).toList();
    final pantryRows = pantry.map((p) => p.toJson()).toList();
    final pantryIds = pantry.map((p) => p.id).toSet();
    for (var i = 0; i < pantryRows.length; i += chunk) {
      final slice =
          pantryRows.sublist(i, math.min(i + chunk, pantryRows.length));
      try {
        await SupabaseService.upsertTable('pantry_items', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] pantry_items chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('pantry_items', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] pantry_item ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('pantry_items', pantryIds, familyId);
  }

  /// Upserts the current user's fitness metrics, AI plans, logs, workout graph,
  /// and PRs for [familyId], with tombstone deletes (same pattern as meals/tasks).
  static Future<void> pushFamilyFitnessToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    const chunk = 40;

    final metrics = db.fitness.where((f) => f.userId == uid).toList();
    final metricRows = metrics.map((f) => f.toJson()).toList();
    final metricIds = metrics.map((f) => f.id).toSet();
    for (var i = 0; i < metricRows.length; i += chunk) {
      final slice =
          metricRows.sublist(i, math.min(i + chunk, metricRows.length));
      try {
        await SupabaseService.upsertTable('fitness', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] fitness chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('fitness', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] fitness metric ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedUserRows('fitness', metricIds, uid);

    final plans = db.fitnessPlans
        .whereType<Map>()
        .where((p) => p['user_id'] == uid)
        .map((p) {
          final row = fitnessPlanRowForCloud(
            Map<String, dynamic>.from(p as Map),
            familyId,
          );
          for (final k in _fitnessPlansCloudOmit) {
            row.remove(k);
          }
          return row;
        })
        .toList();
    final planIds = db.fitnessPlans
        .whereType<Map>()
        .where((p) => p['user_id'] == uid)
        .map((p) => fitnessPlanCloudRowId(p, familyId))
        .toSet();
    for (var i = 0; i < plans.length; i += chunk) {
      final slice = plans.sublist(i, math.min(i + chunk, plans.length));
      try {
        await SupabaseService.upsertTable('fitness_plans', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] fitness_plans chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('fitness_plans', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] fitness_plan ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedUserRows('fitness_plans', planIds, uid);

    final logs = db.fitnessLogs
        .where((l) => l.familyId == familyId && l.userId == uid)
        .toList();
    final logRows =
        logs.map((l) => {...l.toJson(), 'family_id': familyId}).toList();
    final logIds = logs.map((l) => l.id).toSet();
    for (var i = 0; i < logRows.length; i += chunk) {
      final slice = logRows.sublist(i, math.min(i + chunk, logRows.length));
      try {
        await SupabaseService.upsertTable('fitness_logs', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] fitness_logs chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('fitness_logs', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] fitness_log ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('fitness_logs', logIds, familyId);

    final sessions = db.workoutSessions
        .where((s) => s.familyId == familyId && s.userId == uid)
        .toList();
    final sessionRows = sessions.map((s) {
      final row = Map<String, dynamic>.from(s.toJson());
      row['family_id'] = familyId;
      for (final k in _workoutSessionCloudOmit) {
        row.remove(k);
      }
      return row;
    }).toList();
    final sessionIds = sessions.map((s) => s.id).toSet();
    for (var i = 0; i < sessionRows.length; i += chunk) {
      final slice =
          sessionRows.sublist(i, math.min(i + chunk, sessionRows.length));
      try {
        await SupabaseService.upsertTable('workout_sessions', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] workout_sessions chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('workout_sessions', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] workout_session ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('workout_sessions', sessionIds, familyId);

    final wex = db.workoutExercises
        .where((e) => e.familyId == familyId && e.userId == uid)
        .toList();
    final wexRows = wex.map((e) {
      final row = Map<String, dynamic>.from(e.toJson());
      row['family_id'] = familyId;
      for (final k in _workoutExerciseCloudOmit) {
        row.remove(k);
      }
      return row;
    }).toList();
    final wexIds = wex.map((e) => e.id).toSet();
    for (var i = 0; i < wexRows.length; i += chunk) {
      final slice = wexRows.sublist(i, math.min(i + chunk, wexRows.length));
      try {
        await SupabaseService.upsertTable('workout_exercises', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] workout_exercises chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('workout_exercises', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] workout_exercise ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('workout_exercises', wexIds, familyId);

    final wsets = db.workoutSets
        .where((set) => set.familyId == familyId && set.userId == uid)
        .toList();
    final setRows =
        wsets.map((set) => {...set.toJson(), 'family_id': familyId}).toList();
    final setIds = wsets.map((set) => set.id).toSet();
    for (var i = 0; i < setRows.length; i += chunk) {
      final slice = setRows.sublist(i, math.min(i + chunk, setRows.length));
      try {
        await SupabaseService.upsertTable('workout_sets', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] workout_sets chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('workout_sets', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] workout_set ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('workout_sets', setIds, familyId);

    final prs = db.exercisePrs
        .where((p) => p.familyId == familyId && p.userId == uid)
        .toList();
    final prRows = prs.map((p) => p.toJson()).toList();
    final prIds = prs.map((p) => p.id).toSet();
    for (var i = 0; i < prRows.length; i += chunk) {
      final slice = prRows.sublist(i, math.min(i + chunk, prRows.length));
      try {
        await SupabaseService.upsertTable('exercise_prs', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] exercise_prs chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('exercise_prs', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] exercise_pr ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('exercise_prs', prIds, familyId);
  }

  /// Upserts [period_cycles] and [period_symptoms] for the signed-in user and
  /// [familyId] only. Prevents cross-user / cross-home row reassignment during
  /// full sync (RLS is per-user, but the client was sending every local row).
  static Future<void> pushFamilyPeriodDataToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    const chunk = 40;

    final cycles = db.periodCycles
        .where((c) => c.userId == uid && c.familyId == familyId)
        .toList();
    final cycleRows = cycles.map((c) => c.toJson()).toList();
    final cycleIds = cycles.map((c) => c.id).toSet();
    for (var i = 0; i < cycleRows.length; i += chunk) {
      final slice =
          cycleRows.sublist(i, math.min(i + chunk, cycleRows.length));
      try {
        await SupabaseService.upsertTable('period_cycles', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] period_cycles chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('period_cycles', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] period_cycle ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedUserRows('period_cycles', cycleIds, uid);

    final symptoms = db.periodSymptoms
        .where((s) => s.userId == uid && s.familyId == familyId)
        .toList();
    final symptomRows = symptoms.map((s) => s.toJson()).toList();
    final symptomIds = symptoms.map((s) => s.id).toSet();
    for (var i = 0; i < symptomRows.length; i += chunk) {
      final slice =
          symptomRows.sublist(i, math.min(i + chunk, symptomRows.length));
      try {
        await SupabaseService.upsertTable('period_symptoms', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] period_symptoms chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('period_symptoms', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] period_symptom ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedUserRows('period_symptoms', symptomIds, uid);
  }

  /// Upserts [devotionals] and [reading_plans] for [familyId] only. Prevents
  /// cross-home reassignment when syncing (same issue as recipes/lists).
  static Future<void> pushFamilyDevotionalsToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    const chunk = 40;

    final devotionals =
        db.devotionals.where((d) => d.familyId == familyId).toList();
    final devRows = devotionals
        .map((d) => {...d.toJson(), 'family_id': familyId})
        .toList();
    final devIds = devotionals.map((d) => d.id).toSet();
    for (var i = 0; i < devRows.length; i += chunk) {
      final slice = devRows.sublist(i, math.min(i + chunk, devRows.length));
      try {
        await SupabaseService.upsertTable('devotionals', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] devotionals chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('devotionals', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] devotional ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('devotionals', devIds, familyId);

    final plans =
        db.readingPlans.where((r) => r.familyId == familyId).toList();
    final planRows = plans
        .map((r) => {...r.toJson(), 'family_id': familyId})
        .toList();
    final planIds = plans.map((r) => r.id).toSet();
    for (var i = 0; i < planRows.length; i += chunk) {
      final slice = planRows.sublist(i, math.min(i + chunk, planRows.length));
      try {
        await SupabaseService.upsertTable('reading_plans', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] reading_plans chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('reading_plans', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] reading_plan ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('reading_plans', planIds, familyId);
  }

  /// Upserts [prayer_wall] rows for [familyId] only (prevents cross-home reassignment).
  static Future<void> pushFamilyPrayerWallToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    const chunk = 40;

    final posts =
        db.prayerWall.where((p) => p.familyId == familyId).toList();
    final rows =
        posts.map((p) => _prayerWallRowForCloud(p, familyId)).toList();
    final ids = posts.map((p) => p.id).toSet();
    for (var i = 0; i < rows.length; i += chunk) {
      final slice = rows.sublist(i, math.min(i + chunk, rows.length));
      try {
        await SupabaseService.upsertTable('prayer_wall', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] prayer_wall chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('prayer_wall', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] prayer_wall ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('prayer_wall', ids, familyId);
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

  /// Upserts all shopping lists for [familyId] and applies tombstone deletes.
  /// Await after saves so list edits reach Supabase even when the full background
  /// sync fails (same pattern as [pushFamilyTasksToCloudNow]).
  static Future<void> pushFamilyListsToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    final familyLists =
        db.lists.where((l) => l.familyId == familyId).toList();
    final localIds = familyLists.map((l) => l.id).toSet();
    const chunk = 25;
    for (var i = 0; i < familyLists.length; i += chunk) {
      final slice = familyLists.sublist(
          i, math.min(i + chunk, familyLists.length));
      final rows = slice
          .map((l) => {...l.toJson(), 'family_id': familyId})
          .toList();
      try {
        await SupabaseService.upsertTable('lists', rows);
      } catch (e) {
        debugPrint('[DatabaseService] lists chunk upsert failed, retry per row: $e');
        for (final l in slice) {
          try {
            await SupabaseService.upsertTable('lists', [
              {...l.toJson(), 'family_id': familyId},
            ]);
          } catch (e2) {
            debugPrint('[DatabaseService] list ${l.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('lists', localIds, familyId);
  }

  /// Upserts all calendar events for [familyId] and applies tombstone deletes.
  static Future<void> pushFamilyEventsToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    final familyEvents =
        db.events.where((e) => e.familyId == familyId).toList();
    final localIds = familyEvents.map((e) => e.id).toSet();
    const chunk = 40;
    for (var i = 0; i < familyEvents.length; i += chunk) {
      final slice = familyEvents.sublist(
          i, math.min(i + chunk, familyEvents.length));
      final rows = slice
          .map((e) => {...e.toJson(), 'family_id': familyId})
          .toList();
      for (final m in rows) {
        for (final k in _eventsCloudOmit) {
          m.remove(k);
        }
      }
      try {
        await SupabaseService.upsertTable('events', rows);
      } catch (e) {
        debugPrint('[DatabaseService] events chunk upsert failed, retry per row: $e');
        for (final ev in slice) {
          try {
            final one = {...ev.toJson(), 'family_id': familyId};
            for (final k in _eventsCloudOmit) {
              one.remove(k);
            }
            await SupabaseService.upsertTable('events', [one]);
          } catch (e2) {
            debugPrint('[DatabaseService] event ${ev.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('events', localIds, familyId);
  }

  /// Upserts chores and chore completions for [familyId] and applies tombstone deletes.
  static Future<void> pushFamilyChoresToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    final chores = db.chores.where((c) => c.familyId == familyId).toList();
    final choreIds = chores.map((c) => c.id).toSet();
    final completions =
        db.choreCompletions.where((c) => c.familyId == familyId).toList();
    final completionIds = completions.map((c) => c.id).toSet();

    const chunk = 40;
    for (var i = 0; i < chores.length; i += chunk) {
      final slice = chores.sublist(i, math.min(i + chunk, chores.length));
      final rows = slice.map(_choreRowForCloud).toList();
      try {
        await SupabaseService.upsertTable('chores', rows);
      } catch (e) {
        debugPrint('[DatabaseService] chores chunk upsert failed, retry per row: $e');
        for (final c in slice) {
          try {
            await SupabaseService.upsertTable('chores', [_choreRowForCloud(c)]);
          } catch (e2) {
            debugPrint('[DatabaseService] chore ${c.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('chores', choreIds, familyId);

    for (var i = 0; i < completions.length; i += chunk) {
      final slice =
          completions.sublist(i, math.min(i + chunk, completions.length));
      final rows = slice.map((c) => c.toJson()).toList();
      try {
        await SupabaseService.upsertTable('chore_completions', rows);
      } catch (e) {
        debugPrint(
            '[DatabaseService] chore_completions chunk upsert failed, retry per row: $e');
        for (final c in slice) {
          try {
            await SupabaseService.upsertTable('chore_completions', [c.toJson()]);
          } catch (e2) {
            debugPrint('[DatabaseService] chore_completion ${c.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('chore_completions', completionIds, familyId);
  }

  /// Upserts polls and poll_votes for [familyId], tombstone-deletes removed rows,
  /// and removes orphan [poll_votes] rows whose [poll_id] no longer exists locally.
  static Future<void> pushFamilyPollsToCloudNow(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    final polls = db.polls.where((p) => p.familyId == familyId).toList();
    final pollIds = polls.map((p) => p.id).toSet();
    final votes =
        db.pollVotes.where((v) => v.familyId == familyId).toList();
    final voteIds = votes.map((v) => v.id).toSet();

    const chunk = 40;
    for (var i = 0; i < polls.length; i += chunk) {
      final slice = polls.sublist(i, math.min(i + chunk, polls.length));
      final rows = slice
          .map((p) => {...p.toJson(), 'family_id': familyId})
          .toList();
      try {
        await SupabaseService.upsertTable('polls', rows);
      } catch (e) {
        debugPrint('[DatabaseService] polls chunk upsert failed, retry per row: $e');
        for (final p in slice) {
          try {
            await SupabaseService.upsertTable('polls', [
              {...p.toJson(), 'family_id': familyId},
            ]);
          } catch (e2) {
            debugPrint('[DatabaseService] poll ${p.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('polls', pollIds, familyId);

    for (var i = 0; i < votes.length; i += chunk) {
      final slice = votes.sublist(i, math.min(i + chunk, votes.length));
      final rows = slice.map((v) => v.toJson()).toList();
      try {
        await SupabaseService.upsertTable('poll_votes', rows);
      } catch (e) {
        debugPrint(
            '[DatabaseService] poll_votes chunk upsert failed, retry per row: $e');
        for (final v in slice) {
          try {
            await SupabaseService.upsertTable('poll_votes', [v.toJson()]);
          } catch (e2) {
            debugPrint('[DatabaseService] poll_vote ${v.id} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('poll_votes', voteIds, familyId);

    try {
      final cloudVotes = await SupabaseService.client
          .from('poll_votes')
          .select('id,poll_id')
          .eq('family_id', familyId);
      for (final r in cloudVotes as List) {
        final pid = r['poll_id'] as String?;
        final vid = r['id'] as String?;
        if (pid == null || vid == null) continue;
        if (!pollIds.contains(pid)) {
          await SupabaseService.deleteRows('poll_votes', {'id': vid});
        }
      }
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('PGRST205') &&
          !msg.contains('Could not find the table')) {
        debugPrint('[DatabaseService] poll_votes orphan cleanup failed: $e');
      }
    }
  }

  /// Upserts special_dates (occasions) for [familyId] and tombstone-deletes removed rows.
  static Future<void> pushFamilySpecialDatesToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    final rows = db.specialDates
        .where((s) => s.familyId == familyId)
        .map((s) => {...s.toJson(), 'family_id': familyId})
        .toList();
    final localIds = rows.map((r) => r['id'] as String).toSet();
    const chunk = 40;
    for (var i = 0; i < rows.length; i += chunk) {
      final slice = rows.sublist(i, math.min(i + chunk, rows.length));
      try {
        await SupabaseService.upsertTable('special_dates', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] special_dates chunk upsert failed, retry per row: $e');
        for (final r in slice) {
          try {
            await SupabaseService.upsertTable('special_dates', [r]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] special_date ${r['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('special_dates', localIds, familyId);
  }

  /// Upserts [family_photos] and [milestones] for [familyId] and tombstone-deletes removed rows.
  static Future<void> pushFamilyPhotosAndMilestonesToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    const chunk = 40;

    final photos = db.familyPhotos.where((p) => p.familyId == familyId).toList();
    final photoRows =
        photos.map((p) => {...p.toJson(), 'family_id': familyId}).toList();
    final photoIds = photos.map((p) => p.id).toSet();
    for (var i = 0; i < photoRows.length; i += chunk) {
      final slice = photoRows.sublist(i, math.min(i + chunk, photoRows.length));
      try {
        await SupabaseService.upsertTable('family_photos', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] family_photos chunk upsert failed, retry per row: $e');
        for (final r in slice) {
          try {
            await SupabaseService.upsertTable('family_photos', [r]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] family_photo ${r['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('family_photos', photoIds, familyId);

    final milestones =
        db.milestones.where((m) => m.familyId == familyId).toList();
    final msRows =
        milestones.map((m) => {...m.toJson(), 'family_id': familyId}).toList();
    final msIds = milestones.map((m) => m.id).toSet();
    for (var i = 0; i < msRows.length; i += chunk) {
      final slice = msRows.sublist(i, math.min(i + chunk, msRows.length));
      try {
        await SupabaseService.upsertTable('milestones', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] milestones chunk upsert failed, retry per row: $e');
        for (final r in slice) {
          try {
            await SupabaseService.upsertTable('milestones', [r]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] milestone ${r['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('milestones', msIds, familyId);
  }

  /// Upserts [user_locations] and [saved_places] for [familyId] and tombstone-deletes removed rows.
  static Future<void> pushFamilyLocationDataToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    const chunk = 40;

    final locs =
        db.userLocations.where((u) => u.familyId == familyId).toList();
    final locRows = locs.map((u) => u.toJson()).toList();
    final locIds = locs.map((u) => u.id).toSet();
    for (var i = 0; i < locRows.length; i += chunk) {
      final slice = locRows.sublist(i, math.min(i + chunk, locRows.length));
      try {
        await SupabaseService.upsertTable('user_locations', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] user_locations chunk upsert failed, retry per row: $e');
        for (final r in slice) {
          try {
            await SupabaseService.upsertTable('user_locations', [r]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] user_location ${r['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('user_locations', locIds, familyId);

    final places =
        db.savedPlaces.where((p) => p.familyId == familyId).toList();
    final placeRows =
        places.map((p) => {...p.toJson(), 'family_id': familyId}).toList();
    final placeIds = places.map((p) => p.id).toSet();
    for (var i = 0; i < placeRows.length; i += chunk) {
      final slice = placeRows.sublist(i, math.min(i + chunk, placeRows.length));
      try {
        await SupabaseService.upsertTable('saved_places', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] saved_places chunk upsert failed, retry per row: $e');
        for (final r in slice) {
          try {
            await SupabaseService.upsertTable('saved_places', [r]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] saved_place ${r['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('saved_places', placeIds, familyId);
  }

  /// Upserts [health_records] for [familyId] and tombstone-deletes removed rows.
  static Future<void> pushFamilyHealthRecordsToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    final rows = db.healthRecords
        .where((h) => h.familyId == familyId)
        .map((h) => {...h.toJson(), 'family_id': familyId})
        .toList();
    final localIds = rows.map((r) => r['id'] as String).toSet();
    const chunk = 25;
    for (var i = 0; i < rows.length; i += chunk) {
      final slice = rows.sublist(i, math.min(i + chunk, rows.length));
      try {
        await SupabaseService.upsertTable('health_records', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] health_records chunk upsert failed, retry per row: $e');
        for (final r in slice) {
          try {
            await SupabaseService.upsertTable('health_records', [r]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] health_record ${r['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedRows('health_records', localIds, familyId);
  }

  static Set<String> _familyMemberUserIds(AppDB db, String familyId) => db
      .familyMembers
      .where((m) => m.familyId == familyId)
      .map((m) => m.userId)
      .toSet();

  /// Habits that belong to this home ([family_id] match) or are legacy personal
  /// rows ([family_id] null) for a member of this family.
  static List<DailyHabit> _dailyHabitsForFamilySync(AppDB db, String familyId) {
    final memberIds = _familyMemberUserIds(db, familyId);
    return db.dailyHabits.where((h) {
      if (h.familyId == familyId) return true;
      if (h.familyId == null && memberIds.contains(h.userId)) return true;
      return false;
    }).toList();
  }

  static List<DailyHabitCompletion> _habitCompletionsToSyncForFamily(
    AppDB db,
    String familyId,
    String userId,
  ) {
    final habitIds =
        _dailyHabitsForFamilySync(db, familyId).map((h) => h.id).toSet();
    return db.dailyHabitCompletions
        .where((c) => c.userId == userId && habitIds.contains(c.habitId))
        .toList();
  }

  /// Tombstone-delete removed [daily_habits] rows, including legacy rows with
  /// null [family_id] (standard [_deleteRemovedRows] only sees [family_id] = [familyId]).
  static Future<void> _deleteRemovedHabitRows(String familyId) async {
    if (!SupabaseService.isConfigured || _deletedKeys.isEmpty) return;
    try {
      final cloudRows = await SupabaseService.client
          .from('daily_habits')
          .select('id')
          .or('family_id.eq.$familyId,family_id.is.null');
      final cloudIds =
          (cloudRows as List).map((r) => r['id'] as String).toSet();
      final removed = cloudIds.intersection(_deletedKeys);
      for (final id in removed) {
        await SupabaseService.deleteRows('daily_habits', {'id': id});
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return;
      }
      debugPrint('[DatabaseService] Failed to delete removed daily_habits rows: $e');
    }
  }

  /// Upserts [daily_habits] and the current user's [daily_habit_completions] for
  /// this family, with tombstone deletes (same reliability pattern as lists/tasks).
  static Future<void> pushFamilyHabitsToCloudNow(
    AppDB db,
    String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    const chunk = 40;
    final habits = _dailyHabitsForFamilySync(db, familyId);
    final habitRows = habits.map((h) => h.toJson()).toList();
    final habitIds = habits.map((h) => h.id).toSet();

    for (var i = 0; i < habitRows.length; i += chunk) {
      final slice =
          habitRows.sublist(i, math.min(i + chunk, habitRows.length));
      try {
        await SupabaseService.upsertTable('daily_habits', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] daily_habits chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable('daily_habits', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] daily_habit ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedHabitRows(familyId);

    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    final completions = _habitCompletionsToSyncForFamily(db, familyId, uid);
    final completionRows = completions.map((c) => c.toJson()).toList();
    final completionIds = completions.map((c) => c.id).toSet();

    for (var i = 0; i < completionRows.length; i += chunk) {
      final slice =
          completionRows.sublist(i, math.min(i + chunk, completionRows.length));
      try {
        await SupabaseService.upsertTable('daily_habit_completions', slice);
      } catch (e) {
        debugPrint(
            '[DatabaseService] daily_habit_completions chunk upsert failed, retry per row: $e');
        for (var j = 0; j < slice.length; j++) {
          try {
            await SupabaseService.upsertTable(
                'daily_habit_completions', [slice[j]]);
          } catch (e2) {
            debugPrint(
                '[DatabaseService] daily_habit_completion ${slice[j]['id']} sync failed: $e2');
          }
        }
      }
    }
    await _deleteRemovedUserRows('daily_habit_completions', completionIds, uid);
  }

  /// Push local data to Supabase. Safe to fire-and-forget.
  /// Syncs for the same [familyId] are serialized so concurrent [saveAndSync]
  /// calls cannot leave Supabase with an older snapshot.
  static Future<void> syncToCloud(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    final previous = _syncTailByFamily[familyId] ?? Future<void>.value();
    final completer = Completer<void>();
    _syncTailByFamily[familyId] = completer.future;
    try {
      await previous.catchError((_) {});
      try {
        await _syncToCloud(db, familyId);
      } catch (e) {
        debugPrint('[DatabaseService] Cloud sync failed: $e');
      }
    } finally {
      completer.complete();
      if (identical(_syncTailByFamily[familyId], completer.future)) {
        _syncTailByFamily.remove(familyId);
      }
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
      // lists: need real updated_at for merge — otherwise row stays at DB default
      // and another device's stale copy can win last-write-wins.
      const keepUpdatedAt = {'user_locations', 'lists', 'families'};
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
              .where((r) => r.familyId == fid)
              .map((r) => _recipeRowForCloud(r, fid))
              .toList(),
          db.recipes.where((r) => r.familyId == fid).map((r) => r.id).toSet()),
      upAndClean(
          'meal_plans',
          db.mealPlans
              .where((m) => m.familyId == fid)
              .map((m) => _mealPlanRowForCloud(m, fid))
              .toList(),
          db.mealPlans.where((m) => m.familyId == fid).map((m) => m.id).toSet()),
      upAndClean('lists',
          db.lists.map((l) => {...l.toJson(), 'family_id': fid}).toList(),
          db.lists.map((l) => l.id).toSet()),
      upAndClean(
          'devotionals',
          db.devotionals
              .where((d) => d.familyId == fid)
              .map((d) => {...d.toJson(), 'family_id': fid})
              .toList(),
          db.devotionals.where((d) => d.familyId == fid).map((d) => d.id).toSet()),
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
                .map((p) => fitnessPlanCloudRowId(p, fid))
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
      if (currentUserId != null)
        upAndClean(
          'exercise_prs',
          db.exercisePrs
              .where((p) => p.familyId == fid && p.userId == currentUserId)
              .map((p) => p.toJson())
              .toList(),
          db.exercisePrs
              .where((p) => p.familyId == fid && p.userId == currentUserId)
              .map((p) => p.id)
              .toSet(),
        )
      else
        Future.value(),
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
      (() async {
        final habits = _dailyHabitsForFamilySync(db, fid);
        await up('daily_habits', habits.map((h) => h.toJson()).toList());
        await _deleteRemovedHabitRows(fid);
      })(),
      if (currentUserId != null)
        (() async {
          final completions =
              _habitCompletionsToSyncForFamily(db, fid, currentUserId);
          await up(
              'daily_habit_completions',
              completions.map((c) => c.toJson()).toList());
          await _deleteRemovedUserRows(
            'daily_habit_completions',
            completions.map((c) => c.id).toSet(),
            currentUserId,
          );
        })()
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
      upAndClean(
          'prayer_wall',
          db.prayerWall
              .where((p) => p.familyId == fid)
              .map((p) => _prayerWallRowForCloud(p, fid))
              .toList(),
          db.prayerWall.where((p) => p.familyId == fid).map((p) => p.id).toSet()),
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
      if (currentUserId != null)
        Future.wait([
          upAndCleanUser(
            'period_cycles',
            db.periodCycles
                .where((c) =>
                    c.userId == currentUserId && c.familyId == fid)
                .map((c) => c.toJson())
                .toList(),
            db.periodCycles
                .where((c) =>
                    c.userId == currentUserId && c.familyId == fid)
                .map((c) => c.id)
                .toSet(),
            userId: currentUserId,
          ),
          upAndCleanUser(
            'period_symptoms',
            db.periodSymptoms
                .where((s) =>
                    s.userId == currentUserId && s.familyId == fid)
                .map((s) => s.toJson())
                .toList(),
            db.periodSymptoms
                .where((s) =>
                    s.userId == currentUserId && s.familyId == fid)
                .map((s) => s.id)
                .toSet(),
            userId: currentUserId,
          ),
        ])
      else
        Future.value(),
      upAndClean('external_calendars',
          db.externalCalendars.map((c) => {...c.toJson(), 'family_id': fid}).toList(),
          db.externalCalendars.map((c) => c.id).toSet()),
      upAndClean('rewards',
          db.rewards.map((r) => {...r.toJson(), 'family_id': fid}).toList(),
          db.rewards.map((r) => r.id).toSet()),
      upAndClean(
          'reading_plans',
          db.readingPlans
              .where((r) => r.familyId == fid)
              .map((r) => {...r.toJson(), 'family_id': fid})
              .toList(),
          db.readingPlans.where((r) => r.familyId == fid).map((r) => r.id).toSet()),
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
    if (o is Family) return o.updatedAt;
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
      'profile': Map<String, dynamic>.from(prof as Map),
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
      lists: _mergeById(
          local.lists, _safeParse(cloud['lists'], ShoppingList.fromJson)),
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
