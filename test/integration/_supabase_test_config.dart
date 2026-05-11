/// Credentials for scripted sync harness tests (optional second Supabase project or branch).
///
/// ```
/// flutter test test/integration/sync_two_device_test.dart \
///   --dart-define=SUPABASE_TEST_URL=https://....supabase.co \
///   --dart-define=SUPABASE_TEST_ANON_KEY=ey... \
///   --dart-define=HUB_TEST_USER_A_EMAIL=... \
///   --dart-define=HUB_TEST_USER_A_PASSWORD=... \
///   --dart-define=HUB_TEST_USER_B_EMAIL=... \
///   --dart-define=HUB_TEST_USER_B_PASSWORD=... \
///   --dart-define=HUB_TEST_FAMILY_ID=<uuid shared by both accounts>
/// ```
abstract final class SupabaseTestConfig {
  static const url = String.fromEnvironment('SUPABASE_TEST_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');
  static const userAEmail = String.fromEnvironment('HUB_TEST_USER_A_EMAIL');
  static const userAPassword = String.fromEnvironment('HUB_TEST_USER_A_PASSWORD');
  static const userBEmail = String.fromEnvironment('HUB_TEST_USER_B_EMAIL');
  static const userBPassword = String.fromEnvironment('HUB_TEST_USER_B_PASSWORD');
  static const familyId = String.fromEnvironment('HUB_TEST_FAMILY_ID');

  static bool get isReady =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      userAEmail.isNotEmpty &&
      userAPassword.isNotEmpty &&
      userBEmail.isNotEmpty &&
      userBPassword.isNotEmpty &&
      familyId.isNotEmpty;
}

