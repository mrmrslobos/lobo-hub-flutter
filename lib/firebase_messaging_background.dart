import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Must be registered with [FirebaseMessaging.onBackgroundMessage] before
/// [WidgetsFlutterBinding.ensureInitialized]; runs in its own isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Data sync / bookkeeping can be added later; taps use [getInitialMessage] / streams.
}
