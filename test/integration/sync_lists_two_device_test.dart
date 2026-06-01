// Sequential simulation: list header + normalized list_items row sync.
//
// Requires the same Supabase test project credentials as sync_two_device_test.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:lobohub/config/cloud_sync_scope.dart';

import '_supabase_test_config.dart';
import '_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'list item on A is visible after B pulls lists bundle',
    () async {
      await SyncTestHarness.initSupabaseOnce();

      const fid = SupabaseTestConfig.familyId;
      const listTitle = 'integration harness list';
      const itemText = 'integration harness item';

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userAEmail,
        SupabaseTestConfig.userAPassword,
      );

      final created = await SyncTestHarness.deviceACreateListWithItem(
        listTitle,
        itemText,
      );

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userBEmail,
        SupabaseTestConfig.userBPassword,
      );
      await SyncTestHarness.pullFamilyScoped(fid, CloudSyncScope.listsBundle);

      await SyncTestHarness.waitForListItem(
        created.list.id,
        created.item.id,
        fid,
      );

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userAEmail,
        SupabaseTestConfig.userAPassword,
      );
      await SyncTestHarness.pullFamily(fid);

      await SyncTestHarness.deviceARemoveListItem(
        created.list.id,
        created.item.id,
      );

      await SyncTestHarness.tearDownLocals();
      await SyncTestHarness.signIn(
        SupabaseTestConfig.userBEmail,
        SupabaseTestConfig.userBPassword,
      );
      await SyncTestHarness.pullFamilyScoped(fid, CloudSyncScope.listsBundle);

      await SyncTestHarness.waitForListItemGone(
        created.list.id,
        created.item.id,
        fid,
      );

      await SyncTestHarness.tearDownLocals();
    },
    skip: !SupabaseTestConfig.isReady,
  );
}
