import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'services/pending_cloud_sync_hints.dart';

/// Must be registered with [FirebaseMessaging.onBackgroundMessage] before
/// [WidgetsFlutterBinding.ensureInitialized]; runs in its own isolate.
///
/// **Decision (terminated-state prefetch):** We do not run a full cloud reconcile
/// in this isolate (no app session, encryption, or merge context). Instead we
/// record a hint for the next foreground session; see pending_cloud_sync_hints.dart
/// and SyncProvider startup / onAppResumed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  try {
    final data = message.data;
    final path = '${data['path'] ?? data['route'] ?? ''}';
    final did = data['devotionalId']?.toString();
    final looksDevotional =
        (did != null && did.isNotEmpty) || path.contains('devotional');
    if (looksDevotional) {
      await PendingCloudSyncHints.recordDevotionalPrefetchHint();
    }
  } catch (_) {}
}
