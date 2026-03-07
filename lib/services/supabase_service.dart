import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase client with helpers used throughout the app.
class SupabaseService {
  /// Whether Supabase has been initialized with real credentials.
  static bool get isConfigured {
    try {
      return Supabase.instance.client.supabaseUrl.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get auth => _client.auth;

  // ─── Auth ──────────────────────────────────────────────────────────────────

  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) =>
      auth.signInWithPassword(email: email, password: password);

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) =>
      auth.signUp(email: email, password: password);

  static Future<bool> signInWithOAuth(
    OAuthProvider provider, {
    String? redirectTo,
  }) =>
      auth.signInWithOAuth(provider, redirectTo: redirectTo);

  static Future<void> signOut() => auth.signOut();

  static Session? get currentSession => auth.currentSession;
  static User? get currentUser => auth.currentUser;

  static Future<void> resetPasswordForEmail(String email,
          {String? redirectTo}) =>
      auth.resetPasswordForEmail(email, redirectTo: redirectTo);

  static Future<AuthSessionUrlResponse> exchangeCodeForSession(
          String authCallbackUrl) =>
      auth.exchangeCodeForSession(authCallbackUrl);

  // ─── Database ──────────────────────────────────────────────────────────────

  /// Upsert rows into a Supabase table.
  static Future<void> upsertTable(
      String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      await _client.from(table).upsert(rows, onConflict: 'id');
    } catch (e) {
      debugPrint('[Supabase] upsert $table failed: $e');
    }
  }

  /// Find a family by join code via RPC.
  static Future<Map<String, dynamic>?> findFamilyByJoinCode(
      String code) async {
    try {
      final result = await _client
          .rpc('find_family_by_join_code', params: {'code': code});
      if (result != null && (result as List).isNotEmpty) {
        return (result[0] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[Supabase] findFamilyByJoinCode failed: $e');
    }
    return null;
  }

  /// Subscribe to realtime family channel.
  static RealtimeChannel subscribeFamilyChannel(
    String familyId, {
    required void Function(Map<String, dynamic>) onBroadcast,
  }) {
    return _client
        .channel('family:$familyId')
        .onBroadcast(
          event: 'db_change',
          callback: (payload) => onBroadcast(payload),
        )
        .subscribe();
  }

  /// Unsubscribe from a channel.
  static Future<void> unsubscribeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  // ─── RPC ───────────────────────────────────────────────────────────────────

  static Future<void> claimOwnedFamilies() async {
    try {
      await _client.rpc('claim_owned_families');
    } catch (e) {
      debugPrint('[Supabase] claimOwnedFamilies failed (non-fatal): $e');
    }
  }
}
