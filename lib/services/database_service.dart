// lib/services/database_service.dart
// FamilyHub - Local storage service with Supabase sync

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'supabase_service.dart';

class DatabaseService {
  static const String _dbKey = 'familyhub_db';
  static AppDB? _cache;

  static AppDB get db => _cache ?? AppDB.empty();

  // ── Local persistence ─────────────────────────────────────────────────────

  static Future<AppDB> loadLocal() async {
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

  static Future<void> saveLocal(AppDB db) async {
    _cache = db;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dbKey, jsonEncode(db.toJson()));
  }

  static Future<void> clearLocal() async {
    _cache = AppDB.empty();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dbKey);
  }

  // ── Cloud sync ────────────────────────────────────────────────────────────

  /// Save locally and attempt a background cloud sync.
  static Future<void> saveAndSync(AppDB db, String familyId) async {
    await saveLocal(db);
    await syncToCloud(db, familyId);
  }

  /// Push local data to Supabase. Safe to fire-and-forget.
  static Future<void> syncToCloud(AppDB db, String familyId) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await _syncToCloud(db, familyId);
    } catch (e) {
      debugPrint('[DatabaseService] Cloud sync failed: $e');
    }
  }

  /// Convert snake_case keys to camelCase for Supabase column compatibility.
  static String _snakeToCamel(String s) {
    final parts = s.split('_');
    if (parts.length <= 1) return s;
    return parts.first +
        parts.skip(1).map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}').join();
  }

  static Map<String, dynamic> _toCamel(Map<String, dynamic> row) {
    return row.map((k, v) => MapEntry(_snakeToCamel(k), v));
  }

  static List<Map<String, dynamic>> _camelRows(List<Map<String, dynamic>> rows) {
    return rows.map(_toCamel).toList();
  }

  static Future<void> _syncToCloud(AppDB db, String familyId) async {
    Future<void> up(String table, List<Map<String, dynamic>> rows,
        {String onConflict = 'id'}) async {
      if (rows.isNotEmpty) {
        try {
          await SupabaseService.upsertTable(table, _camelRows(rows),
              onConflict: onConflict);
        } catch (e) {
          debugPrint('[DatabaseService] Failed to sync $table: $e');
        }
      }
    }

    final fid = familyId;

    // Helper to upsert then delete removed rows in one step
    Future<void> upAndClean(String table, List<Map<String, dynamic>> rows,
        Set<String> localIds, {String onConflict = 'id'}) async {
      await up(table, rows, onConflict: onConflict);
      await _deleteRemovedRows(table, localIds, fid);
    }

    // Core identity tables first (other tables may reference these)
    await Future.wait([
      up('users', db.users.map((u) => u.toJson()).toList()),
      up('families', db.families.map((f) => f.toJson()).toList()),
      up('family_members', db.familyMembers.map((m) => m.toJson()).toList(),
          onConflict: 'userId,familyId'),
    ]);

    // All other tables in parallel — they're independent of each other
    await Future.wait([
      upAndClean('tasks',
          db.tasks.map((t) => {...t.toJson(), 'familyId': fid}).toList(),
          db.tasks.map((t) => t.id).toSet()),
      upAndClean('events',
          db.events.map((e) => {...e.toJson(), 'familyId': fid}).toList(),
          db.events.map((e) => e.id).toSet()),
      upAndClean('recipes',
          db.recipes.map((r) => {...r.toJson(), 'familyId': fid}).toList(),
          db.recipes.map((r) => r.id).toSet()),
      upAndClean('meal_plans',
          db.mealPlans.map((m) => {...m.toJson(), 'familyId': fid}).toList(),
          db.mealPlans.map((m) => m.id).toSet()),
      upAndClean('lists',
          db.lists.map((l) => {...l.toJson(), 'familyId': fid}).toList(),
          db.lists.map((l) => l.id).toSet()),
      upAndClean('devotionals',
          db.devotionals.map((d) => {...d.toJson(), 'familyId': fid}).toList(),
          db.devotionals.map((d) => d.id).toSet()),
      up('fitness',
          db.fitness.map((f) => f.toJson()).toList()),
      upAndClean('budget_categories',
          db.budgetCategories.map((b) => {...b.toJson(), 'familyId': fid}).toList(),
          db.budgetCategories.map((b) => b.id).toSet()),
      upAndClean('transactions',
          db.transactions.map((t) => {...t.toJson(), 'familyId': fid}).toList(),
          db.transactions.map((t) => t.id).toSet()),
      upAndClean('ai_history',
          db.aiHistory.map((a) => a.toJson()).toList(),
          db.aiHistory.map((a) => a.id).toSet()),
      upAndClean('daily_habits',
          db.dailyHabits.map((h) => h.toJson()).toList(),
          db.dailyHabits.map((h) => h.id).toSet()),
      up('daily_habit_completions',
          db.dailyHabitCompletions.map((c) => c.toJson()).toList()),
      upAndClean('chores',
          db.chores.map((c) => {...c.toJson(), 'familyId': fid}).toList(),
          db.chores.map((c) => c.id).toSet()),
      upAndClean('chore_completions',
          db.choreCompletions.map((c) => c.toJson()).toList(),
          db.choreCompletions.map((c) => c.id).toSet()),
      upAndClean('polls',
          db.polls.map((p) => {...p.toJson(), 'familyId': fid}).toList(),
          db.polls.map((p) => p.id).toSet()),
      upAndClean('poll_votes',
          db.pollVotes.map((v) => v.toJson()).toList(),
          db.pollVotes.map((v) => v.id).toSet()),
      upAndClean('reward_items',
          db.rewardItems.map((r) => {...r.toJson(), 'familyId': fid}).toList(),
          db.rewardItems.map((r) => r.id).toSet()),
      upAndClean('reward_redemptions',
          db.rewardRedemptions.map((r) => r.toJson()).toList(),
          db.rewardRedemptions.map((r) => r.id).toSet()),
      upAndClean('savings_goals',
          db.savingsGoals.map((g) => {...g.toJson(), 'familyId': fid}).toList(),
          db.savingsGoals.map((g) => g.id).toSet()),
      upAndClean('prayer_wall',
          db.prayerWall.map((p) => {...p.toJson(), 'familyId': fid}).toList(),
          db.prayerWall.map((p) => p.id).toSet()),
      upAndClean('special_dates',
          db.specialDates.map((s) => {...s.toJson(), 'familyId': fid}).toList(),
          db.specialDates.map((s) => s.id).toSet()),
      upAndClean('family_photos',
          db.familyPhotos.map((p) => {...p.toJson(), 'familyId': fid}).toList(),
          db.familyPhotos.map((p) => p.id).toSet()),
      upAndClean('milestones',
          db.milestones.map((m) => {...m.toJson(), 'familyId': fid}).toList(),
          db.milestones.map((m) => m.id).toSet()),
      upAndClean('saved_places',
          db.savedPlaces.map((s) => {...s.toJson(), 'familyId': fid}).toList(),
          db.savedPlaces.map((s) => s.id).toSet()),
      upAndClean('user_locations',
          db.userLocations.map((u) => u.toJson()).toList(),
          db.userLocations.map((u) => u.id).toSet()),
      upAndClean('messages',
          db.messages.map((m) => {...m.toJson(), 'familyId': fid}).toList(),
          db.messages.map((m) => m.id).toSet()),
      upAndClean('health_records',
          db.healthRecords.map((h) => {...h.toJson(), 'familyId': fid}).toList(),
          db.healthRecords.map((h) => h.id).toSet()),
      upAndClean('period_cycles',
          db.periodCycles.map((c) => c.toJson()).toList(),
          db.periodCycles.map((c) => c.id).toSet()),
      upAndClean('period_symptoms',
          db.periodSymptoms.map((s) => s.toJson()).toList(),
          db.periodSymptoms.map((s) => s.id).toSet()),
      upAndClean('external_calendars',
          db.externalCalendars.map((c) => {...c.toJson(), 'familyId': fid}).toList(),
          db.externalCalendars.map((c) => c.id).toSet()),
      upAndClean('rewards',
          db.rewards.map((r) => {...r.toJson(), 'familyId': fid}).toList(),
          db.rewards.map((r) => r.id).toSet()),
      upAndClean('reading_plans',
          db.readingPlans.map((r) => {...r.toJson(), 'familyId': fid}).toList(),
          db.readingPlans.map((r) => r.id).toSet()),
    ]);
  }

  /// Delete cloud rows for a family-scoped table that no longer exist locally.
  static Future<void> _deleteRemovedRows(
    String table, Set<String> localIds, String familyId,
  ) async {
    if (!SupabaseService.isConfigured) return;
    try {
      final cloudRows = await SupabaseService.client
          .from(table)
          .select('id')
          .eq('familyId', familyId);
      final cloudIds = (cloudRows as List).map((r) => r['id'] as String).toSet();
      final removed = cloudIds.difference(localIds);
      for (final id in removed) {
        await SupabaseService.deleteRows(table, {'id': id});
      }
    } catch (e) {
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e');
    }
  }

  // ── Cloud reconcile ───────────────────────────────────────────────────────

  /// Fetch cloud data, merge with local DB, and persist the result.
  /// [lastError] is set if a non-fatal parse error occurred (for debugging).
  static String? lastError;

  static Future<AppDB> reconcileCloud(AppDB local, String familyId) async {
    lastError = null;
    if (!SupabaseService.isConfigured) return local;
    try {
      final cloudData = await SupabaseService.fetchAllTables(familyId);
      final merged = _mergeWithCloud(local, cloudData);
      // Update static cache and persist so authenticate() picks up cloud data
      _cache = merged;
      await saveLocal(merged);
      return merged;
    } catch (e, st) {
      lastError = '$e\n$st';
      return local;
    }
  }

  /// Merge two lists by [id], with cloud items winning on conflict.
  static String _mergeKeyOf(dynamic item) {
    try { return item.mergeKey as String; } catch (_) {}
    return item.id as String;
  }

  static List<T> _mergeById<T>(List<T> local, List<T> cloud) {
    if (cloud.isEmpty) return local;
    if (local.isEmpty) return cloud;
    final map = <String, T>{};
    for (final item in local) {
      try {
        map[_mergeKeyOf(item)] = item;
      } catch (_) {}
    }
    for (final item in cloud) {
      try {
        map[_mergeKeyOf(item)] = item; // cloud wins on conflict
      } catch (_) {}
    }
    return map.values.toList();
  }

  static AppDB _mergeWithCloud(
    AppDB local,
    Map<String, dynamic> cloud,
  ) {
    // Parse each table individually so one bad table doesn't kill everything.
    // Merge by ID so offline-created items aren't lost.
    return AppDB(
      users: _mergeById(local.users, _safeParse(cloud['users'], User.fromJson)),
      families: _mergeById(local.families, _safeParse(cloud['families'], Family.fromJson)),
      familyMembers: _mergeById(local.familyMembers, _safeParse(cloud['family_members'], FamilyMember.fromJson)),
      tasks: _mergeById(local.tasks, _safeParse(cloud['tasks'], Task.fromJson)),
      events: _mergeById(local.events, _safeParse(cloud['events'], CalendarEvent.fromJson)),
      recipes: _mergeById(local.recipes, _safeParse(cloud['recipes'], Recipe.fromJson)),
      mealPlans: _mergeById(local.mealPlans, _safeParse(cloud['meal_plans'], MealPlanEntry.fromJson)),
      lists: _mergeById(local.lists, _safeParse(cloud['lists'], ShoppingList.fromJson)),
      devotionals: _mergeById(local.devotionals, _safeParse(cloud['devotionals'], DevotionalEntry.fromJson)),
      fitness: _mergeById(local.fitness, _safeParse(cloud['fitness'], FitnessMetric.fromJson)),
      budgetCategories: _mergeById(local.budgetCategories, _safeParse(cloud['budget_categories'], BudgetCategoryRecord.fromJson)),
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
      readingPlans: _mergeById(local.readingPlans, _safeParse(cloud['reading_plans'], ReadingPlan.fromJson)),
      externalCalendars: _mergeById(local.externalCalendars, _safeParse(cloud['external_calendars'], ExternalCalendar.fromJson)),
    );
  }

  /// Parse a list from cloud data, skipping individual items that fail.
  static List<T> _safeParse<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw is! List) return [];
    final results = <T>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          results.add(fromJson(item));
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
