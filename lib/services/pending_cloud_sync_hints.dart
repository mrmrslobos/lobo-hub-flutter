import 'package:shared_preferences/shared_preferences.dart';

/// Cross-session hints written from the FCM background isolate when a full Dart
/// [DatabaseService.reconcileCloud] is intentionally avoided (no Supabase session
/// / encryption stack there). Consumed on next foreground startup.
class PendingCloudSyncHints {
  PendingCloudSyncHints._();

  static const _devotionalPrefetch = 'lobohub_hint_devotional_prefetch_v1';

  static Future<void> recordDevotionalPrefetchHint() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_devotionalPrefetch, true);
    } catch (_) {}
  }

  /// Returns true once (clears flag). Safe to call from main isolate only.
  static Future<bool> consumeDevotionalPrefetchHint() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!(p.getBool(_devotionalPrefetch) ?? false)) return false;
      await p.setBool(_devotionalPrefetch, false);
      return true;
    } on Object {
      return false;
    }
  }
}
