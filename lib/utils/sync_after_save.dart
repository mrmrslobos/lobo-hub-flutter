import 'dart:async' show unawaited;

import '../models/models.dart';
import '../providers/app_provider.dart';

/// Persists locally, pushes scoped tables, then nudges other devices via broadcast.
Future<void> saveAndSyncWithImmediatePush(
  AppProvider provider,
  AppDB newDb, {
  required Set<String> pushTableScope,
}) async {
  await provider.saveAndSync(newDb, pushTableScope: pushTableScope);
  if (provider.activeFamily != null) {
    unawaited(provider.syncTablesNow(pushTableScope));
  }
}
