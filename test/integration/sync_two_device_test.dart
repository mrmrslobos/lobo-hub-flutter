// Sequential simulation of two family members (same process, shared static DB).
//
// Provision in the test Supabase project:
// - Two authenticated users who are members of the same family.
// - HUB_TEST_FAMILY_ID = that family's UUID.

import 'package:flutter_test/flutter_test.dart';

import '_supabase_test_config.dart';
import '_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'soft-delete on A is visible after B reconciles',
    () async {
      await SyncTestHarness.initSupabaseOnce();

      const fid = SupabaseTestConfig.familyId;

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userAEmail,
        SupabaseTestConfig.userAPassword,
      );

      final task = await SyncTestHarness.deviceACreateTask('integration harness task');

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userBEmail,
        SupabaseTestConfig.userBPassword,
      );
      await SyncTestHarness.pullFamily(fid);

      await SyncTestHarness.waitForTask(task.id, fid);

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userAEmail,
        SupabaseTestConfig.userAPassword,
      );
      await SyncTestHarness.pullFamily(fid);

      await SyncTestHarness.deviceASoftDeleteTask(task.id);

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userBEmail,
        SupabaseTestConfig.userBPassword,
      );
      await SyncTestHarness.pullFamily(fid);

      await SyncTestHarness.waitForTaskGone(task.id, fid);

      await SyncTestHarness.tearDownLocals();
    },
    skip: !SupabaseTestConfig.isReady,
  );
}
