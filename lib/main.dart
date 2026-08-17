import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/build_flags.dart';
import 'app.dart';
import 'firebase_messaging_background.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/data_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'services/locale_service.dart';
import 'services/crash_reporting_service.dart';
import 'background/background_task_scheduler.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';

/// Replace Flutter’s default red error panels in release/profile with a calm fallback (Phase E).
void _configureProductionErrorPresentation() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return const Material(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.widgets_outlined, size: 44, color: Color(0xFF94A3B8)),
                SizedBox(height: 14),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Try going back or reopening this screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.bootstrapTimeZone();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  _configureProductionErrorPresentation();

  // Photoframe wall builds: landscape + immersive chrome (see AGENTS.md / build.gradle).
  if (BuildFlags.photoframe) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    if (!kIsWeb && Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Initial status bar before MaterialApp; app.dart syncs to theme afterward.
  final platformBright =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: platformBright == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarIconBrightness: platformBright == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));

  // Initialize Supabase if env vars are set
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  final dataProvider = DataProvider();
  final themeProvider = ThemeProvider();
  final authProvider = AuthProvider(dataProvider);
  final syncProvider = SyncProvider(
    authProvider: authProvider,
    dataProvider: dataProvider,
  );
  final appProvider = AppProvider(
    dataProvider: dataProvider,
    authProvider: authProvider,
    syncProvider: syncProvider,
    themeProvider: themeProvider,
  );

  const iosKey = String.fromEnvironment('RC_IOS_KEY', defaultValue: '');
  const androidKey = String.fromEnvironment('RC_ANDROID_KEY', defaultValue: '');

  // Notifications / Firebase / IAP must not block the first frame (cold start UX).
  void startDeferredBootstrap() {
    unawaited(BackgroundTaskScheduler.initialize());
    unawaited(NotificationService.ensureReady());
    unawaited(CrashReportingService.init());
    unawaited(PurchaseService.init(iosApiKey: iosKey, androidApiKey: androidKey));
    unawaited(
      appProvider.initialize().then((_) async {
        if (appProvider.isAuthenticated) {
          await appProvider.prepareDailyDevotionalAndSchedule();
        }
      }),
    );
  }

  scheduleMicrotask(startDeferredBootstrap);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DataProvider>.value(value: dataProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<SyncProvider>.value(value: syncProvider),
        ChangeNotifierProvider<AppProvider>.value(value: appProvider),
        ChangeNotifierProvider(create: (_) => LocaleService()..init()),
      ],
      child: const HuddleApp(),
    ),
  );
}
