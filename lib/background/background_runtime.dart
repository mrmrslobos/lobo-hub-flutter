import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../services/supabase_service.dart';

/// Minimal environment setup for Workmanager / FCM background isolates.
class BackgroundRuntime {
  BackgroundRuntime._();

  static bool _ready = false;

  static Future<void> ensureReady() async {
    if (_ready) return;
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.bootstrapTimeZone();

    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      try {
        if (!SupabaseService.isConfigured) {
          await Supabase.initialize(
            url: supabaseUrl,
            anonKey: supabaseAnonKey,
            authOptions: const FlutterAuthClientOptions(
              authFlowType: AuthFlowType.pkce,
            ),
          );
        }
      } catch (e) {
        debugPrint('[BackgroundRuntime] Supabase init: $e');
      }
    }

    _ready = true;
  }
}
