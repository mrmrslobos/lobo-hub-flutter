// Firebase Crashlytics — mobile only; no-op on web and if Firebase init failed.

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashReportingService {
  static bool _didInit = false;

  static Future<void> init() async {
    if (_didInit) return;
    _didInit = true;
    if (kIsWeb) return;

    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('[CrashReportingService] init skipped: $e');
    }
  }
}
