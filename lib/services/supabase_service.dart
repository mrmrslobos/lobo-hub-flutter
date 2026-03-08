// lib/services/supabase_service.dart
// FamilyHub - Supabase integration service

// ignore_for_file: avoid_catches_without_on_clauses

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
      'families',
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
      'fitness_metrics',
      'fitness_plans',
      'ai_history',
      'daily_habits',
      'daily_habit_completions',
      'user_locations',
    ];

    final result = <String, dynamic>{};

    // Family-scoped tables
    for (final table in familyScopedTables) {
      try {
        result[table] = await client
            .from(table)
            .select()
            .eq('familyId', familyId);
      } catch (_) {
        result[table] = [];
      }
    }

    // Tables that use family_id but may be named differently
    for (final table in familyIdTables) {
      try {
        result[table] = await client
            .from(table)
            .select()
            .eq('familyId', familyId);
      } catch (_) {
        result[table] = [];
      }
    }

    // User-scoped tables: fetch members first then query by user_id
    try {
      final members = await client
          .from('family_members')
          .select('userId')
          .eq('familyId', familyId);

      final userIds = (members as List)
          .map((m) => m['userId'] as String)
          .toList();

      if (userIds.isNotEmpty) {
        // Fetch users
        try {
          result['users'] = await client
              .from('users')
              .select()
              .inFilter('id', userIds);
        } catch (_) {
          result['users'] = [];
        }

        // Fetch user-scoped tables
        for (final table in userScopedTables) {
          try {
            result[table] = await client
                .from(table)
                .select()
                .inFilter('userId', userIds);
          } catch (_) {
            result[table] = [];
          }
        }
      } else {
        result['users'] = [];
        for (final table in userScopedTables) {
          result[table] = [];
        }
      }
    } catch (_) {
      result['users'] = [];
      for (final table in userScopedTables) {
        result[table] = [];
      }
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
}
