// lib/services/supabase_service.dart
// FamilyHub - Supabase integration service

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => Supabase.instance.client.auth;

  static bool get isConfigured {
    try {
      Supabase.instance.client; // throws if not initialized
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return auth.signInWithPassword(email: email, password: password);
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return auth.signUp(email: email, password: password);
  }

  static Future<bool> signInWithOAuth(
    OAuthProvider provider, {
    String? redirectTo,
  }) {
    return auth.signInWithOAuth(provider, redirectTo: redirectTo);
  }

  static Future<void> signOut() => auth.signOut();

  static Session? get currentSession => auth.currentSession;

  static User? get currentUser => auth.currentUser;

  static Future<void> resetPasswordForEmail(
    String email, {
    String? redirectTo,
  }) {
    return auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  static Future<AuthSessionUrlResponse> exchangeCodeForSession(
    String authCallbackUrl,
  ) {
    return auth.exchangeCodeForSession(authCallbackUrl);
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  /// Fetch all relevant tables for a family from Supabase (full DB sync).
  static Future<Map<String, dynamic>> fetchAllTables(String familyId) async {
    const familyScopedTables = [
      'tasks',
      'events',
      'recipes',
      'meal_plans',
      'lists',
      'devotionals',
      'budget_categories',
      'transactions',
      'chores',
      'polls',
      'reward_items',
      'savings_goals',
      'prayer_wall',
      'special_dates',
      'family_photos',
      'milestones',
      'saved_places',
      'messages',
      'health_records',
      'external_calendars',
      'rewards',
      'reading_plans',
    ];

    const familyIdTables = [
      'family_members',
      'chore_completions',
      'poll_votes',
      'reward_redemptions',
      'period_cycles',
      'period_symptoms',
    ];

    const userScopedTables = [
      'fitness',
      'fitness_plans',
      'ai_history',
      'daily_habits',
      'daily_habit_completions',
      'user_locations',
    ];

    final result = <String, dynamic>{};

    /// Safely fetch a single table, returning [] on error.
    Future<List> fetch(String table, String column, dynamic value) async {
      try {
        if (value is List) {
          return await client.from(table).select().inFilter(column, value);
        }
        return await client.from(table).select().eq(column, value);
      } catch (_) {
        return [];
      }
    }

    // ── Phase 1: fetch family + family_members in parallel ───────────────
    // We need member userIds before we can query user-scoped tables.
    final phase1 = await Future.wait([
      fetch('families', 'id', familyId),
      fetch('family_members', 'family_id', familyId),
    ]);
    result['families'] = phase1[0];
    result['family_members'] = phase1[1];

    final userIds = (phase1[1] as List)
        .map((m) => (m as Map)['user_id'] as String)
        .toList();

    // ── Phase 2: everything else in parallel ─────────────────────────────
    final allTables = <String>[];
    final allFutures = <Future<List>>[];

    for (final table in familyScopedTables) {
      allTables.add(table);
      allFutures.add(fetch(table, 'family_id', familyId));
    }
    // family_members already fetched in phase 1, skip it
    for (final table in familyIdTables) {
      if (table == 'family_members') continue;
      allTables.add(table);
      allFutures.add(fetch(table, 'family_id', familyId));
    }
    if (userIds.isNotEmpty) {
      allTables.add('users');
      allFutures.add(fetch('users', 'id', userIds));
      for (final table in userScopedTables) {
        allTables.add(table);
        allFutures.add(fetch(table, 'user_id', userIds));
      }
    } else {
      result['users'] = [];
      for (final table in userScopedTables) {
        result[table] = [];
      }
    }

    final phase2 = await Future.wait(allFutures);
    for (var i = 0; i < allTables.length; i++) {
      result[allTables[i]] = phase2[i];
    }

    return result;
  }

  /// Upsert rows into a table, using the given conflict column(s).
  static Future<void> upsertTable(
    String table,
    List<Map<String, dynamic>> rows, {
    String onConflict = 'id',
  }) async {
    if (rows.isEmpty) return;
    await client.from(table).upsert(rows, onConflict: onConflict);
  }

  /// Call a Supabase RPC function.
  static Future<dynamic> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) {
    return client.rpc(function, params: params);
  }

  /// Find a family by its join code via RPC.
  static Future<Map<String, dynamic>?> findFamilyByJoinCode(
    String code,
  ) async {
    try {
      final result = await client.rpc(
        'find_family_by_join_code',
        params: {'code': code},
      );
      if (result != null && (result as List).isNotEmpty) {
        return result[0] as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Subscribe to realtime broadcast events for a family channel.
  static RealtimeChannel subscribeToFamily(
    String familyId, {
    required void Function(Map<String, dynamic>) onBroadcast,
  }) {
    return client
        .channel('family:$familyId')
        .onBroadcast(
          event: 'db_change',
          callback: (payload) => onBroadcast(payload),
        )
        .subscribe();
  }

  /// Unsubscribe and remove a realtime channel.
  static Future<void> unsubscribe(RealtimeChannel channel) async {
    await client.removeChannel(channel);
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  /// Delete rows from a table matching the given filters.
  static Future<void> deleteRows(
    String table,
    Map<String, String> filters,
  ) async {
    var query = client.from(table).delete();
    for (final entry in filters.entries) {
      query = query.eq(entry.key, entry.value);
    }
    await query;
  }

  // ── Storage ─────────────────────────────────────────────────────────────

  /// Upload a photo file to Supabase Storage and return the public URL.
  /// Falls back to the local file path if upload fails.
  static Future<String> uploadPhoto({
    required String familyId,
    required String photoId,
    required String filePath,
  }) async {
    try {
      final ext = filePath.split('.').last;
      final storagePath = '$familyId/$photoId.$ext';
      final file = File(filePath);

      await client.storage
          .from('family-photos')
          .upload(storagePath, file, fileOptions: const FileOptions(upsert: true));

      return client.storage.from('family-photos').getPublicUrl(storagePath);
    } catch (e) {
      debugPrint('[SupabaseService] photo upload failed: $e');
      return filePath; // fallback to local path
    }
  }
}
