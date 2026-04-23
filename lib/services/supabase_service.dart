// lib/services/supabase_service.dart
// Huddle - Supabase integration service

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart' hide User;

class SupabaseService {
  static void _debugCatch(String context, Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('[SupabaseService] $context: $e\n$st');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => Supabase.instance.client.auth;

  static bool get isConfigured {
    try {
      Supabase.instance.client; // throws if not initialized
      return true;
    } on Object {
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

  /// Idempotent server RPC: re-links `users` / `family_members` / `families`
  /// rows from a legacy random profile id to the current Supabase Auth UUID
  /// when the email matches. Without this, RLS sees no membership and the
  /// app offers "create home" even for existing accounts.
  static Future<void> claimOwnedFamilies() async {
    if (!isConfigured) return;
    try {
      await client.rpc('claim_owned_families');
    } on Object catch (e, st) {
      debugPrint('[SupabaseService] claim_owned_families failed: $e\n$st');
    }
  }

  /// Updates `families.subscription_tier` for [familyId] (any family member).
  /// Requires migration `21_family_subscription_tier_sync.sql` on the project.
  static Future<void> syncFamilySubscriptionTier({
    required String familyId,
    required SubscriptionTier tier,
  }) async {
    if (!isConfigured) return;
    try {
      await client.rpc(
        'sync_family_subscription_tier',
        params: {
          'p_family_id': familyId,
          'p_tier': tier.name,
        },
      );
    } on Object catch (e, st) {
      debugPrint('[SupabaseService] sync_family_subscription_tier failed: $e\n$st');
    }
  }

  /// Deletes all Supabase rows for [familyId]. **Home owner only** (enforced server-side).
  /// Requires migration `26_delete_family_cloud_data.sql`.
  static Future<void> deleteFamilyCloudData({required String familyId}) async {
    if (!isConfigured) return;
    await client.rpc(
      'delete_family_cloud_data',
      params: {'p_family_id': familyId},
    );
  }

  /// Normalizes a PostgREST `.select()` result to row maps.
  static List<Map<String, dynamic>> rowsFromSelect(dynamic response) {
    if (response == null) return [];
    if (response is List) {
      return response
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    if (response is Iterable) {
      return response
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return [];
  }

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

  /// Member user ids from [family_members] plus the signed-in user (if any).
  /// Including auth uid avoids empty `users` when `family_members` is temporarily
  /// empty or RLS returns no rows before membership is visible.
  static List<String> _memberUserIdsPlusCurrentAuth(dynamic familyMemberRows) {
    final ids = <String>[];
    final seen = <String>{};
    void add(String? id) {
      if (id == null || id.isEmpty) return;
      if (seen.add(id)) ids.add(id);
    }

    if (familyMemberRows is List) {
      for (final m in familyMemberRows) {
        if (m is Map) add(m['user_id'] as String?);
      }
    }
    add(currentUser?.id);
    return ids;
  }

  /// Fetch all relevant tables for a family from Supabase (full DB sync).
  static Future<Map<String, dynamic>> fetchAllTables(String familyId) async {
    const familyScopedTables = [
      'tasks',
      'events',
      'recipes',
      'meal_plans',
      'lists',
      'devotionals',
      'devotional_thoughts',
      'budget_categories',
      'budget_entries',
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
      'pantry_items',
      'family_activity_logs',
      'wellness_check_ins',
      // Strong integration: family-visible structured workouts
      'workout_sessions',
      'workout_exercises',
      'workout_sets',
      'exercise_prs',
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
      'fitness_logs',
      'ai_history',
      'daily_habits',
      'daily_habit_completions',
      'user_locations',
    ];

    final result = <String, dynamic>{};

    Future<List<dynamic>> fetch(String table, String column, dynamic value) async {
      if (value is List) {
        return await client.from(table).select().inFilter(column, value);
      }
      return await client.from(table).select().eq(column, value);
    }

    Future<List<dynamic>> fetchOrEmpty(String label, Future<List<dynamic>> f) async {
      try {
        return await f;
      } on Object catch (e, st) {
        debugPrint('[SupabaseService] fetch $label failed (using empty): $e\n$st');
        return [];
      }
    }

    // ── Phase 1: fetch family + family_members (never fail the whole pull) ─
    // We need member userIds before we can query user-scoped tables.
    final familiesRows =
        await fetchOrEmpty('families', fetch('families', 'id', familyId));
    final familyMembersRows = await fetchOrEmpty(
      'family_members',
      fetch('family_members', 'family_id', familyId),
    );
    result['families'] = familiesRows;
    result['family_members'] = familyMembersRows;

    final userIds = _memberUserIdsPlusCurrentAuth(familyMembersRows);

    // ── Phase 2: everything else in parallel (per-table errors → empty list) ─
    final allTables = <String>[];
    final allFutures = <Future<List<dynamic>>>[];

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

    for (var i = 0; i < allFutures.length; i++) {
      result[allTables[i]] = await fetchOrEmpty(allTables[i], allFutures[i]);
    }

    return result;
  }

  /// Fetches only [tables] (Supabase relation names, e.g. `meal_plans`).
  ///
  /// Always includes `families` and `family_members` so merges and tombstone
  /// pruning stay consistent with a full pull. Pass an empty set to delegate
  /// to [fetchAllTables].
  static Future<Map<String, dynamic>> fetchTablesForFamily(
    String familyId,
    Set<String> tables,
  ) async {
    if (tables.isEmpty) return fetchAllTables(familyId);

    const familyScopedTables = [
      'tasks',
      'events',
      'recipes',
      'meal_plans',
      'lists',
      'devotionals',
      'devotional_thoughts',
      'budget_categories',
      'budget_entries',
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
      'pantry_items',
      'family_activity_logs',
      'wellness_check_ins',
      'workout_sessions',
      'workout_exercises',
      'workout_sets',
      'exercise_prs',
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
      'fitness_logs',
      'ai_history',
      'daily_habits',
      'daily_habit_completions',
      'user_locations',
    ];

    final want = tables
        .union({
          CloudSyncScope.families,
          CloudSyncScope.familyMembers,
        })
        .toSet();

    final result = <String, dynamic>{};

    Future<List<dynamic>> fetch(String table, String column, dynamic value) async {
      if (value is List) {
        return await client.from(table).select().inFilter(column, value);
      }
      return await client.from(table).select().eq(column, value);
    }

    Future<List<dynamic>> fetchOrEmpty(String label, Future<List<dynamic>> f) async {
      try {
        return await f;
      } on Object catch (e, st) {
        debugPrint('[SupabaseService] fetch $label failed (using empty): $e\n$st');
        return [];
      }
    }

    final familiesRows =
        await fetchOrEmpty('families', fetch('families', 'id', familyId));
    final familyMembersRows = await fetchOrEmpty(
      'family_members',
      fetch('family_members', 'family_id', familyId),
    );
    result['families'] = familiesRows;
    result['family_members'] = familyMembersRows;

    final userIds = _memberUserIdsPlusCurrentAuth(familyMembersRows);

    final allTables = <String>[];
    final allFutures = <Future<List<dynamic>>>[];

    for (final table in familyScopedTables) {
      if (!want.contains(table)) continue;
      allTables.add(table);
      allFutures.add(fetch(table, 'family_id', familyId));
    }
    for (final table in familyIdTables) {
      if (table == 'family_members' || !want.contains(table)) continue;
      allTables.add(table);
      allFutures.add(fetch(table, 'family_id', familyId));
    }

    final userScopedWanted =
        userScopedTables.where(want.contains).toSet();
    if (userIds.isNotEmpty && userScopedWanted.isNotEmpty) {
      allTables.add('users');
      allFutures.add(fetch('users', 'id', userIds));
      for (final table in userScopedWanted) {
        allTables.add(table);
        allFutures.add(fetch(table, 'user_id', userIds));
      }
    }

    for (var i = 0; i < allFutures.length; i++) {
      result[allTables[i]] = await fetchOrEmpty(allTables[i], allFutures[i]);
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
    } on Object catch (e, st) {
      _debugCatch('find_family_by_join_code', e, st);
    }
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
    } on Object catch (e, st) {
      debugPrint('[SupabaseService] photo upload failed: $e\n$st');
      return filePath; // fallback to local path
    }
  }

  /// Remove an object from the `family-photos` bucket when [url] is a Supabase public URL.
  /// No-op for local file paths or when Supabase is not configured. Errors are logged only.
  static Future<void> deleteFamilyPhotoFromStorage(String url) async {
    if (!isConfigured) return;
    if (!url.startsWith('http')) return;
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final idx = segments.indexOf('family-photos');
      if (idx == -1 || idx >= segments.length - 1) return;
      final path = segments.sublist(idx + 1).join('/');
      if (path.isEmpty) return;
      await client.storage.from('family-photos').remove([path]);
    } on Object catch (e, st) {
      _debugCatch('deleteFamilyPhotoFromStorage', e, st);
    }
  }
}
