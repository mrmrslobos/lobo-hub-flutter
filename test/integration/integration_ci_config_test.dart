// Fails CI when GitHub Actions runs integration workflow but dart-defines
// were not supplied (empty secrets → tests would silently skip).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_supabase_test_config.dart';

bool get _runsOnGithubActions =>
    Platform.environment['GITHUB_ACTIONS'] == 'true';

void main() {
  test('Supabase sync harness dart-defines are set in CI', () {
    if (!_runsOnGithubActions) {
      return;
    }
    expect(
      SupabaseTestConfig.isReady,
      isTrue,
      reason:
          'This repo integration workflow expects GitHub Secrets: SUPABASE_TEST_URL, '
          'SUPABASE_TEST_ANON_KEY, HUB_TEST_USER_A_EMAIL, HUB_TEST_USER_A_PASSWORD, '
          'HUB_TEST_USER_B_EMAIL, HUB_TEST_USER_B_PASSWORD, HUB_TEST_FAMILY_ID. '
          'See README.md § Integration sync tests.',
    );
  });
}
