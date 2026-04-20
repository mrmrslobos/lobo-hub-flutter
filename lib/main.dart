import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/data_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'services/locale_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initial status bar before MaterialApp; app.dart syncs to theme afterward.
  final platformBright =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: platformBright == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
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

  // Initialize notification service
  await NotificationService.init();

  // Crashlytics after Firebase may have been initialized by notifications (FCM).
  await CrashReportingService.init();

  // Initialize purchase service if keys are provided
  const iosKey = String.fromEnvironment('RC_IOS_KEY', defaultValue: '');
  const androidKey = String.fromEnvironment('RC_ANDROID_KEY', defaultValue: '');
  await PurchaseService.init(iosApiKey: iosKey, androidApiKey: androidKey);

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

  await appProvider.initialize();

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
