// lib/screens/dashboard/dashboard_screen.dart
// Home dashboard screen for FamilyHub — matches Vite app design

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/subscription_modal.dart';

// ─── AI Suggestion model ─────────────────────────────────────────────────────

class _AISuggestion {
  final IconData icon;
  final String title;
  final String description;
  final String? reasoning;
  final String? timeEstimate;
  final String? route;

  const _AISuggestion({
    required this.icon,
    required this.title,
    required this.description,
    this.reasoning,
    this.timeEstimate,
    this.route,
  });
}

class _TryAIFeature {
  final IconData icon;
  final String label;
  final String description;
  final String route;
  final Color color;

  const _TryAIFeature({
    required this.icon,
    required this.label,
    required this.description,
    required this.route,
    required this.color,
  });
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.color, this.onTap);
}

// ─── Dashboard Screen ────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _dismissedAnnouncement;
  List<_AISuggestion> _suggestions = [];
  bool _suggestionsLoading = true;
  bool _suggestionsLoaded = false;

  // Monthly Summary
  Map<String, dynamic>? _monthlySummary;
  bool _monthlySummaryLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDismissedAnnouncement();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAISuggestions());
  }

  Future<void> _loadDismissedAnnouncement() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = context.read<AppProvider>().activeFamily?.id;
    if (familyId == null) return;
    final dismissed = prefs.getString('dismissed_announcement_$familyId');
    if (mounted) setState(() => _dismissedAnnouncement = dismissed);
  }

  Future<void> _dismissAnnouncement(String announcement, String familyId) async {
    setState(() => _dismissedAnnouncement = announcement);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dismissed_announcement_$familyId', announcement);
  }

  Future<void> _onRefresh() async {
    final provider = context.read<AppProvider>();
    await provider.saveAndSync(provider.db);
    await _loadAISuggestions();
  }

  Future<void> _loadMonthlySummary() async {
    if (AiService.isAIBlocked) return;
    if (_monthlySummaryLoading) return;
    setState(() => _monthlySummaryLoading = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final family = provider.activeFamily;
    if (family == null) {
      if (mounted) setState(() => _monthlySummaryLoading = false);
      return;
    }
    final familyId = family.id;
    final familyName = family.name ?? 'Family';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthName = DateFormat('MMMM yyyy').format(now);

    // Gather monthly stats
    final tasksCreated = db.tasks.where((t) => t.familyId == familyId && t.dueDate != null && t.dueDate!.isAfter(monthStart)).length;
    final tasksCompleted = db.tasks.where((t) => t.familyId == familyId && t.dueDate != null && t.dueDate!.isAfter(monthStart) && t.completed).length;
    final mealsPlanned = db.mealPlans.where((m) => m.familyId == familyId && m.date.isAfter(monthStart)).length;
    final devotionals = db.devotionalEntries.where((d) => d.familyId == familyId && d.date.isAfter(monthStart)).length;
    final workouts = db.fitnessLogs.where((f) => f.familyId == familyId && f.date.isAfter(monthStart)).length;

    final budgetEntries = db.budgetEntries.where((e) => e.familyId == familyId && e.date.isAfter(monthStart)).toList();
    final income = budgetEntries.where((e) => e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final expenses = budgetEntries.where((e) => !e.isIncome).fold<double>(0, (s, e) => s + e.amount);

    final prompt = '''
You are a warm, encouraging family assistant for a Christian family app. Always respond with valid JSON only, no markdown fences.

Generate a monthly recap for the $familyName family for $monthName.

Data:
- Tasks: $tasksCompleted completed out of $tasksCreated created
- Meals Planned: $mealsPlanned
- Devotionals Shared: $devotionals
- Workouts Logged: $workouts
- Budget: \$${income.toStringAsFixed(0)} income / \$${expenses.toStringAsFixed(0)} expenses

Return a JSON object:
{
  "headline": "string (catchy summary)",
  "highlights": [{"icon": "emoji", "text": "string"}],
  "encouragement": "string (celebrating progress)",
  "faithNote": "string (scripture or prayer)",
  "topAchievement": "string",
  "areasToFocus": ["string", "string"]
}
''';

    try {
      final raw = await AiService.ask(prompt: prompt, feature: 'ai_motivation', familyId: familyId);
      if (raw == null || !mounted) {
        if (mounted) setState(() => _monthlySummaryLoading = false);
        return;
      }
      provider.saveAiHistory(module: 'dashboard', prompt: 'Generate monthly family summary', response: raw);
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(cleaned.indexOf('\n') + 1);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.lastIndexOf('```'));
      cleaned = cleaned.trim();

      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        setState(() { _monthlySummary = decoded; _monthlySummaryLoading = false; });
      } else {
        setState(() => _monthlySummaryLoading = false);
      }
    } catch (e) {
      debugPrint('[Dashboard] monthly summary error: $e');
      if (mounted) setState(() => _monthlySummaryLoading = false);
    }
  }

  Future<void> _loadAISuggestions() async {
    if (AiService.isAIBlocked) return;
    if (!mounted) return;
    setState(() => _suggestionsLoading = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) {
      setState(() {
        _suggestionsLoading = false;
        _suggestions = _generateLocalSuggestions(db, family?.id ?? '');
        _suggestionsLoaded = true;
      });
      return;
    }

    final familyId = family.id;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Build context for the AI
    final tasksDue = db.tasks.where((t) => t.familyId == familyId && !t.completed && t.dueDate != null && _isSameDay(t.dueDate!, today)).length;
    final overdue = db.tasks.where((t) => t.familyId == familyId && !t.completed && t.dueDate != null && t.dueDate!.isBefore(today)).length;
    final chores = db.chores.where((c) => c.familyId == familyId).length;
    final meals = db.mealPlans.where((m) => m.familyId == familyId && _isSameDay(m.date, today)).toList();
    final mealsPlanned = meals.map((m) => m.mealType).toSet();
    final upcomingEvents = db.events.where((e) => e.familyId == familyId && !e.startDate.isBefore(today) && e.startDate.isBefore(today.add(const Duration(days: 3)))).toList();
    final habits = db.dailyHabits.where((h) => h.familyId == familyId).length;
    final habitsCompleted = db.dailyHabitCompletions.where((c) => _isSameDay(c.date, today)).length;

    final contextStr = '''
Family: ${family.name}
Today: ${DateFormat('EEEE, MMMM d').format(now)}
Tasks due today: $tasksDue, Overdue: $overdue
Chores: $chores total
Meals planned today: ${mealsPlanned.join(', ')} (missing: ${['breakfast', 'lunch', 'dinner'].where((m) => !mealsPlanned.contains(m)).join(', ')})
Upcoming events (3 days): ${upcomingEvents.map((e) => '${e.title} on ${DateFormat('EEE').format(e.startDate)}').join(', ')}
Habits: $habitsCompleted/$habits completed today
Prayer wall entries: ${db.prayerWall.where((p) => p.familyId == familyId).length}
Active lists: ${db.lists.where((l) => l.familyId == familyId).length}
''';

    try {
      final raw = await AiService.ask(
        prompt: '''You are a helpful family assistant AI. Give practical, encouraging suggestions based on the family data. Respond with valid JSON only.

Based on this family's current data, generate 3 personalized, actionable suggestions to help them today. Each suggestion should be helpful and specific.

$contextStr

Respond with a JSON array of objects, each with:
- "icon": one of "task", "meal", "calendar", "fitness", "budget", "prayer", "habit", "chore", "list"
- "title": short action title (5-8 words)
- "description": one sentence describing the suggestion
- "reasoning": brief explanation of why this is suggested
- "timeEstimate": estimated time like "5 min", "15 min", "30 min"
- "route": app route like "/tasks", "/meals", "/calendar", "/fitness", "/budget", "/prayer-wall", "/chores", "/lists"

Return ONLY the JSON array, no markdown.''',
        feature: 'ai_motivation',
        familyId: familyId,
      );

      if (raw != null && mounted) {
        provider.saveAiHistory(module: 'dashboard', prompt: 'Generate daily AI suggestions', response: raw);
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            setState(() {
              _suggestions = decoded.map((s) {
                final map = s as Map<String, dynamic>;
                return _AISuggestion(
                  icon: _iconFromString(map['icon'] as String? ?? 'task'),
                  title: map['title'] as String? ?? '',
                  description: map['description'] as String? ?? '',
                  reasoning: map['reasoning'] as String?,
                  timeEstimate: map['timeEstimate'] as String?,
                  route: map['route'] as String?,
                );
              }).toList();
              _suggestionsLoading = false;
              _suggestionsLoaded = true;
            });
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}

    // Fallback to local suggestions
    if (mounted) {
      setState(() {
        _suggestions = _generateLocalSuggestions(db, familyId);
        _suggestionsLoading = false;
        _suggestionsLoaded = true;
      });
    }
  }

  List<_AISuggestion> _generateLocalSuggestions(AppDB db, String familyId) {
    final suggestions = <_AISuggestion>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final overdue = db.tasks.where((t) => t.familyId == familyId && !t.completed && t.dueDate != null && t.dueDate!.isBefore(today)).length;
    if (overdue > 0) {
      suggestions.add(_AISuggestion(
        icon: Icons.warning_amber_rounded,
        title: 'Tackle $overdue overdue task${overdue > 1 ? 's' : ''}',
        description: 'Clear your overdue items to stay on track.',
        reasoning: 'You have tasks past their due date that need attention.',
        timeEstimate: '${overdue * 10} min',
        route: '/tasks',
      ));
    }

    final mealsPlanned = db.mealPlans.where((m) => m.familyId == familyId && _isSameDay(m.date, today)).map((m) => m.mealType).toSet();
    final missing = ['breakfast', 'lunch', 'dinner'].where((m) => !mealsPlanned.contains(m)).toList();
    if (missing.isNotEmpty) {
      suggestions.add(_AISuggestion(
        icon: Icons.restaurant_rounded,
        title: 'Plan ${missing.first} for today',
        description: 'You haven\'t planned ${missing.join(' or ')} yet.',
        reasoning: 'Meal planning reduces stress and saves money.',
        timeEstimate: '5 min',
        route: '/meals',
      ));
    }

    final habits = db.dailyHabits.where((h) => h.familyId == familyId).length;
    final habitsCompleted = db.dailyHabitCompletions.where((c) => _isSameDay(c.date, today)).length;
    if (habits > 0 && habitsCompleted < habits) {
      suggestions.add(_AISuggestion(
        icon: Icons.radio_button_checked_rounded,
        title: 'Complete your daily habits',
        description: '$habitsCompleted of $habits habits done. Keep the streak going!',
        reasoning: 'Consistency builds lasting habits.',
        timeEstimate: '10 min',
        route: '/tasks',
      ));
    }

    if (suggestions.isEmpty) {
      suggestions.add(const _AISuggestion(
        icon: Icons.celebration_rounded,
        title: 'You\'re all caught up!',
        description: 'Great job staying on top of things. Enjoy your day!',
        reasoning: 'No urgent items need your attention right now.',
      ));
    }

    return suggestions.take(3).toList();
  }

  static IconData _iconFromString(String name) {
    switch (name) {
      case 'meal': return Icons.restaurant_rounded;
      case 'calendar': return Icons.calendar_today_rounded;
      case 'fitness': return Icons.fitness_center_rounded;
      case 'budget': return Icons.account_balance_wallet_rounded;
      case 'prayer': return Icons.favorite_rounded;
      case 'habit': return Icons.radio_button_checked_rounded;
      case 'chore': return Icons.assignment_turned_in_rounded;
      case 'list': return Icons.checklist_rounded;
      default: return Icons.check_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final user = provider.activeUser;
        final family = provider.activeFamily;

        if (user == null || family == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final db = provider.db;
        final familyId = family.id;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        // ── Data queries ──────────────────────────────────────────────
        final tasksDueToday = db.tasks
            .where((t) =>
                t.familyId == familyId &&
                !t.completed &&
                t.dueDate != null &&
                _isSameDay(t.dueDate!, today))
            .toList();

        final overdueTasks = db.tasks
            .where((t) =>
                t.familyId == familyId &&
                !t.completed &&
                t.dueDate != null &&
                t.dueDate!.isBefore(today))
            .toList();

        final todayFocusTasks = [...tasksDueToday, ...overdueTasks];

        final weekEnd = today.add(const Duration(days: 7));
        final upcomingEvents = db.events
            .where((e) =>
                e.familyId == familyId &&
                !e.startDate.isBefore(today) &&
                e.startDate.isBefore(weekEnd))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        final choresToday = db.chores
            .where((c) => c.familyId == familyId)
            .toList();
        final choresCompletedToday = choresToday
            .where((c) =>
                c.lastCompletedAt != null &&
                _isSameDay(c.lastCompletedAt!, today))
            .length;

        final monthStart = DateTime(now.year, now.month, 1);
        final eventsThisMonth = db.events
            .where((e) =>
                e.familyId == familyId &&
                !e.startDate.isBefore(monthStart))
            .length;
        final spentThisMonth = db.budgetEntries
            .where((e) =>
                e.familyId == familyId &&
                e.type == TransactionType.EXPENSE &&
                !e.date.isBefore(monthStart))
            .fold<double>(0, (sum, e) => sum + e.amount);

        final habitsToday = db.dailyHabits
            .where((h) => h.familyId == familyId)
            .toList();
        final habitsCompletedToday = db.dailyHabitCompletions
            .where((c) => _isSameDay(c.date, today))
            .length;

        final activeLists = db.lists
            .where((l) => l.familyId == familyId)
            .toList();

        final todayMealPlans = db.mealPlans
            .where((m) =>
                m.familyId == familyId &&
                _isSameDay(m.date, today))
            .toList();

        final todayDevotional = db.devotionals
            .where((d) => d.familyId == familyId)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        final readingPlans = db.readingPlans
            .where((r) => r.familyId == familyId)
            .toList();

        final recentPrayer = db.prayerWall
            .where((p) => p.familyId == familyId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final recentFitness = db.fitness
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        final openPolls = db.polls
            .where((p) =>
                p.familyId == familyId && p.status == PollStatus.open)
            .toList();

        // Check if current user is a restricted (kid) member
        final userMembership = db.familyMembers
            .where((m) => m.userId == user.id && m.familyId == familyId)
            .toList();
        final isRestricted = userMembership.isNotEmpty &&
            userMembership.first.moduleAccess != null &&
            userMembership.first.moduleAccess!.isNotEmpty;

        // Find switchable kids (for parent view)
        final switchableKids = db.familyMembers
            .where((m) =>
                m.familyId == familyId &&
                m.userId != user.id &&
                m.moduleAccess != null &&
                m.moduleAccess!.isNotEmpty)
            .map((m) => db.users.where((u) => u.id == m.userId).toList())
            .where((u) => u.isNotEmpty)
            .map((u) => u.first)
            .toList();

        if (isRestricted) {
          return _buildKidsDashboard(context, provider, user, family, db, familyId, today, choresToday, choresCompletedToday, todayMealPlans, tasksDueToday);
        }

        return Scaffold(
          drawer: const AppDrawer(),
          backgroundColor: AppTheme.background,
          appBar: const FamilyHubAppBar(),
          body: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primary,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildHeroSection(family),
                _buildTrialBanner(context, family),
                _buildActionButtons(context),
                _buildAnnouncementSection(context, provider, family),
                if (!family.welcomeDismissed)
                  _buildTryAICard(context, provider, family),
                _buildBirthdaysSection(db, familyId, today),
                _buildAISuggestionsSection(),
                _buildMonthlySummarySection(),
                _buildStatsGrid(
                  tasksDue: tasksDueToday.length,
                  choresCompleted: choresCompletedToday,
                  choresTotal: choresToday.length,
                  eventsThisMonth: eventsThisMonth,
                  spentThisMonth: spentThisMonth,
                  habitsCompleted: habitsCompletedToday,
                  habitsTotal: habitsToday.length,
                ),
                _buildEventCountdown(context, upcomingEvents),
                _buildRecapCard(now),
                _buildTodayFocus(context, todayFocusTasks, overdueTasks, provider),
                _buildUpcomingEvents(context, upcomingEvents),
                _buildActiveLists(context, activeLists),
                _buildBudgetSnapshot(context, db, familyId, monthStart),
                _buildPointsLeaderboard(db, familyId),
                _buildTodayMeals(context, todayMealPlans),
                _buildTodayChores(context, choresToday, choresCompletedToday),
                _buildDevotional(context, todayDevotional),
                _buildReadingPlan(context, readingPlans),
                _buildPrayerWall(context, recentPrayer),
                _buildFitness(context, recentFitness),
                _buildOpenPolls(context, openPolls),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Builder methods
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Kids Dashboard (restricted member view) ────────────────────────────────

  Widget _buildKidsDashboard(
    BuildContext context,
    AppProvider provider,
    User user,
    Family family,
    AppDB db,
    String familyId,
    DateTime today,
    List<Chore> choresToday,
    int choresCompletedToday,
    List<MealPlanEntry> todayMealPlans,
    List<Task> tasksDueToday,
  ) {
    final dayName = DateFormat('EEEE').format(today);
    final monthDay = DateFormat('MMMM d').format(today);
    final firstName = user.name.split(' ').first;

    // Calculate kid's points from approved chore completions
    final approvedCompletions = db.choreCompletions.where((cc) =>
      cc.familyId == familyId &&
      cc.userId == user.id &&
      cc.approvalStatus == ApprovalStatus.APPROVED
    ).toList();
    final totalPoints = approvedCompletions.fold<int>(0, (sum, cc) {
      final chore = db.chores.where((c) => c.id == cc.choreId).toList();
      return sum + (chore.isNotEmpty ? chore.first.points : 0);
    });

    // Kid's chores (assigned to them or unassigned)
    final myChores = choresToday.where((c) =>
      c.assignees.isEmpty || c.assignees.contains(user.id)
    ).toList();
    final todayCompletions = db.choreCompletions.where((cc) =>
      cc.familyId == familyId && cc.userId == user.id && _isSameDay(cc.date, today)
    ).toList();
    final completedChoreIds = todayCompletions.map((cc) => cc.choreId).toSet();
    final myChoresCompleted = myChores.where((c) => completedChoreIds.contains(c.id)).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(String.fromCharCode(0x2728), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
        ]),
        centerTitle: false,
        actions: [
          if (provider.isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Greeting
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hey $firstName! \u{1F44B}', style: const TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.stone900)),
                const SizedBox(height: 4),
                Text("It's $dayName, $monthDay. Here's your day.", style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500)),
              ]),
            ),
            const SizedBox(height: 20),

            // Quick Stats Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(child: _kidStatCard('Chores Done', '$myChoresCompleted/${myChores.length}', Icons.assignment_turned_in_rounded, const Color(0xFF16A34A))),
                const SizedBox(width: 10),
                Expanded(child: _kidStatCard('Tasks Due', '${tasksDueToday.length}', Icons.check_circle_outline_rounded, const Color(0xFF2563EB))),
                const SizedBox(width: 10),
                Expanded(child: _kidStatCard('Reward Pts', '$totalPoints', Icons.star_rounded, const Color(0xFFD97706))),
              ]),
            ),
            const SizedBox(height: 20),

            // My Chores Today
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.cleaning_services_rounded, size: 20, color: Color(0xFF16A34A)),
                    SizedBox(width: 8),
                    Text('My Chores Today', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.stone900)),
                  ]),
                  const SizedBox(height: 12),
                  if (myChores.isEmpty)
                    const Text('No chores today! Enjoy your free time.', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500))
                  else
                    ...myChores.map((chore) {
                      final isDone = completedChoreIds.contains(chore.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: isDone ? null : () async {
                            HapticFeedback.mediumImpact();
                            final completion = ChoreCompletion(
                              id: const Uuid().v4(),
                              choreId: chore.id,
                              userId: user.id,
                              familyId: familyId,
                              date: today,
                              completedAt: DateTime.now(),
                            );
                            await provider.saveAndSync(db.copyWith(
                              choreCompletions: [...db.choreCompletions, completion],
                            ));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDone ? const Color(0xFFDCFCE7) : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDone ? const Color(0xFF86EFAC) : AppTheme.stone100),
                            ),
                            child: Row(children: [
                              Container(
                                width: 24, height: 24,
                                decoration: BoxDecoration(
                                  color: isDone ? const Color(0xFF16A34A) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isDone ? const Color(0xFF16A34A) : AppTheme.stone300, width: 2),
                                ),
                                child: isDone ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  chore.title,
                                  style: TextStyle(
                                    fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600,
                                    color: isDone ? AppTheme.stone400 : AppTheme.stone800,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                              if (chore.points > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                                  child: Text('${chore.points} pts', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                                ),
                            ]),
                          ),
                        ),
                      );
                    }),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Today's Meals
            _buildTodayMeals(context, todayMealPlans),

            // Today's Tasks
            _buildTodayFocus(context, tasksDueToday, const [], provider),

            // Kid account switcher — show other kids
            Builder(builder: (_) {
              final otherKids = db.familyMembers
                  .where((m) =>
                      m.familyId == familyId &&
                      m.userId != user.id &&
                      m.moduleAccess != null &&
                      m.moduleAccess!.isNotEmpty)
                  .map((m) => db.users.where((u) => u.id == m.userId).toList())
                  .where((u) => u.isNotEmpty)
                  .map((u) => u.first)
                  .toList();
              if (otherKids.isEmpty) return const SizedBox.shrink();
              return _buildKidSwitcher(context, provider, otherKids, family);
            }),
          ],
        ),
      ),
    );
  }

  Widget _kidStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
      ]),
    );
  }

  // ── Kid Switcher ───────────────────────────────────────────────────────────

  Widget _buildKidSwitcher(BuildContext context, AppProvider provider, List<User> kids, Family family) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFF2563EB)),
            SizedBox(width: 6),
            Text('Switch Account', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF2563EB))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: kids.map((kid) {
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                provider.switchActiveUser(kid);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(kid.name.split(' ').first, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone700)),
                ]),
              ),
            );
          }).toList()),
        ]),
      ),
    );
  }

  Widget _buildHeroSection(Family family) {
    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now);
    final monthDay = DateFormat('MMMM d').format(now);
    final day = now.day;
    String suffix = 'th';
    if (day % 100 < 11 || day % 100 > 13) {
      switch (day % 10) {
        case 1: suffix = 'st'; break;
        case 2: suffix = 'nd'; break;
        case 3: suffix = 'rd'; break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hey ${family.name}!',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.stone900),
          ),
          const SizedBox(height: 4),
          Text(
            "It's $dayName, $monthDay$suffix. Here's your family at a glance.",
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialBanner(BuildContext context, Family family) {
    if (family.subscriptionTier != SubscriptionTier.trial) return const SizedBox.shrink();
    final expired = family.isTrialExpired;
    final daysLeft = family.trialDaysRemaining;
    // Only show when 7 days or less remaining, or expired
    if (!expired && daysLeft > 7) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: () => context.go('/subscription'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: expired
                  ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
                  : [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(expired ? Icons.lock_rounded : Icons.timer_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  expired
                      ? 'Trial expired — tap to upgrade and unlock all features'
                      : '$daysLeft day${daysLeft == 1 ? '' : 's'} left in your free trial — tap to view plans',
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final actions = [
      _QuickAction(Icons.add_rounded, 'Add Task', const Color(0xFF6366F1), () => context.go('/tasks')),
      _QuickAction(Icons.restaurant_rounded, 'Meal Plan', const Color(0xFF10B981), () => context.go('/meals')),
      _QuickAction(Icons.shopping_cart_rounded, 'Shopping', const Color(0xFF0EA5E9), () => context.go('/lists')),
      _QuickAction(Icons.event_rounded, 'New Event', const Color(0xFFF59E0B), () => context.go('/calendar')),
      _QuickAction(Icons.menu_book_rounded, 'Devotional', const Color(0xFF8B5CF6), () => context.go('/devotional')),
      _QuickAction(Icons.trending_up_rounded, 'Finances', const Color(0xFF16A34A), () => context.go('/budget')),
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final a = actions[i];
          return GestureDetector(
            onTap: () { HapticFeedback.lightImpact(); a.onTap(); },
            child: SizedBox(
              width: 68,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: a.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(a.icon, size: 22, color: a.color),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.label,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone600),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnnouncementSection(BuildContext context, AppProvider provider, Family family) {
    final hasAnnouncement = family.announcement != null && family.announcement!.isNotEmpty && family.announcement != _dismissedAnnouncement;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GestureDetector(
        onTap: () => _editAnnouncement(context, provider, family),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hasAnnouncement ? AppTheme.stone100 : AppTheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(Icons.campaign_outlined, color: hasAnnouncement ? AppTheme.stone500 : AppTheme.stone400, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasAnnouncement ? family.announcement! : 'Pin a family announcement here...',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: hasAnnouncement ? AppTheme.stone700 : AppTheme.stone400),
              ),
            ),
            if (hasAnnouncement)
              GestureDetector(
                onTap: () { HapticFeedback.lightImpact(); _dismissAnnouncement(family.announcement!, family.id); },
                child: const Icon(Icons.close, size: 16, color: AppTheme.stone400),
              )
            else
              Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  Future<void> _editAnnouncement(BuildContext context, AppProvider provider, Family family) async {
    final controller = TextEditingController(text: family.announcement ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Family Announcement'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Type a family announcement...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          if (family.announcement != null && family.announcement!.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: Text('Clear', style: TextStyle(color: Colors.red.shade400)),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return; // cancelled

    final user = provider.activeUser;
    final authorName = user?.name ?? 'Someone';
    // copyWith uses ?? so null means "keep old value".
    // Use empty string to clear; the display treats empty as no announcement.
    final updated = family.copyWith(
      announcement: result.isEmpty ? '' : result,
      announcementAuthor: result.isEmpty ? '' : authorName,
    );
    provider.updateFamily(updated);
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      families: db.families.map((f) => f.id == updated.id ? updated : f).toList(),
    ));
    // Clear dismiss state if the announcement changed
    if (result.isNotEmpty) {
      setState(() => _dismissedAnnouncement = null);
    }
  }

  // ── Try AI Onboarding Card ──────────────────────────────────────────────

  Widget _buildTryAICard(BuildContext context, AppProvider provider, Family family) {
    final features = [
      _TryAIFeature(
        icon: Icons.auto_awesome_rounded,
        label: 'Daily Devotional',
        description: 'AI-generated family devotionals with scripture & prayer',
        route: '/devotional',
        color: const Color(0xFFF59E0B), // amber
      ),
      _TryAIFeature(
        icon: Icons.restaurant_rounded,
        label: 'Meal Planner',
        description: 'Generate a full week of meals tailored to your family',
        route: '/meals',
        color: const Color(0xFF10B981), // emerald
      ),
      _TryAIFeature(
        icon: Icons.checklist_rounded,
        label: 'Task Breakdown',
        description: 'Turn big goals into bite-sized tasks with AI',
        route: '/tasks',
        color: AppTheme.primary,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Try our AI-powered features',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    onPressed: () {
                      final updated = family.copyWith(welcomeDismissed: true);
                      final db = provider.db;
                      provider.updateFamily(updated);
                      provider.saveAndSync(db.copyWith(
                        families: db.families.map((f) => f.id == updated.id ? updated : f).toList(),
                      ));
                    },
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Tap a feature below to get started',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
              ),
            ),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: features.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final f = features[i];
                  return GestureDetector(
                    onTap: () => context.push(f.route),
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: f.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(f.icon, color: Colors.white, size: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            f.label,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              f.description,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10.5,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI Suggestions Section ────────────────────────────────────────────────

  Widget _buildAISuggestionsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xFFD97706), size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Suggestions', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF92400E))),
                  Text('Powered by Gemini', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFD97706))),
                ],
              )),
              GestureDetector(
                onTap: _loadAISuggestions,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded, size: 13, color: const Color(0xFFD97706).withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text('Refresh', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFD97706).withValues(alpha: 0.8))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // Suggestions or loading
            if (_suggestionsLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFFD97706).withValues(alpha: 0.5)))),
                  const SizedBox(width: 10),
                  const Text('Gemini is analysing your family data...', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Color(0xFFB45309))),
                ]),
              )
            else
              ..._suggestions.asMap().entries.map((entry) {
                final idx = entry.key;
                final s = entry.value;
                return Padding(
                  padding: EdgeInsets.only(top: idx > 0 ? 10 : 0),
                  child: _buildSuggestionCard(s),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(_AISuggestion s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(s.icon, size: 16, color: const Color(0xFFD97706)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                if (s.timeEstimate != null)
                  Text(s.timeEstimate!, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFFD97706))),
              ],
            )),
            if (s.route != null)
              GestureDetector(
                onTap: () => context.go(s.route!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Go \u2192', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text(s.description, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF78350F), height: 1.4)),
          if (s.reasoning != null) ...[
            const SizedBox(height: 4),
            Text(s.reasoning!, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFFB45309))),
          ],
        ],
      ),
    );
  }

  // ── Monthly Summary Section ─────────────────────────────────────────────────

  Widget _buildMonthlySummarySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.insights_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(child: Text('Monthly Summary', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white))),
              if (_monthlySummary == null)
                GestureDetector(
                  onTap: _monthlySummaryLoading ? null : () { HapticFeedback.lightImpact(); _loadMonthlySummary(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                    child: _monthlySummaryLoading
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Generate', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                  ),
                ),
            ]),
            if (_monthlySummary != null) ...[
              const SizedBox(height: 12),
              Text(_monthlySummary!['headline']?.toString() ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
              const SizedBox(height: 10),
              if (_monthlySummary!['highlights'] is List)
                ...(_monthlySummary!['highlights'] as List).map((h) {
                  final icon = h is Map ? (h['icon']?.toString() ?? '') : '';
                  final text = h is Map ? (h['text']?.toString() ?? '') : h.toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$icon ', style: const TextStyle(fontSize: 14)),
                      Expanded(child: Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70))),
                    ]),
                  );
                }),
              if (_monthlySummary!['encouragement'] != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text(_monthlySummary!['encouragement'].toString(), style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white, fontStyle: FontStyle.italic)),
                ),
              ],
              if (_monthlySummary!['faithNote'] != null) ...[
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('\u{1F4D6} ', style: TextStyle(fontSize: 14)),
                  Expanded(child: Text(_monthlySummary!['faithNote'].toString(), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white60))),
                ]),
              ],
              if (_monthlySummary!['areasToFocus'] is List) ...[
                const SizedBox(height: 8),
                const Text('Focus Areas', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 4),
                ...(_monthlySummary!['areasToFocus'] as List).map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    Container(width: 5, height: 5, margin: const EdgeInsets.only(right: 8), decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle)),
                    Expanded(child: Text(a.toString(), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70))),
                  ]),
                )),
              ],
            ] else if (!_monthlySummaryLoading)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Tap Generate for an AI-powered recap of your family\'s month.', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white60)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid({
    required int tasksDue,
    required int choresCompleted,
    required int choresTotal,
    required int eventsThisMonth,
    required double spentThisMonth,
    required int habitsCompleted,
    required int habitsTotal,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(children: [
        Row(children: [
          Expanded(child: _miniStatCard(Icons.check_box_outlined, const Color(0xFF0D9488), tasksDue.toString(), 'Tasks Due')),
          const SizedBox(width: 10),
          Expanded(child: _miniStatCard(Icons.assignment_outlined, const Color(0xFFF59E0B), '$choresCompleted/$choresTotal', 'Chores Today')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _miniStatCard(Icons.calendar_today_outlined, AppTheme.primary, eventsThisMonth.toString(), 'Events This Month')),
          const SizedBox(width: 10),
          Expanded(child: _miniStatCard(Icons.account_balance_wallet_outlined, const Color(0xFFEC4899), '\$${spentThisMonth.toStringAsFixed(0)}', 'Spent This Month')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _miniStatCard(Icons.radio_button_checked_outlined, const Color(0xFF8B5CF6), '$habitsCompleted/$habitsTotal', 'Habits Today', progress: habitsTotal > 0 ? habitsCompleted / habitsTotal : 0)),
          const SizedBox(width: 10),
          const Expanded(child: SizedBox()),
        ]),
      ]),
    );
  }

  Widget _miniStatCard(IconData icon, Color color, String value, String label, {double? progress}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            if (progress != null) ...[
              const Spacer(),
              Text('${(progress * 100).toInt()}%', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ],
          ]),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.stone900)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500)),
        ],
      ),
    );
  }

  Widget _buildRecapCard(DateTime now) {
    final monthName = DateFormat('MMMM').format(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF6366F1)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$monthName Family Recap', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
              const Text('See how your month is going', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
            ],
          )),
          GestureDetector(
            onTap: _monthlySummaryLoading ? null : () { HapticFeedback.lightImpact(); _loadMonthlySummary(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: _monthlySummaryLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Generate\nRecap', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTodayFocus(BuildContext context, List<Task> tasks, List<Task> overdueTasks, AppProvider provider) {
    return _dashSection(
      title: "Today's Focus",
      actionLabel: 'View all',
      onAction: () => context.go('/tasks'),
      child: tasks.isEmpty
          ? const Text('All caught up! No tasks due today.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400))
          : Column(children: tasks.take(5).map((task) {
              final isOverdue = overdueTasks.contains(task);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: isOverdue ? AppTheme.error : AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                      if (task.notes != null && task.notes!.isNotEmpty)
                        Text(task.notes!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                    ],
                  )),
                  Text(
                    isOverdue ? 'Overdue' : 'Today',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: isOverdue ? AppTheme.error : AppTheme.stone400),
                  ),
                ]),
              );
            }).toList()),
    );
  }

  Widget _buildUpcomingEvents(BuildContext context, List<CalendarEvent> events) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF7C3AED)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Upcoming Events', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white))),
            GestureDetector(
              onTap: () => context.go('/calendar'),
              child: const Text('Full Schedule', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white70)),
            ),
          ]),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text('No events on the horizon.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontStyle: FontStyle.italic, color: Colors.white.withValues(alpha: 0.7)))
          else
            ...events.take(3).map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(DateFormat('EEE d').format(e.startDate), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                const SizedBox(width: 12),
                Expanded(child: Text(e.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white))),
                if (!e.allDay) Text(DateFormat('h:mm a').format(e.startDate), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white70)),
              ]),
            )),
        ],
      ),
    );
  }

  Widget _buildActiveLists(BuildContext context, List<ShoppingList> lists) {
    if (lists.isEmpty) return const SizedBox.shrink();
    return _dashSection(
      title: 'Active Lists',
      actionLabel: 'All lists',
      onAction: () => context.go('/lists'),
      child: Column(children: lists.take(3).map((l) {
        final total = l.items.length;
        final done = l.items.where((i) => i.checked).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Text(l.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800))),
            Text('$done/$total', style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
          ]),
        );
      }).toList()),
    );
  }

  // _buildBudgetSection removed — replaced by _buildBudgetSnapshot above

  Widget _buildTodayMeals(BuildContext context, List<MealPlanEntry> meals) {
    // mealType is a lowercase String: 'breakfast', 'lunch', 'dinner'
    final breakfast = meals.where((m) => m.mealType == 'breakfast').toList();
    final lunch = meals.where((m) => m.mealType == 'lunch').toList();
    final dinner = meals.where((m) => m.mealType == 'dinner').toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text("Today's Meals", style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF166534))),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/meals'),
              child: const Text('Plan >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF16A34A))),
            ),
          ]),
          const SizedBox(height: 12),
          _mealRow('BREAKFAST', breakfast.isNotEmpty ? breakfast.first.title : null),
          const SizedBox(height: 8),
          _mealRow('LUNCH', lunch.isNotEmpty ? lunch.first.title : null),
          const SizedBox(height: 8),
          _mealRow('DINNER', dinner.isNotEmpty ? dinner.first.title : null),
        ],
      ),
    );
  }

  Widget _mealRow(String type, String? meal) {
    final hasMeal = meal != null && meal.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(type, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Color(0xFF16A34A))),
        const SizedBox(height: 2),
        Text(hasMeal ? meal : 'Not planned', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontStyle: hasMeal ? FontStyle.normal : FontStyle.italic, color: hasMeal ? AppTheme.stone800 : AppTheme.stone400)),
      ],
    );
  }

  Widget _buildTodayChores(BuildContext context, List<Chore> chores, int completed) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text("Today's Chores", style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF92400E))),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/chores'),
              child: const Text('Chart >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFF59E0B))),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            chores.isEmpty
                ? 'No chores assigned today. Enjoy the break!'
                : '$completed of ${chores.length} chores completed.',
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
          ),
        ],
      ),
    );
  }

  Widget _buildDevotional(BuildContext context, List<DevotionalEntry> devotionals) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Devotional', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E40AF))),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/devotional'),
              child: const Text('Open >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF3B82F6))),
            ),
          ]),
          const SizedBox(height: 8),
          if (devotionals.isEmpty)
            const Text('No devotionals yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400))
          else ...[
            Text(DateFormat('MMM d').format(devotionals.first.date).toUpperCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Color(0xFF3B82F6))),
            const SizedBox(height: 4),
            Text(devotionals.first.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900)),
            if (devotionals.first.scripture != null)
              Text(devotionals.first.scripture!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF3B82F6))),
          ],
        ],
      ),
    );
  }

  Widget _buildReadingPlan(BuildContext context, List<ReadingPlan> plans) {
    if (plans.isEmpty) return const SizedBox.shrink();
    final plan = plans.first;
    final totalEntries = plan.entryIds.length;
    final completedEntries = plan.completedCount;
    final progressValue = totalEntries > 0 ? completedEntries / totalEntries : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Reading Plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF6D28D9))),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/devotional'),
              child: const Text('Continue >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF7C3AED))),
            ),
          ]),
          const SizedBox(height: 8),
          Text(plan.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              backgroundColor: const Color(0xFFDDD6FE),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('$completedEntries/$totalEntries entries', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500)),
            const Spacer(),
            Text('${(progressValue * 100).toInt()}% complete', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF7C3AED))),
          ]),
        ],
      ),
    );
  }

  Widget _buildPrayerWall(BuildContext context, List<PrayerWallEntry> prayers) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Prayer Wall', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF9F1239))),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/prayer-wall'),
              child: const Text('Open >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFF43F5E))),
            ),
          ]),
          const SizedBox(height: 8),
          if (prayers.isEmpty)
            const Text('Share a prayer or gratitude with your family.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400))
          else ...[
            Row(children: [
              Text(prayers.first.type == PrayerWallType.GRATITUDE ? '\u{1F31F}' : '\u{1F64F}', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(prayers.first.type == PrayerWallType.GRATITUDE ? 'Gratitude' : 'Prayer Request', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9F1239))),
            ]),
            const SizedBox(height: 4),
            Text(prayers.first.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone700)),
          ],
        ],
      ),
    );
  }

  Widget _buildFitness(BuildContext context, List<FitnessMetric> metrics) {
    return _dashSection(
      title: 'Fitness',
      actionLabel: 'Log',
      onAction: () => context.go('/fitness'),
      child: metrics.isEmpty
          ? const Text('Start logging to see metrics.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400))
          : Row(children: [
              const Icon(Icons.fitness_center_rounded, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(metrics.first.type, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone700)),
              const SizedBox(width: 4),
              Text(DateFormat('MMM d').format(metrics.first.date), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
              const Spacer(),
              Text(metrics.first.value.toStringAsFixed(1), style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
            ]),
    );
  }

  Widget _buildOpenPolls(BuildContext context, List<Poll> polls) {
    return _dashSection(
      title: 'Open Polls',
      actionLabel: 'All Polls',
      onAction: () => context.go('/polls'),
      child: polls.isEmpty
          ? const Text('No open polls right now.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400))
          : Column(children: polls.take(2).map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.how_to_vote_rounded, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(p.question, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone800))),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.stone400),
              ]),
            )).toList()),
    );
  }

  // ── Birthdays & Anniversaries (next 7 days) ─────────────────────────────

  Widget _buildBirthdaysSection(AppDB db, String familyId, DateTime today) {
    final specialDates = db.specialDates
        .where((d) => d.familyId == familyId)
        .toList();

    if (specialDates.isEmpty) return const SizedBox.shrink();

    // Calculate days until each date this year
    final upcoming = <Map<String, dynamic>>[];
    for (final sd in specialDates) {
      var nextOccurrence = DateTime(today.year, sd.month, sd.day);
      if (nextOccurrence.isBefore(today)) {
        nextOccurrence = DateTime(today.year + 1, sd.month, sd.day);
      }
      final daysUntil = nextOccurrence.difference(today).inDays;
      if (daysUntil <= 7) {
        int? turningAge;
        if (sd.year != null && sd.type == SpecialDateType.BIRTHDAY) {
          turningAge = nextOccurrence.year - sd.year!;
        }
        upcoming.add({
          'date': sd,
          'daysUntil': daysUntil,
          'turningAge': turningAge,
        });
      }
    }

    if (upcoming.isEmpty) return const SizedBox.shrink();
    upcoming.sort((a, b) => (a['daysUntil'] as int).compareTo(b['daysUntil'] as int));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.cake_rounded, size: 18, color: Color(0xFFEC4899)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Upcoming Celebrations', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.stone900))),
            GestureDetector(
              onTap: () => context.go('/birthdays'),
              child: const Text('View all >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFEC4899))),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: upcoming.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final item = upcoming[i];
                final sd = item['date'] as SpecialDate;
                final daysUntil = item['daysUntil'] as int;
                final turningAge = item['turningAge'] as int?;
                final isToday = daysUntil == 0;
                final emoji = sd.emoji ?? (sd.type == SpecialDateType.BIRTHDAY ? '\u{1F382}' : '\u{1F48D}');

                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isToday
                        ? const LinearGradient(colors: [Color(0xFFFCE7F3), Color(0xFFFDF2F8)])
                        : null,
                    color: isToday ? null : AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isToday ? const Color(0xFFF9A8D4) : AppTheme.stone100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Text(emoji, style: const TextStyle(fontSize: 18)),
                        const Spacer(),
                        if (isToday)
                          const Text('\u{1F389}', style: TextStyle(fontSize: 14)),
                      ]),
                      const SizedBox(height: 6),
                      Text(sd.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.stone800), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        isToday ? 'Today!' : daysUntil == 1 ? 'Tomorrow' : 'In $daysUntil days',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: isToday ? const Color(0xFFDB2777) : AppTheme.stone400),
                      ),
                      if (turningAge != null)
                        Text('Turning $turningAge', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFFEC4899))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Event Countdown Cards ─────────────────────────────────────────────────

  Widget _buildEventCountdown(BuildContext context, List<CalendarEvent> events) {
    if (events.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: SizedBox(
        height: 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: events.length.clamp(0, 5),
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final event = events[i];
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final eventDay = DateTime(event.startDate.year, event.startDate.month, event.startDate.day);
            final daysLeft = eventDay.difference(today).inDays;

            return GestureDetector(
              onTap: () => context.go('/calendar'),
              child: Container(
                width: 130,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      daysLeft == 0 ? '\u{1F389}' : '$daysLeft',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    if (daysLeft > 0)
                      Text('day${daysLeft == 1 ? '' : 's'} left', style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Text(event.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Budget Snapshot with category breakdown ────────────────────────────────

  Widget _buildBudgetSnapshot(BuildContext context, AppDB db, String familyId, DateTime monthStart) {
    final monthEntries = db.budgetEntries.where((e) =>
      e.familyId == familyId && !e.date.isBefore(monthStart)).toList();
    final income = monthEntries.where((e) => e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final expenses = monthEntries.where((e) => !e.isIncome).fold<double>(0, (s, e) => s + e.amount);
    final net = income - expenses;

    // Group expenses by category
    final byCategory = <String, double>{};
    for (final e in monthEntries.where((e) => !e.isIncome)) {
      byCategory[e.category.name] = (byCategory[e.category.name] ?? 0) + e.amount;
    }
    final sortedCats = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Category colors
    const catColors = {
      'housing': Color(0xFF6366F1),
      'food': Color(0xFFF59E0B),
      'transport': Color(0xFF3B82F6),
      'entertainment': Color(0xFFEC4899),
      'utilities': Color(0xFF14B8A6),
      'healthcare': Color(0xFFEF4444),
      'education': Color(0xFF8B5CF6),
      'savings': Color(0xFF22C55E),
      'other': Color(0xFF78716C),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stone100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Budget', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.stone900)),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/budget'),
              child: Text('Details >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.primary)),
            ),
          ]),
          const SizedBox(height: 12),
          if (income == 0 && expenses == 0)
            const Text('Start tracking to see insights.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400))
          else ...[
            // Summary row
            Row(children: [
              _budgetMetric('INCOME', '\$${income.toStringAsFixed(0)}', AppTheme.success),
              const SizedBox(width: 24),
              _budgetMetric('EXPENSES', '\$${expenses.toStringAsFixed(0)}', AppTheme.error),
              const SizedBox(width: 24),
              _budgetMetric('NET', '${net >= 0 ? '+' : ''}\$${net.toStringAsFixed(0)}', net >= 0 ? AppTheme.success : AppTheme.error),
            ]),
            // Category breakdown bars
            if (sortedCats.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('SPENDING BY CATEGORY', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppTheme.stone400)),
              const SizedBox(height: 8),
              ...sortedCats.take(5).map((entry) {
                final pct = expenses > 0 ? entry.value / expenses : 0.0;
                final color = catColors[entry.key] ?? const Color(0xFF78716C);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: Text(entry.key, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: AppTheme.stone100,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 55, child: Text('\$${entry.value.toStringAsFixed(0)}', textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone700))),
                  ]),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _budgetMetric(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppTheme.stone400)),
      Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: color)),
    ]);
  }

  // ── Points Leaderboard ────────────────────────────────────────────────────

  Widget _buildPointsLeaderboard(AppDB db, String familyId) {
    // Aggregate all-time chore points per user
    final pointsMap = <String, int>{};
    for (final cc in db.choreCompletions.where((c) => c.familyId == familyId && c.approvalStatus == ApprovalStatus.APPROVED)) {
      final chore = db.chores.where((c) => c.id == cc.choreId).toList();
      if (chore.isNotEmpty) {
        pointsMap[cc.userId] = (pointsMap[cc.userId] ?? 0) + chore.first.points;
      }
    }

    if (pointsMap.isEmpty) return const SizedBox.shrink();

    final sorted = pointsMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.emoji_events_rounded, size: 18, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Points Leaderboard', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF92400E)))),
            GestureDetector(
              onTap: () => context.go('/chores'),
              child: const Text('Chores >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFF59E0B))),
            ),
          ]),
          const SizedBox(height: 12),
          ...top5.asMap().entries.map((entry) {
            final rank = entry.key;
            final userId = entry.value.key;
            final points = entry.value.value;
            final user = db.users.where((u) => u.id == userId).toList();
            final name = user.isNotEmpty ? user.first.name.split(' ').first : 'Unknown';
            final medal = rank == 0 ? '\u{1F451}' : '${rank + 1}';
            final bgColor = rank == 0 ? const Color(0xFFFEF3C7)
                : rank == 1 ? const Color(0xFFF1F5F9)
                : rank == 2 ? const Color(0xFFFFF7ED)
                : Colors.transparent;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                SizedBox(width: 24, child: Text(medal, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800))),
                Text('$points pts', style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFD97706))),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ── Generic dash section card ─────────────────────────────────────────────

  Widget _dashSection({
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stone100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.stone900)),
            const Spacer(),
            if (actionLabel != null)
              GestureDetector(
                onTap: onAction,
                child: Text('$actionLabel >', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.primary)),
              ),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
