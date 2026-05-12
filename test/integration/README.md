# Integration sync tests

These tests hit a **dedicated Supabase test project** (never production). They spawn **two VM isolates**, each with its own Sembast file, so static services behave like two devices.

## Required dart-defines

| Define | Purpose |
|--------|---------|
| `SUPABASE_TEST_URL` | Test project URL (`https://….supabase.co`) |
| `SUPABASE_TEST_ANON_KEY` | Test project anon key |
| `HUB_TEST_USER_A_EMAIL` / `HUB_TEST_USER_A_PASSWORD` | First provisioned account |
| `HUB_TEST_USER_B_EMAIL` / `HUB_TEST_USER_B_PASSWORD` | Second provisioned account |

`SyncTestHarness.create()` inserts a fresh `families` row plus `family_members` for both users and deletes it in `tearDown()` via `delete_family_cloud_data`.

## Run locally

```bash
flutter test test/integration/sync_two_device_test.dart \
  --dart-define=SUPABASE_TEST_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_TEST_ANON_KEY=eyJhbGc... \
  --dart-define=HUB_TEST_USER_A_EMAIL=user-a@example.test \
  --dart-define=HUB_TEST_USER_A_PASSWORD='your-secret' \
  --dart-define=HUB_TEST_USER_B_EMAIL=user-b@example.test \
  --dart-define=HUB_TEST_USER_B_PASSWORD='your-secret'
```

If URL/key or user defines are missing, the soft-delete test is **skipped**.

For historical reasons some Flutter docs refer to an `integration_test/` directory; this repo’s harness lives under **`test/integration/`** and is run with `flutter test` as above.
