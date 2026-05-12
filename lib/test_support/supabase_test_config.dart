/// Compile-time credentials for Supabase-backed integration tests.
///
/// Pass via `--dart-define=SUPABASE_TEST_URL=…` and
/// `--dart-define=SUPABASE_TEST_ANON_KEY=…`.
abstract final class SupabaseTestConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_TEST_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');

  /// Pre-provisioned accounts that share no production data (see harness README).
  static const userAEmail = String.fromEnvironment('HUB_TEST_USER_A_EMAIL');
  static const userAPassword = String.fromEnvironment('HUB_TEST_USER_A_PASSWORD');
  static const userBEmail = String.fromEnvironment('HUB_TEST_USER_B_EMAIL');
  static const userBPassword = String.fromEnvironment('HUB_TEST_USER_B_PASSWORD');

  /// Throws with runnable instructions when URL/key missing from dart-define.
  static void ensureSupabaseDartDefines() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Integration tests require a dedicated Supabase test project.\n'
        'Missing SUPABASE_TEST_URL and/or SUPABASE_TEST_ANON_KEY.\n'
        'Example:\n'
        '  flutter test test/integration/sync_two_device_test.dart \\\n'
        '    --dart-define=SUPABASE_TEST_URL=https://YOUR_PROJECT.supabase.co \\\n'
        '    --dart-define=SUPABASE_TEST_ANON_KEY=eyJhbGc...\n',
      );
    }
  }

  static bool get hasIntegrationAccounts =>
      userAEmail.isNotEmpty &&
      userAPassword.isNotEmpty &&
      userBEmail.isNotEmpty &&
      userBPassword.isNotEmpty;
}
