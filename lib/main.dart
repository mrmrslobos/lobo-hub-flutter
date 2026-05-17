import 'dart:async';

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
import 'repositories/app_db_ai_history_repository.dart';
import 'repositories/app_db_calendar_events_repository.dart';
import 'repositories/app_db_budget_categories_repository.dart';
import 'repositories/app_db_budget_entries_repository.dart';
import 'repositories/app_db_chore_completions_repository.dart';
import 'repositories/app_db_chores_repository.dart';
import 'repositories/app_db_daily_habit_completions_repository.dart';
import 'repositories/app_db_daily_habits_repository.dart';
import 'repositories/app_db_devotional_thoughts_repository.dart';
import 'repositories/app_db_devotionals_repository.dart';
import 'repositories/app_db_exercise_prs_repository.dart';
import 'repositories/app_db_external_calendars_repository.dart';
import 'repositories/app_db_family_activity_logs_repository.dart';
import 'repositories/app_db_family_photos_repository.dart';
import 'repositories/app_db_fitness_logs_repository.dart';
import 'repositories/app_db_fitness_metrics_repository.dart';
import 'repositories/app_db_health_records_repository.dart';
import 'repositories/app_db_meal_plans_repository.dart';
import 'repositories/app_db_messages_repository.dart';
import 'repositories/app_db_milestones_repository.dart';
import 'repositories/app_db_pantry_items_repository.dart';
import 'repositories/app_db_period_cycles_repository.dart';
import 'repositories/app_db_period_symptoms_repository.dart';
import 'repositories/app_db_poll_votes_repository.dart';
import 'repositories/app_db_polls_repository.dart';
import 'repositories/app_db_prayer_wall_repository.dart';
import 'repositories/app_db_reading_plan_progress_repository.dart';
import 'repositories/app_db_reading_plans_repository.dart';
import 'repositories/app_db_recipes_repository.dart';
import 'repositories/app_db_reward_items_repository.dart';
import 'repositories/app_db_reward_redemptions_repository.dart';
import 'repositories/app_db_rewards_repository.dart';
import 'repositories/app_db_saved_places_repository.dart';
import 'repositories/app_db_savings_goals_repository.dart';
import 'repositories/app_db_shopping_list_repository.dart';
import 'repositories/app_db_special_dates_repository.dart';
import 'repositories/app_db_tasks_repository.dart';
import 'repositories/app_db_transactions_repository.dart';
import 'repositories/app_db_user_locations_repository.dart';
import 'repositories/app_db_wellness_check_ins_repository.dart';
import 'repositories/app_db_workout_exercises_repository.dart';
import 'repositories/app_db_workout_sessions_repository.dart';
import 'repositories/app_db_workout_sets_repository.dart';
import 'repositories/ai_history_repository.dart';
import 'repositories/calendar_events_repository.dart';
import 'repositories/budget_categories_repository.dart';
import 'repositories/budget_entries_repository.dart';
import 'repositories/chore_completions_repository.dart';
import 'repositories/chores_repository.dart';
import 'repositories/daily_habit_completions_repository.dart';
import 'repositories/daily_habits_repository.dart';
import 'repositories/devotional_thoughts_repository.dart';
import 'repositories/devotionals_repository.dart';
import 'repositories/exercise_prs_repository.dart';
import 'repositories/external_calendars_repository.dart';
import 'repositories/family_activity_logs_repository.dart';
import 'repositories/family_photos_repository.dart';
import 'repositories/fitness_logs_repository.dart';
import 'repositories/fitness_metrics_repository.dart';
import 'repositories/health_records_repository.dart';
import 'repositories/meal_plans_repository.dart';
import 'repositories/messages_repository.dart';
import 'repositories/milestones_repository.dart';
import 'repositories/pantry_items_repository.dart';
import 'repositories/period_cycles_repository.dart';
import 'repositories/period_symptoms_repository.dart';
import 'repositories/poll_votes_repository.dart';
import 'repositories/polls_repository.dart';
import 'repositories/prayer_wall_repository.dart';
import 'repositories/reading_plan_progress_repository.dart';
import 'repositories/reading_plans_repository.dart';
import 'repositories/recipes_repository.dart';
import 'repositories/reward_items_repository.dart';
import 'repositories/reward_redemptions_repository.dart';
import 'repositories/rewards_repository.dart';
import 'repositories/saved_places_repository.dart';
import 'repositories/savings_goals_repository.dart';
import 'repositories/shopping_list_repository.dart';
import 'repositories/special_dates_repository.dart';
import 'repositories/tasks_repository.dart';
import 'repositories/transactions_repository.dart';
import 'repositories/user_locations_repository.dart';
import 'repositories/wellness_check_ins_repository.dart';
import 'repositories/workout_exercises_repository.dart';
import 'repositories/workout_sessions_repository.dart';
import 'repositories/workout_sets_repository.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'services/locale_service.dart';
import 'services/crash_reporting_service.dart';
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
    unawaited(NotificationService.ensureReady());
    unawaited(CrashReportingService.init());
    unawaited(PurchaseService.init(iosApiKey: iosKey, androidApiKey: androidKey));
    unawaited(appProvider.initialize());
  }

  scheduleMicrotask(startDeferredBootstrap);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DataProvider>.value(value: dataProvider),
        Provider<TasksRepository>(
          create: (ctx) => AppDbTasksRepository(
            dataProvider: ctx.read<DataProvider>(),
          ),
        ),
        Provider<ShoppingListsRepository>(
          create: (ctx) => AppDbShoppingListsRepository(
            dataProvider: ctx.read<DataProvider>(),
          ),
        ),
        Provider<PrayerWallRepository>(
          create: (ctx) => AppDbPrayerWallRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<SpecialDatesRepository>(
          create: (ctx) => AppDbSpecialDatesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<CalendarEventsRepository>(
          create: (ctx) => AppDbCalendarEventsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<ExternalCalendarsRepository>(
          create: (ctx) => AppDbExternalCalendarsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<RecipesRepository>(
          create: (ctx) => AppDbRecipesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<MealPlansRepository>(
          create: (ctx) => AppDbMealPlansRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<PantryItemsRepository>(
          create: (ctx) => AppDbPantryItemsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<DevotionalsRepository>(
          create: (ctx) => AppDbDevotionalsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<DevotionalThoughtsRepository>(
          create: (ctx) => AppDbDevotionalThoughtsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<ChoresRepository>(
          create: (ctx) => AppDbChoresRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<ChoreCompletionsRepository>(
          create: (ctx) => AppDbChoreCompletionsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<PollsRepository>(
          create: (ctx) => AppDbPollsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<PollVotesRepository>(
          create: (ctx) => AppDbPollVotesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<DailyHabitsRepository>(
          create: (ctx) => AppDbDailyHabitsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<DailyHabitCompletionsRepository>(
          create: (ctx) => AppDbDailyHabitCompletionsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<BudgetCategoriesRepository>(
          create: (ctx) => AppDbBudgetCategoriesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<BudgetEntriesRepository>(
          create: (ctx) => AppDbBudgetEntriesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<TransactionsRepository>(
          create: (ctx) => AppDbTransactionsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<SavingsGoalsRepository>(
          create: (ctx) => AppDbSavingsGoalsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<RewardItemsRepository>(
          create: (ctx) => AppDbRewardItemsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<RewardsRepository>(
          create: (ctx) => AppDbRewardsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<RewardRedemptionsRepository>(
          create: (ctx) => AppDbRewardRedemptionsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<HealthRecordsRepository>(
          create: (ctx) => AppDbHealthRecordsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<ReadingPlansRepository>(
          create: (ctx) => AppDbReadingPlansRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<ReadingPlanProgressRepository>(
          create: (ctx) => AppDbReadingPlanProgressRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<FamilyPhotosRepository>(
          create: (ctx) => AppDbFamilyPhotosRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<MilestonesRepository>(
          create: (ctx) => AppDbMilestonesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<SavedPlacesRepository>(
          create: (ctx) => AppDbSavedPlacesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<WellnessCheckInsRepository>(
          create: (ctx) => AppDbWellnessCheckInsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<MessagesRepository>(
          create: (ctx) => AppDbMessagesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<AIHistoryRepository>(
          create: (ctx) => AppDbAIHistoryRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<FamilyActivityLogsRepository>(
          create: (ctx) => AppDbFamilyActivityLogsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<FitnessMetricsRepository>(
          create: (ctx) => AppDbFitnessMetricsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<FitnessLogsRepository>(
          create: (ctx) => AppDbFitnessLogsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<WorkoutSessionsRepository>(
          create: (ctx) => AppDbWorkoutSessionsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<WorkoutExercisesRepository>(
          create: (ctx) => AppDbWorkoutExercisesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<WorkoutSetsRepository>(
          create: (ctx) => AppDbWorkoutSetsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<ExercisePRsRepository>(
          create: (ctx) => AppDbExercisePRsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<PeriodCyclesRepository>(
          create: (ctx) => AppDbPeriodCyclesRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<PeriodSymptomsRepository>(
          create: (ctx) => AppDbPeriodSymptomsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
        Provider<UserLocationsRepository>(
          create: (ctx) => AppDbUserLocationsRepository(dataProvider: ctx.read<DataProvider>()),
        ),
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
