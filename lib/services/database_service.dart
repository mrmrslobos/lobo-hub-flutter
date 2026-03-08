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

  static Future<void> _syncToCloud(AppDB db, String familyId) async {
    Future<void> up(String table, List<Map<String, dynamic>> rows) async {
      if (rows.isNotEmpty) {
        await SupabaseService.upsertTable(table, rows);
      }
    }

    final fid = familyId;

    await up('tasks',
        db.tasks.map((t) => {...t.toJson(), 'family_id': fid}).toList());
    await up('events',
        db.events.map((e) => {...e.toJson(), 'family_id': fid}).toList());
    await up('recipes',
        db.recipes.map((r) => {...r.toJson(), 'family_id': fid}).toList());
    await up('meal_plans',
        db.mealPlans.map((m) => {...m.toJson(), 'family_id': fid}).toList());
    await up('lists',
        db.lists.map((l) => {...l.toJson(), 'family_id': fid}).toList());
    await up('devotionals',
        db.devotionals.map((d) => {...d.toJson(), 'family_id': fid}).toList());
    await up('fitness_metrics',
        db.fitness.map((f) => f.toJson()).toList());
    await up('budget_categories',
        db.budgetCategories.map((b) => {...b.toJson(), 'family_id': fid}).toList());
    await up('transactions',
        db.transactions.map((t) => {...t.toJson(), 'family_id': fid}).toList());
    await up('ai_history',
        db.aiHistory.map((a) => a.toJson()).toList());
    await up('daily_habits',
        db.dailyHabits.map((h) => h.toJson()).toList());
    await up('daily_habit_completions',
        db.dailyHabitCompletions.map((c) => c.toJson()).toList());
    await up('chores',
        db.chores.map((c) => {...c.toJson(), 'family_id': fid}).toList());
    await up('chore_completions',
        db.choreCompletions.map((c) => c.toJson()).toList());
    await up('polls',
        db.polls.map((p) => {...p.toJson(), 'family_id': fid}).toList());
    await up('poll_votes',
        db.pollVotes.map((v) => v.toJson()).toList());
    await up('reward_items',
        db.rewardItems.map((r) => {...r.toJson(), 'family_id': fid}).toList());
    await up('reward_redemptions',
        db.rewardRedemptions.map((r) => r.toJson()).toList());
    await up('savings_goals',
        db.savingsGoals.map((g) => {...g.toJson(), 'family_id': fid}).toList());
    await up('prayer_wall',
        db.prayerWall.map((p) => {...p.toJson(), 'family_id': fid}).toList());
    await up('special_dates',
        db.specialDates.map((s) => {...s.toJson(), 'family_id': fid}).toList());
    await up('family_photos',
        db.familyPhotos.map((p) => {...p.toJson(), 'family_id': fid}).toList());
    await up('milestones',
        db.milestones.map((m) => {...m.toJson(), 'family_id': fid}).toList());
    await up('saved_places',
        db.savedPlaces.map((s) => {...s.toJson(), 'family_id': fid}).toList());
    await up('user_locations',
        db.userLocations.map((u) => u.toJson()).toList());
    await up('messages',
        db.messages.map((m) => {...m.toJson(), 'family_id': fid}).toList());
    await up('health_records',
        db.healthRecords.map((h) => {...h.toJson(), 'family_id': fid}).toList());
    await up('period_cycles',
        db.periodCycles.map((c) => c.toJson()).toList());
    await up('period_symptoms',
        db.periodSymptoms.map((s) => s.toJson()).toList());
    await up('external_calendars',
        db.externalCalendars.map((c) => {...c.toJson(), 'family_id': fid}).toList());
  }

  // ── Cloud reconcile ───────────────────────────────────────────────────────

  /// Fetch cloud data and merge it with the local DB.
  static Future<AppDB> reconcileCloud(AppDB local, String familyId) async {
    if (!SupabaseService.isConfigured) return local;
    try {
      final cloudData = await SupabaseService.fetchAllTables(familyId);
      return _mergeWithCloud(local, cloudData);
    } catch (_) {
      return local;
    }
  }

  static AppDB _mergeWithCloud(
    AppDB local,
    Map<String, dynamic> cloud,
  ) {
    try {
      // Cloud data takes precedence; any local-only items not yet on cloud
      // are presumed to be handled on next sync.
      return AppDB.fromCloudJson(cloud);
    } catch (_) {
      return local;
    }
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
