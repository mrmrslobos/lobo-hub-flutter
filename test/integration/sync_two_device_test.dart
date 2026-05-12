import 'package:flutter_test/flutter_test.dart';

import 'package:lobohub/test_support/supabase_test_config.dart';

import '_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'soft-delete propagates from A to B within 5s',
    (tester) async {
      final harness = await SyncTestHarness.create();
      try {
        final deviceA = await harness.spawnDevice(asUser: SyncTestUser.a);
        final deviceB = await harness.spawnDevice(asUser: SyncTestUser.b);

        final task = await deviceA.createTask('soft-delete propagation harness');
        await deviceB.waitForTask(task.id);

        await deviceA.deleteTask(task.id);
        await deviceB.waitForTaskGone(task.id, timeout: const Duration(seconds: 5));

        await tester.pump();
      } finally {
        await harness.tearDown();
      }
    },
    skip:
        SupabaseTestConfig.supabaseUrl.isEmpty ||
            SupabaseTestConfig.supabaseAnonKey.isEmpty ||
            !SupabaseTestConfig.hasIntegrationAccounts,
  );
}
