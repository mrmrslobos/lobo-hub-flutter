// lib/models/app_db.dart
// ignore_for_file: constant_identifier_names

import '../services/field_encryption_service.dart';
import 'emergency_contact.dart';
import 'model_json_helpers.dart';
import 'ai_history.dart';
import 'budget_category_record.dart';
import 'budget_entry.dart';
import 'calendar_event.dart';
import 'chat_message.dart';
import 'chore.dart';
import 'chore_completion.dart';
import 'daily_habit.dart';
import 'daily_habit_completion.dart';
import 'devotional_entry.dart';
import 'devotional_thought.dart';
import 'exercise_pr.dart';
import 'external_calendar.dart';
import 'family.dart';
import 'family_activity_log.dart';
import 'family_member.dart';
import 'family_photo.dart';
import 'fitness_log.dart';
import 'fitness_metric.dart';
import 'health_allergy.dart';
import 'health_condition.dart';
import 'health_immunization.dart';
import 'health_medication.dart';
import 'health_record.dart';
import 'meal_plan_entry.dart';
import 'milestone.dart';
import 'notification_prefs.dart';
import 'pantry_item.dart';
import 'period_cycle.dart';
import 'period_symptom_log.dart';
import 'poll.dart';
import 'poll_vote.dart';
import 'prayer_wall_entry.dart';
import 'reading_plan.dart';
import 'reading_plan_progress.dart';
import 'recipe.dart';
import 'reward.dart';
import 'reward_item.dart';
import 'reward_redemption.dart';
import 'saved_place.dart';
import 'shopping_list.dart';
import 'special_date.dart';
import 'task.dart';
import 'transaction.dart';
import 'user.dart';
import 'user_location.dart';
import 'wellness_check_in.dart';
import 'workout_exercise.dart';
import 'workout_session.dart';
import 'workout_set.dart';
import 'savings_goal.dart';

class AppDB {
  final List<User> users;
  final List<Family> families;
  final List<FamilyMember> familyMembers;
  final List<Task> tasks;
  final List<CalendarEvent> events;
  final List<Recipe> recipes;
  final List<MealPlanEntry> mealPlans;
  final List<ShoppingList> lists;
  final List<DevotionalEntry> devotionals;
  final List<DevotionalThought> devotionalThoughts;
  final List<FitnessMetric> fitness;
  final List<FitnessLog> fitnessLogs;
  final List<dynamic> fitnessPlans;
  final List<WorkoutSession> workoutSessions;
  final List<WorkoutExercise> workoutExercises;
  final List<WorkoutSet> workoutSets;
  final List<ExercisePR> exercisePrs;
  final List<BudgetCategoryRecord> budgetCategories;
  final List<BudgetEntry> budgetEntries;
  final List<Transaction> transactions;
  final List<AIHistory> aiHistory;
  final List<DailyHabit> dailyHabits;
  final List<DailyHabitCompletion> dailyHabitCompletions;
  final List<Chore> chores;
  final List<ChoreCompletion> choreCompletions;
  final List<Poll> polls;
  final List<PollVote> pollVotes;
  final List<RewardItem> rewardItems;
  final List<Reward> rewards;
  final List<RewardRedemption> rewardRedemptions;
  final List<SavingsGoal> savingsGoals;
  final List<PrayerWallEntry> prayerWall;
  final List<SpecialDate> specialDates;
  final List<FamilyPhoto> familyPhotos;
  final List<Milestone> milestones;
  final List<SavedPlace> savedPlaces;
  final List<UserLocation> userLocations;
  final List<ChatMessage> messages;
  final List<HealthRecord> healthRecords;
  final List<PeriodCycle> periodCycles;
  final List<PeriodSymptomLog> periodSymptoms;
  final List<NotificationPrefs> notificationPrefs;
  final List<ReadingPlan> readingPlans;
  final List<ReadingPlanProgress> readingPlanProgress;
  final List<ExternalCalendar> externalCalendars;
  final List<PantryItem> pantryItems;
  final List<FamilyActivityLog> familyActivityLogs;
  final List<WellnessCheckIn> wellnessCheckIns;

  const AppDB({
    this.users = const [],
    this.families = const [],
    this.familyMembers = const [],
    this.tasks = const [],
    this.events = const [],
    this.recipes = const [],
    this.mealPlans = const [],
    this.lists = const [],
    this.devotionals = const [],
    this.devotionalThoughts = const [],
    this.fitness = const [],
    this.fitnessLogs = const [],
    this.fitnessPlans = const [],
    this.workoutSessions = const [],
    this.workoutExercises = const [],
    this.workoutSets = const [],
    this.exercisePrs = const [],
    this.budgetCategories = const <BudgetCategoryRecord>[],
    this.budgetEntries = const [],
    this.transactions = const [],
    this.aiHistory = const [],
    this.dailyHabits = const [],
    this.dailyHabitCompletions = const [],
    this.chores = const [],
    this.choreCompletions = const [],
    this.polls = const [],
    this.pollVotes = const [],
    this.rewardItems = const [],
    this.rewards = const [],
    this.rewardRedemptions = const [],
    this.savingsGoals = const [],
    this.prayerWall = const [],
    this.specialDates = const [],
    this.familyPhotos = const [],
    this.milestones = const [],
    this.savedPlaces = const [],
    this.userLocations = const [],
    this.messages = const [],
    this.healthRecords = const [],
    this.periodCycles = const [],
    this.periodSymptoms = const [],
    this.notificationPrefs = const [],
    this.readingPlans = const [],
    this.readingPlanProgress = const [],
    this.externalCalendars = const [],
    this.pantryItems = const [],
    this.familyActivityLogs = const [],
    this.wellnessCheckIns = const [],
  });

  factory AppDB.empty() => const AppDB();

  factory AppDB.fromJson(Map<String, dynamic> j) => AppDB(
    users: parseList(j['users'], User.fromJson),
    families: parseList(j['families'], Family.fromJson),
    familyMembers: parseList(j['familyMembers'] ?? j['family_members'], FamilyMember.fromJson),
    tasks: parseList(j['tasks'], Task.fromJson),
    events: parseList(j['events'], CalendarEvent.fromJson),
    recipes: parseList(j['recipes'], Recipe.fromJson),
    mealPlans: parseList(j['mealPlans'] ?? j['meal_plans'], MealPlanEntry.fromJson),
    lists: parseList(j['lists'], ShoppingList.fromJson),
    devotionals: parseList(j['devotionals'], DevotionalEntry.fromJson),
    devotionalThoughts: parseList(
      j['devotionalThoughts'] ?? j['devotional_thoughts'],
      DevotionalThought.fromJson,
    ),
    fitness: parseList(j['fitness'], FitnessMetric.fromJson),
    fitnessLogs: parseList(j['fitnessLogs'] ?? j['fitness_logs'], FitnessLog.fromJson),
    fitnessPlans: (j['fitnessPlans'] ?? j['fitness_plans']) is List
        ? (j['fitnessPlans'] ?? j['fitness_plans']) as List
        : [],
    workoutSessions: parseList(j['workoutSessions'] ?? j['workout_sessions'], WorkoutSession.fromJson),
    workoutExercises: parseList(j['workoutExercises'] ?? j['workout_exercises'], WorkoutExercise.fromJson),
    workoutSets: parseList(j['workoutSets'] ?? j['workout_sets'], WorkoutSet.fromJson),
    exercisePrs: parseList(j['exercisePrs'] ?? j['exercise_prs'], ExercisePR.fromJson),
    budgetCategories: parseList(j['budgetCategories'] ?? j['budget_categories'], BudgetCategoryRecord.fromJson),
    budgetEntries: parseList(j['budgetEntries'] ?? j['budget_entries'], BudgetEntry.fromJson),
    transactions: parseList(j['transactions'], Transaction.fromJson),
    aiHistory: parseList(j['aiHistory'] ?? j['ai_history'], AIHistory.fromJson),
    dailyHabits: parseList(j['dailyHabits'] ?? j['daily_habits'], DailyHabit.fromJson),
    dailyHabitCompletions: parseList(j['dailyHabitCompletions'] ?? j['daily_habit_completions'], DailyHabitCompletion.fromJson),
    chores: parseList(j['chores'], Chore.fromJson),
    choreCompletions: parseList(j['choreCompletions'] ?? j['chore_completions'], ChoreCompletion.fromJson),
    polls: parseList(j['polls'], Poll.fromJson),
    pollVotes: parseList(j['pollVotes'] ?? j['poll_votes'], PollVote.fromJson),
    rewardItems: parseList(j['rewardItems'] ?? j['reward_items'], RewardItem.fromJson),
    rewards: parseList(j['rewards'], Reward.fromJson),
    rewardRedemptions: parseList(j['rewardRedemptions'] ?? j['reward_redemptions'], RewardRedemption.fromJson),
    savingsGoals: parseList(j['savingsGoals'] ?? j['savings_goals'], SavingsGoal.fromJson),
    prayerWall: parseList(j['prayerWall'] ?? j['prayer_wall'], PrayerWallEntry.fromJson),
    specialDates: parseList(j['specialDates'] ?? j['special_dates'], SpecialDate.fromJson),
    familyPhotos: parseList(j['familyPhotos'] ?? j['family_photos'], FamilyPhoto.fromJson),
    milestones: parseList(j['milestones'], Milestone.fromJson),
    savedPlaces: parseList(j['savedPlaces'] ?? j['saved_places'], SavedPlace.fromJson),
    userLocations: parseList(j['userLocations'] ?? j['user_locations'], UserLocation.fromJson),
    messages: parseList(j['messages'], ChatMessage.fromJson),
    healthRecords: parseList(j['healthRecords'] ?? j['health_records'], HealthRecord.fromJson),
    periodCycles: parseList(j['periodCycles'] ?? j['period_cycles'], PeriodCycle.fromJson),
    periodSymptoms: parseList(j['periodSymptoms'] ?? j['period_symptoms'], PeriodSymptomLog.fromJson),
    notificationPrefs: parseList(j['notificationPrefs'] ?? j['notification_prefs'], NotificationPrefs.fromJson),
    readingPlans: parseList(j['readingPlans'] ?? j['reading_plans'], ReadingPlan.fromJson),
    readingPlanProgress: parseList(
      j['readingPlanProgress'] ?? j['reading_plan_progress'],
      ReadingPlanProgress.fromJson,
    ),
    externalCalendars: parseList(j['externalCalendars'] ?? j['external_calendars'], ExternalCalendar.fromJson),
    pantryItems: parseList(j['pantryItems'] ?? j['pantry_items'], PantryItem.fromJson),
    familyActivityLogs: parseList(j['familyActivityLogs'] ?? j['family_activity_logs'], FamilyActivityLog.fromJson),
    wellnessCheckIns: parseList(j['wellnessCheckIns'] ?? j['wellness_check_ins'], WellnessCheckIn.fromJson),
  );

  /// fromCloudJson handles Supabase snake_case table names -> AppDB fields
  factory AppDB.fromCloudJson(Map<String, dynamic> cloud) => AppDB(
    users: parseList(cloud['users'], User.fromJson),
    families: parseList(cloud['families'], Family.fromJson),
    familyMembers: parseList(cloud['family_members'], FamilyMember.fromJson),
    tasks: parseList(cloud['tasks'], Task.fromJson),
    events: parseList(cloud['events'], CalendarEvent.fromJson),
    recipes: parseList(cloud['recipes'], Recipe.fromJson),
    mealPlans: parseList(cloud['meal_plans'], MealPlanEntry.fromJson),
    lists: parseList(cloud['lists'], ShoppingList.fromJson),
    devotionals: parseList(cloud['devotionals'], DevotionalEntry.fromJson),
    devotionalThoughts: parseList(
      cloud['devotional_thoughts'],
      DevotionalThought.fromJson,
    ),
    fitness: parseList(cloud['fitness_metrics'], FitnessMetric.fromJson),
    fitnessLogs: parseList(cloud['fitness_logs'], FitnessLog.fromJson),
    fitnessPlans: cloud['fitness_plans'] is List ? cloud['fitness_plans'] as List : [],
    workoutSessions: parseList(cloud['workout_sessions'], WorkoutSession.fromJson),
    workoutExercises: parseList(cloud['workout_exercises'], WorkoutExercise.fromJson),
    workoutSets: parseList(cloud['workout_sets'], WorkoutSet.fromJson),
    exercisePrs: parseList(cloud['exercise_prs'], ExercisePR.fromJson),
    budgetCategories: parseList(cloud['budget_categories'], BudgetCategoryRecord.fromJson),
    budgetEntries: parseList(cloud['budget_entries'], BudgetEntry.fromJson),
    transactions: parseList(cloud['transactions'], Transaction.fromJson),
    aiHistory: parseList(cloud['ai_history'], AIHistory.fromJson),
    dailyHabits: parseList(cloud['daily_habits'], DailyHabit.fromJson),
    dailyHabitCompletions: parseList(cloud['daily_habit_completions'], DailyHabitCompletion.fromJson),
    chores: parseList(cloud['chores'], Chore.fromJson),
    choreCompletions: parseList(cloud['chore_completions'], ChoreCompletion.fromJson),
    polls: parseList(cloud['polls'], Poll.fromJson),
    pollVotes: parseList(cloud['poll_votes'], PollVote.fromJson),
    rewardItems: parseList(cloud['reward_items'], RewardItem.fromJson),
    rewards: parseList(cloud['rewards'], Reward.fromJson),
    rewardRedemptions: parseList(cloud['reward_redemptions'], RewardRedemption.fromJson),
    savingsGoals: parseList(cloud['savings_goals'], SavingsGoal.fromJson),
    prayerWall: parseList(cloud['prayer_wall'], PrayerWallEntry.fromJson),
    specialDates: parseList(cloud['special_dates'], SpecialDate.fromJson),
    familyPhotos: parseList(cloud['family_photos'], FamilyPhoto.fromJson),
    milestones: parseList(cloud['milestones'], Milestone.fromJson),
    savedPlaces: parseList(cloud['saved_places'], SavedPlace.fromJson),
    userLocations: parseList(cloud['user_locations'], UserLocation.fromJson),
    messages: parseList(cloud['messages'], ChatMessage.fromJson),
    healthRecords: parseList(cloud['health_records'], HealthRecord.fromJson),
    periodCycles: parseList(cloud['period_cycles'], PeriodCycle.fromJson),
    periodSymptoms: parseList(cloud['period_symptoms'], PeriodSymptomLog.fromJson),
    notificationPrefs: const [],
    readingPlans: parseList(cloud['reading_plans'], ReadingPlan.fromJson),
    readingPlanProgress: parseList(
      cloud['reading_plan_progress'],
      ReadingPlanProgress.fromJson,
    ),
    externalCalendars: parseList(cloud['external_calendars'], ExternalCalendar.fromJson),
    pantryItems: parseList(cloud['pantry_items'], PantryItem.fromJson),
    familyActivityLogs: parseList(cloud['family_activity_logs'], FamilyActivityLog.fromJson),
    wellnessCheckIns: parseList(cloud['wellness_check_ins'], WellnessCheckIn.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'users': users.map((e) => e.toJson()).toList(),
    'families': families.map((e) => e.toJson()).toList(),
    'familyMembers': familyMembers.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'recipes': recipes.map((e) => e.toJson()).toList(),
    'mealPlans': mealPlans.map((e) => e.toJson()).toList(),
    'lists': lists.map((e) => e.toJson()).toList(),
    'devotionals': devotionals.map((e) => e.toJson()).toList(),
    'devotionalThoughts': devotionalThoughts.map((e) => e.toJson()).toList(),
    'fitness': fitness.map((e) => e.toJson()).toList(),
    'fitnessLogs': fitnessLogs.map((e) => e.toJson()).toList(),
    'fitnessPlans': fitnessPlans,
    'workoutSessions': workoutSessions.map((e) => e.toJson()).toList(),
    'workoutExercises': workoutExercises.map((e) => e.toJson()).toList(),
    'workoutSets': workoutSets.map((e) => e.toJson()).toList(),
    'exercisePrs': exercisePrs.map((e) => e.toJson()).toList(),
    'budgetCategories': budgetCategories.map((e) => e.toJson()).toList(),
    'budgetEntries': budgetEntries.map((e) => e.toJson()).toList(),
    'transactions': transactions.map((e) => e.toJson()).toList(),
    'aiHistory': aiHistory.map((e) => e.toJson()).toList(),
    'dailyHabits': dailyHabits.map((e) => e.toJson()).toList(),
    'dailyHabitCompletions': dailyHabitCompletions.map((e) => e.toJson()).toList(),
    'chores': chores.map((e) => e.toJson()).toList(),
    'choreCompletions': choreCompletions.map((e) => e.toJson()).toList(),
    'polls': polls.map((e) => e.toJson()).toList(),
    'pollVotes': pollVotes.map((e) => e.toJson()).toList(),
    'rewardItems': rewardItems.map((e) => e.toJson()).toList(),
    'rewards': rewards.map((e) => e.toJson()).toList(),
    'rewardRedemptions': rewardRedemptions.map((e) => e.toJson()).toList(),
    'savingsGoals': savingsGoals.map((e) => e.toJson()).toList(),
    'prayerWall': prayerWall.map((e) => e.toJson()).toList(),
    'specialDates': specialDates.map((e) => e.toJson()).toList(),
    'familyPhotos': familyPhotos.map((e) => e.toJson()).toList(),
    'milestones': milestones.map((e) => e.toJson()).toList(),
    'savedPlaces': savedPlaces.map((e) => e.toJson()).toList(),
    'userLocations': userLocations.map((e) => e.toJson()).toList(),
    'messages': messages.map((e) => e.toJson()).toList(),
    'healthRecords': healthRecords.map((e) => e.toJson()).toList(),
    'periodCycles': periodCycles.map((e) => e.toJson()).toList(),
    'periodSymptoms': periodSymptoms.map((e) => e.toJson()).toList(),
    'notificationPrefs': notificationPrefs.map((e) => e.toJson()).toList(),
    'readingPlans': readingPlans.map((e) => e.toJson()).toList(),
    'readingPlanProgress': readingPlanProgress.map((e) => e.toJson()).toList(),
    'externalCalendars': externalCalendars.map((e) => e.toJson()).toList(),
    'pantryItems': pantryItems.map((e) => e.toJson()).toList(),
    'familyActivityLogs': familyActivityLogs.map((e) => e.toJson()).toList(),
    'wellnessCheckIns': wellnessCheckIns.map((e) => e.toJson()).toList(),
  };

  AppDB copyWith({
    List<User>? users,
    List<Family>? families,
    List<FamilyMember>? familyMembers,
    List<Task>? tasks,
    List<CalendarEvent>? events,
    List<Recipe>? recipes,
    List<MealPlanEntry>? mealPlans,
    List<ShoppingList>? lists,
    List<DevotionalEntry>? devotionals,
    List<DevotionalThought>? devotionalThoughts,
    List<FitnessMetric>? fitness,
    List<FitnessLog>? fitnessLogs,
    List<dynamic>? fitnessPlans,
    List<WorkoutSession>? workoutSessions,
    List<WorkoutExercise>? workoutExercises,
    List<WorkoutSet>? workoutSets,
    List<ExercisePR>? exercisePrs,
    List<BudgetCategoryRecord>? budgetCategories,
    List<BudgetEntry>? budgetEntries,
    List<Transaction>? transactions,
    List<AIHistory>? aiHistory,
    List<DailyHabit>? dailyHabits,
    List<DailyHabitCompletion>? dailyHabitCompletions,
    List<Chore>? chores,
    List<ChoreCompletion>? choreCompletions,
    List<Poll>? polls,
    List<PollVote>? pollVotes,
    List<RewardItem>? rewardItems,
    List<Reward>? rewards,
    List<RewardRedemption>? rewardRedemptions,
    List<SavingsGoal>? savingsGoals,
    List<PrayerWallEntry>? prayerWall,
    List<SpecialDate>? specialDates,
    List<FamilyPhoto>? familyPhotos,
    List<Milestone>? milestones,
    List<SavedPlace>? savedPlaces,
    List<UserLocation>? userLocations,
    List<ChatMessage>? messages,
    List<HealthRecord>? healthRecords,
    List<PeriodCycle>? periodCycles,
    List<PeriodSymptomLog>? periodSymptoms,
    List<NotificationPrefs>? notificationPrefs,
    List<ReadingPlan>? readingPlans,
    List<ReadingPlanProgress>? readingPlanProgress,
    List<ExternalCalendar>? externalCalendars,
    List<PantryItem>? pantryItems,
    List<FamilyActivityLog>? familyActivityLogs,
    List<WellnessCheckIn>? wellnessCheckIns,
    // Convenience alias params
    List<PrayerWallEntry>? prayerRequests,
    List<PeriodCycle>? periodEntries,
    List<SpecialDate>? occasions,
    List<FamilyPhoto>? photos,
    List<UserLocation>? locationShares,
    List<DailyHabitCompletion>? habitCompletions,
    List<DevotionalEntry>? devotionalEntries,
    List<ShoppingList>? shoppingLists,
  }) => AppDB(
    users: users ?? this.users,
    families: families ?? this.families,
    familyMembers: familyMembers ?? this.familyMembers,
    tasks: tasks ?? this.tasks,
    events: events ?? this.events,
    recipes: recipes ?? this.recipes,
    mealPlans: mealPlans ?? this.mealPlans,
    lists: shoppingLists ?? lists ?? this.lists,
    devotionals: devotionalEntries ?? devotionals ?? this.devotionals,
    devotionalThoughts: devotionalThoughts ?? this.devotionalThoughts,
    fitness: fitness ?? this.fitness,
    fitnessLogs: fitnessLogs ?? this.fitnessLogs,
    fitnessPlans: fitnessPlans ?? this.fitnessPlans,
    workoutSessions: workoutSessions ?? this.workoutSessions,
    workoutExercises: workoutExercises ?? this.workoutExercises,
    workoutSets: workoutSets ?? this.workoutSets,
    exercisePrs: exercisePrs ?? this.exercisePrs,
    budgetCategories: budgetCategories ?? this.budgetCategories,
    budgetEntries: budgetEntries ?? this.budgetEntries,
    transactions: transactions ?? this.transactions,
    aiHistory: aiHistory ?? this.aiHistory,
    dailyHabits: dailyHabits ?? this.dailyHabits,
    dailyHabitCompletions: habitCompletions ?? dailyHabitCompletions ?? this.dailyHabitCompletions,
    chores: chores ?? this.chores,
    choreCompletions: choreCompletions ?? this.choreCompletions,
    polls: polls ?? this.polls,
    pollVotes: pollVotes ?? this.pollVotes,
    rewardItems: rewardItems ?? this.rewardItems,
    rewards: rewards ?? this.rewards,
    rewardRedemptions: rewardRedemptions ?? this.rewardRedemptions,
    savingsGoals: savingsGoals ?? this.savingsGoals,
    prayerWall: prayerRequests ?? prayerWall ?? this.prayerWall,
    specialDates: occasions ?? specialDates ?? this.specialDates,
    familyPhotos: photos ?? familyPhotos ?? this.familyPhotos,
    milestones: milestones ?? this.milestones,
    savedPlaces: savedPlaces ?? this.savedPlaces,
    userLocations: locationShares ?? userLocations ?? this.userLocations,
    messages: messages ?? this.messages,
    healthRecords: healthRecords ?? this.healthRecords,
    periodCycles: periodEntries ?? periodCycles ?? this.periodCycles,
    periodSymptoms: periodSymptoms ?? this.periodSymptoms,
    notificationPrefs: notificationPrefs ?? this.notificationPrefs,
    readingPlans: readingPlans ?? this.readingPlans,
    readingPlanProgress: readingPlanProgress ?? this.readingPlanProgress,
    externalCalendars: externalCalendars ?? this.externalCalendars,
    pantryItems: pantryItems ?? this.pantryItems,
    familyActivityLogs: familyActivityLogs ?? this.familyActivityLogs,
    wellnessCheckIns: wellnessCheckIns ?? this.wellnessCheckIns,
  );

  /// After [FieldEncryption.init], re-decrypt rows that were parsed while the
  /// cipher was not ready (cloud pull / login order bugs).
  AppDB applySensitiveDecryption(String familyId) {
    if (!FieldEncryption.isReady(familyId)) return this;
    String ds(String? s) {
      if (s == null) return '';
      final d = FieldEncryption.decryptField(s, familyId);
      return d ?? s;
    }

    return copyWith(
      messages: messages.map((m) {
        if (m.familyId != familyId) return m;
        return ChatMessage(
          id: m.id,
          familyId: m.familyId,
          userId: m.userId,
          text: ds(m.text),
          replyToId: m.replyToId,
          reactions: m.reactions,
          editedAt: m.editedAt,
          createdAt: m.createdAt,
        );
      }).toList(),
      budgetCategories: budgetCategories.map((c) {
        if (c.familyId != familyId) return c;
        return BudgetCategoryRecord(
          id: c.id,
          familyId: c.familyId,
          creatorId: c.creatorId,
          name: ds(c.name),
          limit: c.limit,
          color: c.color,
          visibility: c.visibility,
          rolloverEnabled: c.rolloverEnabled,
          limitPeriod: c.limitPeriod,
        );
      }).toList(),
      budgetEntries: budgetEntries.map((e) {
        if (e.familyId != familyId) return e;
        return BudgetEntry(
          id: e.id,
          familyId: e.familyId,
          creatorId: e.creatorId,
          title: ds(e.title),
          amount: e.amount,
          type: e.type,
          category: e.category,
          date: e.date,
          notes: e.notes != null ? ds(e.notes) : null,
          visibility: e.visibility,
        );
      }).toList(),
      transactions: transactions.map((t) {
        if (t.familyId != familyId) return t;
        return Transaction(
          id: t.id,
          familyId: t.familyId,
          creatorId: t.creatorId,
          categoryId: t.categoryId,
          amount: t.amount,
          type: t.type,
          date: t.date,
          description: ds(t.description),
          visibility: t.visibility,
        );
      }).toList(),
      fitnessLogs: fitnessLogs.map((l) {
        if (l.familyId != familyId) return l;
        return FitnessLog(
          id: l.id,
          familyId: l.familyId,
          userId: l.userId,
          activity: ds(l.activity),
          durationMinutes: l.durationMinutes,
          caloriesBurned: l.caloriesBurned,
          notes: l.notes != null ? ds(l.notes) : null,
          date: l.date,
        );
      }).toList(),
      workoutSessions: workoutSessions.map((s) {
        if (s.familyId != familyId) return s;
        return WorkoutSession(
          id: s.id,
          familyId: s.familyId,
          userId: s.userId,
          title: ds(s.title),
          date: s.date,
          durationMinutes: s.durationMinutes,
          notes: s.notes != null ? ds(s.notes) : null,
          healthSyncedAt: s.healthSyncedAt,
          createdAt: s.createdAt,
        );
      }).toList(),
      workoutExercises: workoutExercises.map((e) {
        if (e.familyId != familyId) return e;
        return WorkoutExercise(
          id: e.id,
          familyId: e.familyId,
          userId: e.userId,
          sessionId: e.sessionId,
          exerciseName: ds(e.exerciseName),
          order: e.order,
          restSeconds: e.restSeconds,
          notes: e.notes != null ? ds(e.notes) : null,
          techniqueNotes:
              e.techniqueNotes != null ? ds(e.techniqueNotes) : null,
          referenceUrl:
              e.referenceUrl != null ? ds(e.referenceUrl) : null,
          techniqueImageUrl: e.techniqueImageUrl,
          exerciseDbId: e.exerciseDbId,
          createdAt: e.createdAt,
        );
      }).toList(),
      workoutSets: workoutSets.map((set) {
        if (set.familyId != familyId) return set;
        return WorkoutSet(
          id: set.id,
          familyId: set.familyId,
          userId: set.userId,
          exerciseId: set.exerciseId,
          setNumber: set.setNumber,
          reps: ds(set.reps),
          weight: set.weight != null ? ds(set.weight) : null,
          completed: set.completed,
          notes: set.notes != null ? ds(set.notes) : null,
          createdAt: set.createdAt,
        );
      }).toList(),
      savingsGoals: savingsGoals.map((g) {
        if (g.familyId != familyId) return g;
        return SavingsGoal(
          id: g.id,
          familyId: g.familyId,
          userId: g.userId,
          title: ds(g.title),
          icon: g.icon,
          imageUrl: g.imageUrl,
          targetAmount: g.targetAmount,
          savedAmount: g.savedAmount,
          createdAt: g.createdAt,
          completedAt: g.completedAt,
        );
      }).toList(),
      healthRecords: healthRecords.map((h) {
        if (h.familyId != familyId) return h;
        return HealthRecord(
          id: h.id,
          familyId: h.familyId,
          userId: h.memberId,
          updatedBy: h.updatedBy,
          bloodType: h.bloodType,
          allergies: h.allergies
              .map((a) => HealthAllergy(
                    id: a.id,
                    name: ds(a.name),
                    severity: a.severity,
                    reaction: a.reaction != null ? ds(a.reaction) : null,
                  ))
              .toList(),
          medications: h.medications
              .map((m) => HealthMedication(
                    id: m.id,
                    name: ds(m.name),
                    dose: m.dose != null ? ds(m.dose) : null,
                    frequency: m.frequency != null ? ds(m.frequency) : null,
                    startDate: m.startDate,
                  ))
              .toList(),
          conditions: h.conditions
              .map((c) => HealthCondition(
                    id: c.id,
                    name: ds(c.name),
                    diagnosedDate: c.diagnosedDate,
                    notes: c.notes != null ? ds(c.notes) : null,
                  ))
              .toList(),
          immunizations: h.immunizations
              .map((i) => HealthImmunization(
                    id: i.id,
                    name: ds(i.name),
                    date: i.date,
                    nextDue: i.nextDue,
                  ))
              .toList(),
          emergencyContacts: h.emergencyContacts
              .map((e) => EmergencyContact(
                    id: e.id,
                    name: ds(e.name),
                    phone: ds(e.phone),
                    relation: e.relation != null ? ds(e.relation) : null,
                  ))
              .toList(),
          doctorName: h.doctorName != null ? ds(h.doctorName) : null,
          doctorPhone: h.doctorPhone != null ? ds(h.doctorPhone) : null,
          insuranceProvider:
              h.insuranceProvider != null ? ds(h.insuranceProvider) : null,
          insurancePolicyNumber:
              h.insurancePolicyNumber != null ? ds(h.insurancePolicyNumber) : null,
          notes: h.notes != null ? ds(h.notes) : null,
          updatedAt: h.updatedAt,
          type: h.type,
          title: h.title,
          data: h.data,
        );
      }).toList(),
      periodCycles: periodCycles.map((p) {
        if (p.familyId != familyId) return p;
        return PeriodCycle(
          id: p.id,
          userId: p.userId,
          familyId: p.familyId,
          startDate: p.startDate,
          endDate: p.endDate,
          flowLevel: p.flowLevel,
          notes: p.notes != null ? ds(p.notes) : null,
          createdAt: p.createdAt,
        );
      }).toList(),
      periodSymptoms: periodSymptoms.map((p) {
        if (p.familyId != familyId) return p;
        return PeriodSymptomLog(
          id: p.id,
          userId: p.userId,
          familyId: p.familyId,
          date: p.date,
          symptoms: p.symptoms.map((s) => ds(s)).toList(),
          mood: p.mood,
          painLevel: p.painLevel,
          notes: p.notes != null ? ds(p.notes) : null,
          createdAt: p.createdAt,
        );
      }).toList(),
    );
  }

  // Convenience alias getters for screen compatibility
  List<PrayerWallEntry> get prayerRequests => prayerWall;
  List<PeriodCycle> get periodEntries => periodCycles;
  List<SpecialDate> get occasions => specialDates;
  List<FamilyPhoto> get photos => familyPhotos;
  List<UserLocation> get locationShares => userLocations;
  List<DailyHabitCompletion> get habitCompletions => dailyHabitCompletions;
  List<DevotionalEntry> get devotionalEntries => devotionals;
  List<ShoppingList> get shoppingLists => lists;
}
