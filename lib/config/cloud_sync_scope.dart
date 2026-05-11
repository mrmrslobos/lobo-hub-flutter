// Table keys for [DatabaseService.syncToCloud] / [AppProvider.saveAndSync] partial pushes.
// Values must match Supabase table names used in database_service.dart.

class CloudSyncScope {
  CloudSyncScope._();

  static const String users = 'users';
  static const String families = 'families';
  static const String familyMembers = 'family_members';

  static const String tasks = 'tasks';
  static const String events = 'events';
  static const String recipes = 'recipes';
  static const String mealPlans = 'meal_plans';
  static const String lists = 'lists';
  static const String devotionals = 'devotionals';
  static const String devotionalThoughts = 'devotional_thoughts';
  static const String fitness = 'fitness';
  static const String fitnessPlans = 'fitness_plans';
  static const String fitnessLogs = 'fitness_logs';
  static const String workoutSessions = 'workout_sessions';
  static const String workoutExercises = 'workout_exercises';
  static const String workoutSets = 'workout_sets';
  static const String exercisePrs = 'exercise_prs';
  static const String budgetCategories = 'budget_categories';
  static const String budgetEntries = 'budget_entries';
  static const String transactions = 'transactions';
  static const String aiHistory = 'ai_history';
  static const String dailyHabits = 'daily_habits';
  static const String dailyHabitCompletions = 'daily_habit_completions';
  static const String chores = 'chores';
  static const String choreCompletions = 'chore_completions';
  static const String polls = 'polls';
  static const String pollVotes = 'poll_votes';
  static const String rewardItems = 'reward_items';
  static const String rewardRedemptions = 'reward_redemptions';
  static const String savingsGoals = 'savings_goals';
  static const String prayerWall = 'prayer_wall';
  static const String specialDates = 'special_dates';
  static const String familyPhotos = 'family_photos';
  static const String milestones = 'milestones';
  static const String savedPlaces = 'saved_places';
  static const String userLocations = 'user_locations';
  static const String messages = 'messages';
  static const String healthRecords = 'health_records';
  static const String periodCycles = 'period_cycles';
  static const String periodSymptoms = 'period_symptoms';
  static const String externalCalendars = 'external_calendars';
  static const String rewards = 'rewards';
  static const String readingPlans = 'reading_plans';
  static const String readingPlanProgress = 'reading_plan_progress';
  static const String pantryItems = 'pantry_items';
  static const String familyActivityLogs = 'family_activity_logs';
  static const String wellnessCheckIns = 'wellness_check_ins';

  /// Devotional entry + per-user notes (thoughts + prayers).
  static Set<String> get devotionalBundle => {
        devotionals,
        devotionalThoughts,
      };

  static Set<String> get readingPlanBundle => {
        readingPlans,
        readingPlanProgress,
      };

  static Set<String> get devotionalReadingPlanBundle => {
        ...devotionalBundle,
        readingPlanProgress,
      };

  /// Budget-related tables often saved together.
  static Set<String> get budgetBundle => {
        budgetCategories,
        budgetEntries,
        transactions,
        savingsGoals,
      };

  /// Chores + completion rows are often updated together (rotation cursor).
  static Set<String> get choreBundle => {
        chores,
        choreCompletions,
      };

  /// Daily habits + per-user completion rows.
  static Set<String> get habitBundle => {
        dailyHabits,
        dailyHabitCompletions,
      };

  static Set<String> get pollBundle => {polls, pollVotes};

  static Set<String> get photoMilestoneBundle => {familyPhotos, milestones};

  static Set<String> get fitnessFullBundle => {
        fitness,
        fitnessPlans,
        fitnessLogs,
        workoutSessions,
        workoutExercises,
        workoutSets,
        exercisePrs,
      };

  /// Recipes, meal plans, pantry, and lists often change together from Meal Hub.
  static Set<String> get mealsExtendedBundle => {
        recipes,
        mealPlans,
        pantryItems,
        lists,
      };

  /// Week / AI meal planning may also create tasks (prep reminders).
  static Set<String> get mealsPlannerBundle => {
        ...mealsExtendedBundle,
        tasks,
      };

  static Set<String> get locationBundle => {savedPlaces, userLocations};

  static Set<String> get calendarBundle => {events, externalCalendars};

  static Set<String> get occasionBundle => {specialDates};

  static Set<String> get rewardFullBundle => {
        rewardItems,
        rewardRedemptions,
        savingsGoals,
        rewards,
      };

  static Set<String> get periodBundle => {periodCycles, periodSymptoms};

  /// AI event planner: events + related tasks + shopping lists.
  static Set<String> get eventPlannerAiBundle => {events, tasks, lists};

  static Set<String> get workoutSessionBundle => {
        workoutSessions,
        workoutExercises,
        workoutSets,
      };

  /// Tables eligible for incremental pull via per-`(familyId, table)`
  /// `last_synced_at` cursors. Two requirements:
  ///   1. The table has a real `updated_at timestamptz` column.
  ///   2. Absence of a row from an incremental response is not interpreted
  ///      as "row was deleted" (incremental fetches also include
  ///      `deleted_at != null` rows so the client learns about deletes).
  /// `users`, `families`, `family_members` stay full-pull as they're
  /// foundational and small.
  static const Set<String> incrementalEligibleTables = {
    // Soft-delete family-scoped tables (deletes propagate via deleted_at).
    tasks, events, lists, recipes, mealPlans, chores, polls,
    prayerWall, devotionals, readingPlans, specialDates,
    familyPhotos, savedPlaces, rewardItems, savingsGoals,
    dailyHabits, budgetCategories, transactions, budgetEntries,
    milestones, externalCalendars, healthRecords,
    periodCycles, periodSymptoms, rewards,
    // Append-only / log-like tables with reliable updated_at.
    messages, familyActivityLogs, aiHistory,
    dailyHabitCompletions, choreCompletions, pollVotes,
    rewardRedemptions, devotionalThoughts, readingPlanProgress,
    pantryItems, wellnessCheckIns, exercisePrs,
    workoutSessions, workoutExercises, workoutSets,
    fitness, fitnessLogs, fitnessPlans,
  };

  /// Tables we subscribe to via Postgres realtime, filtered by `family_id`.
  /// Single source of truth so the realtime subscription list can't drift
  /// from the push scope. `families` is subscribed separately (filter by id).
  static const List<String> realtimeFamilyScopedTables = [
    tasks, events, recipes, mealPlans, lists, devotionals, devotionalThoughts,
    budgetCategories, budgetEntries, transactions, chores, choreCompletions,
    polls, pollVotes, rewardItems, rewardRedemptions, savingsGoals, prayerWall,
    specialDates, familyPhotos, milestones, savedPlaces, messages,
    healthRecords, readingPlans, readingPlanProgress, rewards, externalCalendars,
    pantryItems, familyActivityLogs, wellnessCheckIns, exercisePrs, aiHistory,
    dailyHabits, dailyHabitCompletions, familyMembers, fitness, fitnessLogs,
    fitnessPlans, periodCycles, periodSymptoms, userLocations,
    workoutExercises, workoutSessions, workoutSets,
  ];

  /// Tables with a server-side `deleted_at` column. Deletes on these tables
  /// must be UPDATEs setting `deleted_at = now()`, not DELETEs. Fetches must
  /// filter `deleted_at IS NULL`. See migration 20260511120300_add_deleted_at.
  static const Set<String> softDeleteTables = {
    tasks,
    events,
    lists,
    recipes,
    mealPlans,
    chores,
    polls,
    prayerWall,
    devotionals,
    readingPlans,
    specialDates,
    familyPhotos,
    savedPlaces,
    rewardItems,
    savingsGoals,
    dailyHabits,
    budgetCategories,
    transactions,
    budgetEntries,
    milestones,
    externalCalendars,
    healthRecords,
    periodCycles,
    periodSymptoms,
    rewards,
  };
}
