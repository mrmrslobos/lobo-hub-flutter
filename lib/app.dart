// lib/app.dart
// App entry point with go_router navigation and MaterialApp.router setup

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'config/build_flags.dart';
import 'config/huddle_motion.dart';
import 'config/theme.dart';
import 'config/app_config.dart';
import 'providers/app_provider.dart';
import 'widgets/route_recency.dart';
import 'services/notification_service.dart';
import 'services/daily_devotional_service.dart';
import 'widgets/biometric_lock.dart';
import 'widgets/offline_banner.dart';

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
import 'screens/subscription/subscription_screen.dart';
import 'screens/assistant/assistant_screen.dart';
import 'screens/photoframe/photoframe_screen.dart';

/// Cross-fade plus slight vertical drift when switching top-level / shell routes (Phase G).
Page<void> _huddlePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: HuddleMotion.routeForward,
    reverseTransitionDuration: HuddleMotion.routeReverse,
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: HuddleMotion.routeCurve,
        reverseCurve: HuddleMotion.routeReverseCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: HuddleMotion.routeSlideBegin,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class HuddleApp extends StatefulWidget {
  const HuddleApp({super.key});

  @override
  State<HuddleApp> createState() => _HuddleAppState();
}

class _HuddleAppState extends State<HuddleApp> with WidgetsBindingObserver {
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
      _provider.authProvider.onSessionReady = _consumePendingRoute;
      NotificationService.onRoutePending = _consumePendingRoute;
      _isRouterInitialized = true;
      _listenToAuthState();
      WidgetsBinding.instance.addObserver(this);
      // Handle notification tap that launched the app from terminated state
      _consumePendingRoute();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_provider.isAuthenticated) {
        _provider.onAppResumed();
        unawaited(_provider.refreshStoreSubscription());
      }
      _consumePendingRoute();
    }
  }

  /// Navigate to the route set by a notification tap (FCM or local).
  void _consumePendingRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.ensureReady();
      final pending = NotificationService.pendingRoute;
      if (pending == null || pending.isEmpty) return;
      if (!_provider.isAuthenticated) return;

      var route = pending;
      NotificationService.pendingRoute = null;
      try {
        if (route.startsWith('/devotional')) {
          await _provider.prepareDailyDevotionalAndSchedule();
          route = _resolveDevotionalRoute(route);
        } else {
          await _provider.refreshFromCloud();
        }
      } catch (e) {
        debugPrint('[HuddleApp] pending route prep failed: $e');
      }
      if (!mounted) return;
      _router.go(route);
    });
  }

  String _resolveDevotionalRoute(String route) {
    final uri = Uri.parse(route.startsWith('/') ? route : '/$route');
    final existingId =
        uri.queryParameters['id'] ?? uri.queryParameters['devotionalId'];
    if (existingId != null && existingId.isNotEmpty) {
      return '/devotional?id=$existingId';
    }
    final user = _provider.activeUser;
    final family = _provider.activeFamily;
    if (user == null || family == null) return '/devotional';
    final entry = DailyDevotionalService.findTodaysAuto(
      _provider.db,
      familyId: family.id,
      userId: user.id,
    );
    if (entry != null) return '/devotional?id=${entry.id}';
    return '/devotional';
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
          // OAuth callback or session restore: re-resolve auth from Supabase.
          // Do not call full [AppProvider.initialize] here — it reloads the local
          // DB and races with [AuthScreen._login] while [DatabaseService.reconcileCloud]
          // is in flight, breaking email-password sign-in.
          unawaited(_provider.resumeAuthAfterSupabaseSignIn());
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
    NotificationService.onRoutePending = null;
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  GoRouter _buildRouter(AppProvider provider) {
    return GoRouter(
      initialLocation: BuildFlags.photoframe ? '/photoframe' : '/',
      debugLogDiagnostics: false,
      redirect: (context, state) {
        // Still loading initial data — don't redirect yet
        if (provider.isInitializing) return null;

        final loc = state.matchedLocation;
        final isAuthenticated = provider.isAuthenticated;
        final isOnAuth = loc == '/auth';
        // Don't redirect away from auth during password recovery
        final isResetFlow =
            _isPasswordRecovery &&
            state.uri.queryParameters['resetPassword'] == 'true';

        if (!BuildFlags.photoframe && loc == '/photoframe') {
          return '/';
        }

        if (BuildFlags.photoframe) {
          if (!isAuthenticated && !isOnAuth) return '/auth';
          if (!isAuthenticated) return null;
          if (isAuthenticated && isOnAuth && !isResetFlow) {
            _isPasswordRecovery = false;
            return '/photoframe';
          }
          if (loc != '/photoframe') return '/photoframe';
          return null;
        }

        if (!isAuthenticated && !isOnAuth) return '/auth';
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
          pageBuilder: (context, state) {
            final resetPassword =
                state.uri.queryParameters['resetPassword'] == 'true';
            return _huddlePage(
              state,
              AuthScreen(
                key: ValueKey(resetPassword),
                showResetPassword: resetPassword,
              ),
            );
          },
        ),
        GoRoute(
          path: '/photoframe',
          name: 'photoframe',
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const PopScope(
              canPop: false,
              child: PhotoframeScreen(),
            ),
          ),
        ),
        // Dashboard: back does nothing (prevents accidental app exit on Android).
        GoRoute(
          path: '/',
          name: 'dashboard',
          pageBuilder: (context, state) => _huddlePage(
            state,
            const PopScope(
              canPop: false,
              child: DashboardScreen(),
            ),
          ),
        ),
        // All module screens: back goes to dashboard (or closes in-screen detail first).
        ShellRoute(
          builder: (context, state, child) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              // Let the screen handle back first (e.g. close list/plan detail)
              if (BackNavigationScope.invokeActive()) return;
              context.go('/');
            },
            child: ModuleRouteRecency(
              location: state.matchedLocation,
              child: child,
            ),
          ),
          routes: [
            GoRoute(
              path: '/tasks',
              name: 'tasks',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const TasksScreen(),
              ),
            ),
            GoRoute(
              path: '/chat',
              name: 'chat',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const ChatScreen(),
              ),
            ),
            GoRoute(
              path: '/assistant',
              name: 'assistant',
              pageBuilder: (context, state) {
                final q = state.uri.queryParameters;
                return _huddlePage(
                  state,
                  AssistantScreen(
                    initialQuery: q['q'],
                    fromPath: q['from'],
                    startDictation: q['dictate'] == '1',
                  ),
                );
              },
            ),
            GoRoute(
              path: '/calendar',
              name: 'calendar',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const CalendarScreen(),
              ),
            ),
            GoRoute(
              path: '/meals',
              name: 'meals',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const MealsScreen(),
              ),
            ),
            GoRoute(
              path: '/budget',
              name: 'budget',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const BudgetScreen(),
              ),
            ),
            GoRoute(
              path: '/lists',
              name: 'lists',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const ListsScreen(),
              ),
            ),
            GoRoute(
              path: '/chores',
              name: 'chores',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const ChoresScreen(),
              ),
            ),
            GoRoute(
              path: '/rewards',
              name: 'rewards',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const RewardsScreen(),
              ),
            ),
            GoRoute(
              path: '/fitness',
              name: 'fitness',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const FitnessScreen(),
              ),
            ),
            GoRoute(
              path: '/devotional',
              name: 'devotional',
              pageBuilder: (context, state) {
                final id = state.uri.queryParameters['id'] ??
                    state.uri.queryParameters['devotionalId'];
                return _huddlePage(
                  state,
                  DevotionalScreen(
                    key: ValueKey(id ?? 'devotional'),
                    initialDevotionalId: id,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/prayer-wall',
              name: 'prayer-wall',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const PrayerWallScreen(),
              ),
            ),
            GoRoute(
              path: '/polls',
              name: 'polls',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const PollsScreen(),
              ),
            ),
            GoRoute(
              path: '/period-tracker',
              name: 'period-tracker',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const PeriodTrackerScreen(),
              ),
            ),
            GoRoute(
              path: '/birthdays',
              name: 'birthdays',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const BirthdaysScreen(),
              ),
            ),
            GoRoute(
              path: '/photos',
              name: 'photos',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const PhotosScreen(),
              ),
            ),
            GoRoute(
              path: '/location',
              name: 'location',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const LocationScreen(),
              ),
            ),
            GoRoute(
              path: '/health',
              name: 'health',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const HealthScreen(),
              ),
            ),
            GoRoute(
              path: '/ai-history',
              name: 'ai-history',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const AIHistoryScreen(),
              ),
            ),
            GoRoute(
              path: '/habits',
              name: 'habits',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const HabitsScreen(),
              ),
            ),
            GoRoute(
              path: '/subscription',
              name: 'subscription',
              pageBuilder: (context, state) => _huddlePage(
                state,
                const SubscriptionScreen(),
              ),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final tt = theme.textTheme;
        return Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🧭', style: TextStyle(fontSize: 56, color: cs.onSurface.withValues(alpha: 0.35))),
                      const SizedBox(height: 20),
                      Semantics(
                        header: true,
                        child: Text(
                          'We couldn’t open that screen',
                          textAlign: TextAlign.center,
                          style: tt.headlineSmall?.copyWith(
                            height: 1.2,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${AppConfig.appName} may have been updated, or the link is out of date. Nothing was deleted.',
                        textAlign: TextAlign.center,
                        style: tt.bodyLarge?.copyWith(
                          height: 1.4,
                          color: cs.onSurface.withValues(alpha: 0.56),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        label: 'Broken route path',
                        child: Text(
                          state.matchedLocation,
                          textAlign: TextAlign.center,
                          style: tt.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.38),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => context.go(
                              BuildFlags.photoframe ? '/photoframe' : '/',
                            ),
                        icon: const Icon(Icons.home_rounded, size: 20),
                        label: Text('Back to home', style: tt.labelLarge),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRouterInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        final shell = MaterialApp.router(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _provider.themeMode,
            routerConfig: _router,
            builder: (context, child) {
              final theme = Theme.of(context);
              final dark = theme.brightness == Brightness.dark;
              SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                systemNavigationBarColor: theme.colorScheme.surface,
                systemNavigationBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ));
              // Router can pass null briefly; never use shrink here — ConnectivityWrapper
              // puts this in an Expanded, and shrink breaks flex layout (blank area).
              var wrapped = child ??
                  const Center(child: CircularProgressIndicator());
              if (kIsWeb) {
                wrapped = Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: wrapped,
                  ),
                );
              }
              return ConnectivityWrapper(child: wrapped);
            },
          );
        return BuildFlags.photoframe
            ? shell
            : BiometricLockScreen(child: shell);
      },
    );
  }
}

// ─────────────────────────────────────────────
// Helper: makes GoRouter re-evaluate redirect when AppProvider changes
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
// BackNavigationScope: lets screens register a custom back handler so
// the ShellRoute PopScope can delegate back to the screen first.
// ─────────────────────────────────────────────

class BackNavigationScope extends StatefulWidget {
  /// Called when the user triggers a back gesture. Return true if the screen
  /// handled it (e.g. dismissed a detail view); return false to let the shell
  /// navigate to dashboard.
  final bool Function() onBack;
  final Widget child;

  const BackNavigationScope({
    super.key,
    required this.onBack,
    required this.child,
  });

  /// Global registry so the ShellRoute PopScope (which sits *above* the child
  /// in the widget tree) can reach the currently-active back handler.
  static bool Function()? _activeHandler;
  static bool invokeActive() => _activeHandler?.call() ?? false;

  @override
  State<BackNavigationScope> createState() => _BackNavigationScopeState();
}

class _BackNavigationScopeState extends State<BackNavigationScope> {
  @override
  void initState() {
    super.initState();
    BackNavigationScope._activeHandler = widget.onBack;
  }

  @override
  void didUpdateWidget(BackNavigationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    BackNavigationScope._activeHandler = widget.onBack;
  }

  @override
  void dispose() {
    if (BackNavigationScope._activeHandler == widget.onBack) {
      BackNavigationScope._activeHandler = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
