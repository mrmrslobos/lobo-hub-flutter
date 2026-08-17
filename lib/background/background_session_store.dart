import 'package:shared_preferences/shared_preferences.dart';

/// Persists the active user/family so background isolates can load local data
/// without [AppProvider].
class BackgroundSessionStore {
  BackgroundSessionStore._();

  static const _userKey = 'lobohub_bg_active_user_id';
  static const _familyKey = 'lobohub_bg_active_family_id';
  static const _refreshTokenKey = 'lobohub_bg_refresh_token';

  static Future<void> saveActiveSession({
    required String userId,
    required String familyId,
    String? refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, userId);
    await prefs.setString(_familyKey, familyId);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, refreshToken);
    }
  }

  static Future<void> saveRefreshToken(String? refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    if (refreshToken == null || refreshToken.isEmpty) {
      await prefs.remove(_refreshTokenKey);
      return;
    }
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_familyKey);
    await prefs.remove(_refreshTokenKey);
  }

  static Future<({String userId, String familyId})?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userKey);
    final familyId = prefs.getString(_familyKey);
    if (userId == null ||
        userId.isEmpty ||
        familyId == null ||
        familyId.isEmpty) {
      return null;
    }
    return (userId: userId, familyId: familyId);
  }

  static Future<String?> readRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_refreshTokenKey);
    if (token == null || token.isEmpty) return null;
    return token;
  }
}
