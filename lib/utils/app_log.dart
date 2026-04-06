import 'package:flutter/foundation.dart';

/// Tagged logging wrappers (primarily for sync and diagnostics).
class AppLog {
  AppLog._();

  static void sync(String message) => debugPrint('[Sync] $message');

  static void w(String tag, String message) => debugPrint('[$tag] $message');
}
