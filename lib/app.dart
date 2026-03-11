// lib/app.dart
// App entry point with go_router navigation and MaterialApp.router setup

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'config/theme.dart';
import 'config/app_config.dart';
import 'providers/app_provider.dart';
import 'widgets/biometric_lock.dart';

// Screens
import 'screens/auth/auth_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/tasks/tasks_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/calendar/calendar_screen.dart';
import 'screens/meals/meals_screen.dart';
import 'screens/budget/budget_screen.dart';
import 'screens/lists/lists_screen.dart';
import 'screens/chores/chores_screen.dart';
import 'screens/rewards/rewards_screen.dart';
import 'screens/fitness/fitness_screen.dart';
import 'screens/devotional/devotional_screen.dart';
import 'screens/prayer_wall/prayer_wall_screen.dart';
import 'screens/polls/polls_screen.dart';
import 'screens/period_tracker/period_tracker_screen.dart';
import 'screens/birthdays/birthdays_screen.dart';
import 'screens/photos/photos_screen.dart';
import 'screens/location/location_screen.dart';
import 'screens/health/health_screen.dart';
import 'screens/ai_history/ai_history_screen.dart';
import 'screens/habits/habits_screen.dart';

class FamilyHubApp extends StatefulWidget {
  const FamilyHubApp({super.key});

  @override
  State<FamilyHubApp> createState() => _FamilyHubAppState();
}

class _FamilyHubAppState extends State<FamilyHubApp> {
  late final GoRouter _router;
  late final AppProvider _provider;
  StreamSubscription<AuthState>? _authSub;

  bool _isRouterInitialized = false;
  bool _isPasswordRecovery = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only initialize once
    if (!_isRouterInitialized) {
      _provider = context.read<AppProvider>();
      _router = _buildRouter(_provider);
      _isRouterInitialized = true;
      _listenToAuthState();
    }
  }

  void _listenToAuthState() {
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          _isPasswordRecovery = true;
          _router.go('/auth?resetPassword=true');
        } else if (data.event == AuthChangeEvent.signedIn) {
          _isPasswordRecovery = false;
          // OAuth callback or token refresh — re-resolve user/family from
          // the new session so isAuthenticated becomes true, then the
          // router's refreshListenable triggers redirect re-evaluation.
          _provider.initialize();
        } else if (data.event == AuthChangeEvent.signedOut) {
          _isPasswordRecovery = false;
        }
      });
    } catch (_) {
      // Supabase not configured — skip
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  GoRouter _buildRouter(AppProvider provider) {
    return GoRouter(
      initialLocation: '/',
      debugLogDiagnostics: false,
      redirect: (context, state) {
        // Still loading initial data — don't redirect yet
        if (provider.isInitializing) return null;

        final isAuthenticated = provider.isAuthenticated;
        final isOnAuth = state.matchedLocation == '/auth';

        // Routes always accessible without module gating
        final alwaysAccessible = {
          '/auth',
          '/',
          '/ai-history',
          '/habits',
        };

        if (!isAuthenticated && !isOnAuth) return '/auth';
        // Don't redirect away from auth during password recovery
        final isResetFlow =
            _isPasswordRecovery &&
            state.uri.queryParameters['resetPassword'] == 'true';
        if (isAuthenticated && isOnAuth && !isResetFlow) {
          _isPasswordRecovery = false;
          return '/';
        }

        return null;
      },
      refreshListenable: _RouterRefreshStream(provider),
      routes: [
        GoRoute(
          path: '/auth',
          name: 'auth',
          builder: (context, state) {
            final resetPassword =
                state.uri.queryParameters['resetPassword'] == 'true';
            return AuthScreen(
              key: ValueKey(resetPassword),
              showResetPassword: resetPassword,
            );
          },
        ),
        GoRoute(
          path: '/',
          name: 'dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/tasks',
          name: 'tasks',
          builder: (context, state) => const TasksScreen(),
        ),
        GoRoute(
          path: '/chat',
          name: 'chat',
          builder: (context, state) => const ChatScreen(),
        ),
        GoRoute(
          path: '/calendar',
          name: 'calendar',
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/meals',
          name: 'meals',
          builder: (context, state) => const MealsScreen(),
        ),
        GoRoute(
          path: '/budget',
          name: 'budget',
          builder: (context, state) => const BudgetScreen(),
        ),
        GoRoute(
          path: '/lists',
          name: 'lists',
          builder: (context, state) => const ListsScreen(),
        ),
        GoRoute(
          path: '/chores',
          name: 'chores',
          builder: (context, state) => const ChoresScreen(),
        ),
        GoRoute(
          path: '/rewards',
          name: 'rewards',
          builder: (context, state) => const RewardsScreen(),
        ),
        GoRoute(
          path: '/fitness',
          name: 'fitness',
          builder: (context, state) => const FitnessScreen(),
        ),
        GoRoute(
          path: '/devotional',
          name: 'devotional',
          builder: (context, state) => const DevotionalScreen(),
        ),
        GoRoute(
          path: '/prayer-wall',
          name: 'prayer-wall',
          builder: (context, state) => const PrayerWallScreen(),
        ),
        GoRoute(
          path: '/polls',
          name: 'polls',
          builder: (context, state) => const PollsScreen(),
        ),
        GoRoute(
          path: '/period-tracker',
          name: 'period-tracker',
          builder: (context, state) => const PeriodTrackerScreen(),
        ),
        GoRoute(
          path: '/birthdays',
          name: 'birthdays',
          builder: (context, state) => const BirthdaysScreen(),
        ),
        GoRoute(
          path: '/photos',
          name: 'photos',
          builder: (context, state) => const PhotosScreen(),
        ),
        GoRoute(
          path: '/location',
          name: 'location',
          builder: (context, state) => const LocationScreen(),
        ),
        GoRoute(
          path: '/health',
          name: 'health',
          builder: (context, state) => const HealthScreen(),
        ),
        GoRoute(
          path: '/ai-history',
          name: 'ai-history',
          builder: (context, state) => const AIHistoryScreen(),
        ),
        GoRoute(
          path: '/habits',
          name: 'habits',
          builder: (context, state) => const HabitsScreen(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Page Not Found')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppTheme.stone400),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                state.matchedLocation,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRouterInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return BiometricLockScreen(
      child: MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        routerConfig: _router,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Helper: makes GoRouter re-evaluate redirect when AppProvider changes
// ─────────────────────────────────────────────

class _RouterRefreshStream extends ChangeNotifier {
  final AppProvider _provider;

  _RouterRefreshStream(this._provider) {
    _provider.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _provider.removeListener(notifyListeners);
    super.dispose();
  }
}
