// lib/services/database_service.dart
// FamilyHub - Local storage service with Supabase sync

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';
import 'dart:math' as math;

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
    if (SupabaseService.isConfigured) {
      try {
        await _syncToCloud(db, familyId);
      } catch (_) {
        // Local save already succeeded; ignore cloud errors.
      }
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
        await SupabaseService.upsertTable(table, _camelRows(rows),
            onConflict: onConflict);
      }
    }

    final fid = familyId;

    // Core identity tables
    await up('users', db.users.map((u) => u.toJson()).toList());
    await up('families', db.families.map((f) => f.toJson()).toList());
    await up('family_members', db.familyMembers.map((m) => m.toJson()).toList(),
        onConflict: 'userId,familyId');

    await up('tasks',
        db.tasks.map((t) => {...t.toJson(), 'familyId': fid}).toList());
    await up('events',
        db.events.map((e) => {...e.toJson(), 'familyId': fid}).toList());
    await up('recipes',
        db.recipes.map((r) => {...r.toJson(), 'familyId': fid}).toList());
    await up('meal_plans',
        db.mealPlans.map((m) => {...m.toJson(), 'familyId': fid}).toList());
    await up('lists',
        db.lists.map((l) => {...l.toJson(), 'familyId': fid}).toList());
    await up('devotionals',
        db.devotionals.map((d) => {...d.toJson(), 'familyId': fid}).toList());
    await up('fitness_metrics',
        db.fitness.map((f) => f.toJson()).toList());
    await up('budget_categories',
        db.budgetCategories.map((b) => {...b.toJson(), 'familyId': fid}).toList());
    await up('transactions',
        db.transactions.map((t) => {...t.toJson(), 'familyId': fid}).toList());
    await up('ai_history',
        db.aiHistory.map((a) => a.toJson()).toList());
    await up('daily_habits',
        db.dailyHabits.map((h) => h.toJson()).toList());
    await up('daily_habit_completions',
        db.dailyHabitCompletions.map((c) => c.toJson()).toList());
    await up('chores',
        db.chores.map((c) => {...c.toJson(), 'familyId': fid}).toList());
    await up('chore_completions',
        db.choreCompletions.map((c) => c.toJson()).toList());
    await up('polls',
        db.polls.map((p) => {...p.toJson(), 'familyId': fid}).toList());
    await up('poll_votes',
        db.pollVotes.map((v) => v.toJson()).toList());
    await up('reward_items',
        db.rewardItems.map((r) => {...r.toJson(), 'familyId': fid}).toList());
    await up('reward_redemptions',
        db.rewardRedemptions.map((r) => r.toJson()).toList());
    await up('savings_goals',
        db.savingsGoals.map((g) => {...g.toJson(), 'familyId': fid}).toList());
    await up('prayer_wall',
        db.prayerWall.map((p) => {...p.toJson(), 'familyId': fid}).toList());
    await up('special_dates',
        db.specialDates.map((s) => {...s.toJson(), 'familyId': fid}).toList());
    await up('family_photos',
        db.familyPhotos.map((p) => {...p.toJson(), 'familyId': fid}).toList());
    await up('milestones',
        db.milestones.map((m) => {...m.toJson(), 'familyId': fid}).toList());
    await up('saved_places',
        db.savedPlaces.map((s) => {...s.toJson(), 'familyId': fid}).toList());
    await up('user_locations',
        db.userLocations.map((u) => u.toJson()).toList());
    await up('messages',
        db.messages.map((m) => {...m.toJson(), 'familyId': fid}).toList());
    await up('health_records',
        db.healthRecords.map((h) => {...h.toJson(), 'familyId': fid}).toList());
    await up('period_cycles',
        db.periodCycles.map((c) => c.toJson()).toList());
    await up('period_symptoms',
        db.periodSymptoms.map((s) => s.toJson()).toList());
    await up('external_calendars',
        db.externalCalendars.map((c) => {...c.toJson(), 'familyId': fid}).toList());
    await up('rewards',
        db.rewards.map((r) => {...r.toJson(), 'familyId': fid}).toList());
    await up('reading_plans',
        db.readingPlans.map((r) => {...r.toJson(), 'familyId': fid}).toList());
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

  static AppDB _mergeWithCloud(
    AppDB local,
    Map<String, dynamic> cloud,
  ) {
    // Parse each table individually so one bad table doesn't kill everything
    return AppDB(
      users: _safeParse(cloud['users'], User.fromJson),
      families: _safeParse(cloud['families'], Family.fromJson),
      familyMembers: _safeParse(cloud['family_members'], FamilyMember.fromJson),
      tasks: _safeParse(cloud['tasks'], Task.fromJson),
      events: _safeParse(cloud['events'], CalendarEvent.fromJson),
      recipes: _safeParse(cloud['recipes'], Recipe.fromJson),
      mealPlans: _safeParse(cloud['meal_plans'], MealPlanEntry.fromJson),
      lists: _safeParse(cloud['lists'], ShoppingList.fromJson),
      devotionals: _safeParse(cloud['devotionals'], DevotionalEntry.fromJson),
      fitness: _safeParse(cloud['fitness_metrics'], FitnessMetric.fromJson),
      budgetCategories: _safeParse(cloud['budget_categories'], BudgetCategoryRecord.fromJson),
      transactions: _safeParse(cloud['transactions'], Transaction.fromJson),
      aiHistory: _safeParse(cloud['ai_history'], AIHistory.fromJson),
      dailyHabits: _safeParse(cloud['daily_habits'], DailyHabit.fromJson),
      dailyHabitCompletions: _safeParse(cloud['daily_habit_completions'], DailyHabitCompletion.fromJson),
      chores: _safeParse(cloud['chores'], Chore.fromJson),
      choreCompletions: _safeParse(cloud['chore_completions'], ChoreCompletion.fromJson),
      polls: _safeParse(cloud['polls'], Poll.fromJson),
      pollVotes: _safeParse(cloud['poll_votes'], PollVote.fromJson),
      rewardItems: _safeParse(cloud['reward_items'], RewardItem.fromJson),
      rewardRedemptions: _safeParse(cloud['reward_redemptions'], RewardRedemption.fromJson),
      savingsGoals: _safeParse(cloud['savings_goals'], SavingsGoal.fromJson),
      prayerWall: _safeParse(cloud['prayer_wall'], PrayerWallEntry.fromJson),
      specialDates: _safeParse(cloud['special_dates'], SpecialDate.fromJson),
      familyPhotos: _safeParse(cloud['family_photos'], FamilyPhoto.fromJson),
      milestones: _safeParse(cloud['milestones'], Milestone.fromJson),
      savedPlaces: _safeParse(cloud['saved_places'], SavedPlace.fromJson),
      userLocations: _safeParse(cloud['user_locations'], UserLocation.fromJson),
      messages: _safeParse(cloud['messages'], ChatMessage.fromJson),
      healthRecords: _safeParse(cloud['health_records'], HealthRecord.fromJson),
      periodCycles: _safeParse(cloud['period_cycles'], PeriodCycle.fromJson),
      periodSymptoms: _safeParse(cloud['period_symptoms'], PeriodSymptomLog.fromJson),
      rewards: _safeParse(cloud['rewards'], Reward.fromJson),
      readingPlans: _safeParse(cloud['reading_plans'], ReadingPlan.fromJson),
      externalCalendars: _safeParse(cloud['external_calendars'], ExternalCalendar.fromJson),
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
