// lib/screens/dashboard/dashboard_screen.dart
// Home dashboard screen for Huddle — matches Vite app design

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../config/cloud_sync_scope.dart';
import '../../config/theme.dart';
import '../../config/user_module_pins.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../utils/cloud_pull.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../utils/reading_plan_progress.dart';
import '../../widgets/subscription_modal.dart';
import '../../utils/module_disclaimer.dart';
import '../../utils/dashboard_ai_suggestions_cache.dart';
import '../../utils/devotional_display_utils.dart';
import '../../config/module_config.dart';
import '../../widgets/all_tools_sheet.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/huddle_subpage_scaffold.dart';
import '../../widgets/huddle_page_layout.dart';
import '../onboarding/welcome_module_tour_screen.dart';

// ─── AI Suggestion model ─────────────────────────────────────────────────────

class _AISuggestion {
  final String iconKey;
  final IconData icon;
  final String title;
  final String description;
  final String? reasoning;
  final String? timeEstimate;
  final String? route;

  const _AISuggestion({
    this.iconKey = 'task',
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

// ─── Dashboard Screen ────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// In-memory cache so suggestions survive widget recreation without
  /// re-reading SharedPreferences or calling Gemini again.
  static List<_AISuggestion>? _cachedSuggestions;
  static int _cachedCompletedMask = 0;
  static bool _cachedFromGemini = false;
  static String? _cachedForKey;

  String? _dismissedAnnouncement;
  List<_AISuggestion> _suggestions = [];
  int _suggestionCompletedMask = 0;
  bool _suggestionsFromGemini = false;
  bool _suggestionsLoading = true;
  bool _suggestionsLoaded = false;

  void _persistToMemoryCache() {
    _cachedSuggestions = List.of(_suggestions);
    _cachedCompletedMask = _suggestionCompletedMask;
    _cachedFromGemini = _suggestionsFromGemini;
    final p = context.read<AppProvider>();
    _cachedForKey = '${p.activeUser?.id}_${p.activeFamily?.id}';
  }
  bool _startTipDismissed = false;
  bool _startTipReady = false;

  // Monthly Summary
  Map<String, dynamic>? _monthlySummary;
  bool _monthlySummaryLoading = false;
  bool _fetchedGeminiSuggestions = false;
  bool? _lastProviderHasAI;
  late final AppProvider _appProvider;

  /// Show full AI suggestion list on Home (default: first two only).
  bool _aiHomeSuggestionsExpanded = false;
  /// Long monthly recap body hidden until opened.
  bool _monthlyNarrativeExpanded = false;

  /// Phase H — progressive disclosure for dense Home content below essentials.
  bool _showDashboardDeepSections = false;

  @override
  void initState() {
    super.initState();
    _appProvider = context.read<AppProvider>();
    _appProvider.addListener(_onAppProviderChanged);
    _lastProviderHasAI = _appProvider.hasAIAccess;
    _loadDismissedAnnouncement();

    // Restore in-memory cache instantly to avoid spinner on re-navigation
    final cacheKey = '${_appProvider.activeUser?.id}_${_appProvider.activeFamily?.id}';
    if (_cachedSuggestions != null && _cachedForKey == cacheKey) {
      _suggestions = _cachedSuggestions!;
      _suggestionCompletedMask = _cachedCompletedMask;
      _suggestionsFromGemini = _cachedFromGemini;
      _suggestionsLoading = false;
      _suggestionsLoaded = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showMedicalDisclaimerIfNeeded();
      if (!mounted) return;

      if (_suggestionsLoaded) {
        // Already have suggestions from cache — skip API call
      } else if (AiService.isAIBlocked) {
        final p = context.read<AppProvider>();
        final db = p.db;
        final fid = p.activeFamily?.id ?? '';
        final uid = p.activeUser?.id ?? '';
        setState(() {
          _suggestionsLoading = false;
          _suggestions = _generateLocalSuggestions(db, fid, uid);
          _suggestionCompletedMask = 0;
          _suggestionsFromGemini = false;
          _suggestionsLoaded = true;
        });
      } else {
        _loadAISuggestions(forceRefresh: false);
      }
      await _showWelcomeTourIfPending();
      _loadStartTipDismissed();
    });
  }

  @override
  void dispose() {
    _appProvider.removeListener(_onAppProviderChanged);
    super.dispose();
  }

  void _onAppProviderChanged() {
    if (!mounted) return;
    final p = _appProvider;
    final now = p.hasAIAccess;
    if (_lastProviderHasAI == false && now == true) {
      if (!_fetchedGeminiSuggestions) {
        _loadAISuggestions(forceRefresh: false);
      }
    }
    _lastProviderHasAI = now;
  }

  Future<void> _loadStartTipDismissed() async {
    if (!mounted) return;
    final fam = context.read<AppProvider>().activeFamily?.id;
    if (fam == null) return;
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _startTipDismissed = p.getBool('lobohub_dashboard_tip_$fam') ?? false;
      _startTipReady = true;
    });
  }

  Future<void> _dismissStartTip(String familyId) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('lobohub_dashboard_tip_$familyId', true);
    if (mounted) setState(() => _startTipDismissed = true);
  }

  bool _welcomeTourCheckScheduled = false;

  /// After first home creation + module setup, [markWelcomeTourPending] is set; we show once here.
  Future<void> _showWelcomeTourIfPending() async {
    if (_welcomeTourCheckScheduled) return;
    _welcomeTourCheckScheduled = true;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kPrefPendingWelcomeTour) ?? false)) return;
    if (!mounted) return;
    final raw = prefs.getString(kPrefPendingWelcomeTourPaths) ?? '';
    final keys = raw.split(',').where((s) => s.trim().isNotEmpty).toList();
    final modules = modulesInCatalogOrder(keys);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => WelcomeModuleTourScreen(
          modules: modules,
          onComplete: () {
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  Future<void> _showMedicalDisclaimerIfNeeded() async {
    final userId = context.read<AppProvider>().activeUser?.id;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (await isMedicalDisclaimerAcceptedForUser(prefs, userId)) return;
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MedicalDisclaimerDialog(
        onAccepted: () async {
          await setMedicalDisclaimerAcceptedForUser(prefs, userId);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _loadDismissedAnnouncement() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return; // FIXED: context after async
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
    await pullCloudLatestWithHaptic(context);
    if (!mounted) return; // FIXED: context after async
    final provider = context.read<AppProvider>();
    await provider.saveAndSync(provider.db);
    await _loadAISuggestions(forceRefresh: true);
  }

  Future<void> _loadMonthlySummary() async {
    if (!mounted) return;
    if (AiService.isAIBlocked) {
      await SubscriptionModal.show(
        context,
        kind: AiPaywallKind.monthlyRecap,
      );
      return;
    }
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
    final familyName = family.name; // FIXED: Family.name is non-nullable
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthName = DateFormat('MMMM yyyy').format(now);

    // Gather monthly stats
    final tasksCreated = db.tasks.where((t) => t.familyId == familyId && t.dueDate != null && t.dueDate!.isAfter(monthStart)).length;
    final tasksCompleted = db.tasks.where((t) => t.familyId == familyId && t.dueDate != null && t.dueDate!.isAfter(monthStart) && t.completed).length;
    final mealsPlanned = db.mealPlans.where((m) => m.familyId == familyId && m.date.isAfter(monthStart)).length;
    final devotionals = db.devotionalEntries.where((d) => d.familyId == familyId && d.date.isAfter(monthStart)).length;
    final workouts = db.fitnessLogs.where((f) => f.familyId == familyId && f.date.isAfter(monthStart)).length;

    final userId = provider.activeUser?.id ?? '';
    final budgetEntries = db.budgetEntries.where((e) =>
        e.familyId == familyId &&
        e.date.isAfter(monthStart) &&
        (e.visibility == Visibility.FAMILY || (e.visibility == Visibility.PRIVATE && e.creatorId == userId))).toList();
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
      if (!mounted) return;
      if (decoded is Map<String, dynamic>) {
        setState(() {
          _monthlySummary = decoded;
          _monthlySummaryLoading = false;
          _monthlyNarrativeExpanded = true;
        });
      } else {
        setState(() => _monthlySummaryLoading = false);
      }
    } catch (e) {
      debugPrint('[Dashboard] monthly summary error: $e');
      if (mounted) setState(() => _monthlySummaryLoading = false);
    }
  }

  List<_AISuggestion> _parseGeminiSuggestionsList(List decoded) {
    return decoded.map((s) {
      final map = s as Map<String, dynamic>;
      final key = map['icon'] as String? ?? 'task';
      return _AISuggestion(
        iconKey: key,
        icon: _iconFromString(key),
        title: map['title'] as String? ?? '',
        description: map['description'] as String? ?? '',
        reasoning: map['reasoning'] as String?,
        timeEstimate: map['timeEstimate'] as String?,
        route: map['route'] as String?,
      );
    }).toList();
  }

  Future<void> _persistGeminiSuggestions({
    required String userId,
    required String familyId,
    required List<_AISuggestion> suggestions,
    required String contextHash,
  }) async {
    final records = suggestions
        .map((s) => DashboardAiSuggestionRecord(
              icon: s.iconKey,
              title: s.title,
              description: s.description,
              reasoning: s.reasoning,
              timeEstimate: s.timeEstimate,
              route: s.route,
            ))
        .toList();
    await saveDashboardAiCache(
      userId,
      familyId,
      DashboardAiSuggestionsCachePayload(
        suggestions: records,
        contextHash: contextHash,
        generatedAtIso: DateTime.now().toIso8601String(),
        completedMask: _suggestionCompletedMask,
      ),
    );
  }

  void _applyCachedPayload(
    DashboardAiSuggestionsCachePayload payload, {
    required bool fromGemini,
  }) {
    _suggestionCompletedMask = payload.completedMask;
    _suggestionsFromGemini = fromGemini;
    _suggestions = payload.suggestions
        .map((r) => _AISuggestion(
              iconKey: r.icon,
              icon: _iconFromString(r.icon),
              title: r.title,
              description: r.description,
              reasoning: r.reasoning,
              timeEstimate: r.timeEstimate,
              route: r.route,
            ))
        .toList();
    _persistToMemoryCache();
  }

  Future<void> _markSuggestionDone(int index) async {
    if (!_suggestionsFromGemini || index < 0 || index > 2) return;
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;

    final bit = 1 << index;
    if ((_suggestionCompletedMask & bit) != 0) return;

    final newMask = _suggestionCompletedMask | bit;
    setState(() => _suggestionCompletedMask = newMask);

    final cached = await loadDashboardAiCache(user.id, family.id);
    if (cached != null) {
      await saveDashboardAiCache(
        user.id,
        family.id,
        cached.copyWith(completedMask: newMask),
      );
    }

    if (newMask == 0x7 || _suggestions.length < 3 && newMask == (1 << _suggestions.length) - 1) {
      await _loadAISuggestions(forceRefresh: false);
    }
  }

  Future<void> _loadAISuggestions({
    bool showPaywallWhenLocked = false,
    bool forceRefresh = false,
  }) async {
    if (!mounted) return;
    if (AiService.isAIBlocked) {
      if (showPaywallWhenLocked && mounted) {
        await SubscriptionModal.show(
          context,
          kind: AiPaywallKind.homeSuggestions,
        );
      }
      return;
    }
    if (!mounted) return;

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) {
      setState(() {
        _suggestionsLoading = false;
        _suggestions = _generateLocalSuggestions(db, family?.id ?? '', user?.id ?? '');
        _suggestionCompletedMask = 0;
        _suggestionsFromGemini = false;
        _suggestionsLoaded = true;
      });
      return;
    }

    final familyId = family.id;
    final userId = user.id;
    final fingerprint = dashboardSuggestionsContextFingerprint(
      db: db,
      familyId: familyId,
      userId: userId,
    );
    final contextHash = hashDashboardContext(fingerprint);

    if (!forceRefresh) {
      final cached = await loadDashboardAiCache(userId, familyId);
      if (cached != null &&
          cached.suggestions.isNotEmpty &&
          cached.contextHash == contextHash) {
        if (!cached.allCompleted) {
          if (!mounted) return;
          setState(() {
            _applyCachedPayload(cached, fromGemini: true);
            _suggestionsLoading = false;
            _suggestionsLoaded = true;
            _fetchedGeminiSuggestions = true;
          });
          return;
        }
        final canRegen =
            await canGenerateDashboardAiSuggestions(userId, familyId);
        if (!canRegen) {
          if (!mounted) return;
          setState(() {
            _applyCachedPayload(cached, fromGemini: true);
            _suggestionsLoading = false;
            _suggestionsLoaded = true;
            _fetchedGeminiSuggestions = true;
          });
          return;
        }
      } else if (cached != null &&
          cached.suggestions.isNotEmpty &&
          cached.contextHash != contextHash &&
          !cached.allCompleted) {
        if (!mounted) return;
        setState(() {
          _applyCachedPayload(cached, fromGemini: true);
          _suggestionsLoading = false;
          _suggestionsLoaded = true;
          _fetchedGeminiSuggestions = true;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _suggestionsLoading = true);

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
    final habitsCompleted = db.dailyHabitCompletions.where((c) => c.userId == user.id && _isSameDay(c.date, today)).length;

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

    Future<void> showLocalFallback() async {
      if (!mounted) return;
      setState(() {
        _suggestions = _generateLocalSuggestions(db, familyId, user.id);
        _suggestionCompletedMask = 0;
        _suggestionsFromGemini = false;
        _suggestionsLoading = false;
        _suggestionsLoaded = true;
      });
    }

    final allowNetwork = forceRefresh ||
        await canGenerateDashboardAiSuggestions(userId, familyId);

    if (!allowNetwork) {
      final cached = await loadDashboardAiCache(userId, familyId);
      if (cached != null && cached.suggestions.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _applyCachedPayload(cached, fromGemini: true);
          _suggestionsLoading = false;
          _suggestionsLoaded = true;
          _fetchedGeminiSuggestions = true;
        });
        if (mounted && forceRefresh) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Daily AI suggestion limit reached ($kDashboardAiSuggestionsMaxGenerationsPerDay). Showing cached suggestions.',
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await showLocalFallback();
      if (mounted && forceRefresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Daily AI limit reached ($kDashboardAiSuggestionsMaxGenerationsPerDay). Showing quick tips instead.',
              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

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
            final parsed = _parseGeminiSuggestionsList(decoded);
            await recordDashboardAiGeneration(userId, familyId);
            _suggestionCompletedMask = 0;
            await _persistGeminiSuggestions(
              userId: userId,
              familyId: familyId,
              suggestions: parsed,
              contextHash: contextHash,
            );
            if (!mounted) return;
            setState(() {
              _suggestions = parsed;
              _suggestionsFromGemini = true;
              _suggestionsLoading = false;
              _suggestionsLoaded = true;
              _fetchedGeminiSuggestions = true;
              _persistToMemoryCache();
            });
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}

    await showLocalFallback();
  }

  List<_AISuggestion> _generateLocalSuggestions(AppDB db, String familyId, String userId) {
    final suggestions = <_AISuggestion>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final overdue = db.tasks.where((t) => t.familyId == familyId && !t.completed && t.dueDate != null && t.dueDate!.isBefore(today)).length;
    if (overdue > 0) {
      suggestions.add(_AISuggestion(
        iconKey: 'task',
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
        iconKey: 'meal',
        icon: Icons.restaurant_rounded,
        title: 'Plan ${missing.first} for today',
        description: 'You haven\'t planned ${missing.join(' or ')} yet.',
        reasoning: 'Meal planning reduces stress and saves money.',
        timeEstimate: '5 min',
        route: '/meals',
      ));
    }

    final habits = db.dailyHabits.where((h) => h.familyId == familyId).length;
    final habitsCompleted = db.dailyHabitCompletions.where((c) => c.userId == userId && _isSameDay(c.date, today)).length;
    if (habits > 0 && habitsCompleted < habits) {
      suggestions.add(_AISuggestion(
        iconKey: 'habit',
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
        iconKey: 'task',
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
          return const ModuleFamilyLoadingScaffold();
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
        final userId = user.id;
        final spentThisMonth = db.budgetEntries
            .where((e) =>
                e.familyId == familyId &&
                e.type == TransactionType.EXPENSE &&
                !e.date.isBefore(monthStart) &&
                (e.visibility == Visibility.FAMILY || (e.visibility == Visibility.PRIVATE && e.creatorId == userId)))
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

        if (isRestricted) {
          return _buildKidsDashboard(context, provider, user, family, db, familyId, today, choresToday, choresCompletedToday, todayMealPlans, tasksDueToday);
        }

        final showTryAI =
            !family.welcomeDismissed && !(_startTipReady && !_startTipDismissed);
        final hasNoCoreData = db.tasks.where((t) => t.familyId == familyId).isEmpty &&
            db.events.where((e) => e.familyId == familyId).isEmpty;
        final actionTodayCount = todayFocusTasks.length + overdueTasks.length;

        return HuddleModuleScaffold(
          modulePath: '/',
          drawer: const AppDrawer(),
          // backgroundColor handled by theme
          appBar: const MainAppBar(),
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _buildTodayAtAGlance(
                  context,
                  user,
                  family,
                  actionTodayCount,
                  upcomingEvents,
                ),
                _buildTrialBanner(context, family),
                if (_startTipReady && !_startTipDismissed) _buildOnboardingHint(context, family.id),
                _buildAnnouncementSection(context, provider, family),
                _buildHomeQuickActions(context, family, user),
                if (showTryAI) _buildTryAICard(context, provider, family),
                if (hasNoCoreData) _buildEmptySetupHint(context, family, familyId),
                RepaintBoundary(child: _buildAISuggestionsSection()),
                _buildDashboardDeepSectionsToggle(context),
                if (_showDashboardDeepSections) ...[
                  _buildBirthdaysSection(db, familyId, today),
                  RepaintBoundary(child: _buildMonthlySummarySection()),
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
                  _buildBudgetSnapshot(context, db, familyId, user.id, monthStart),
                  _buildPointsLeaderboard(db, familyId),
                  _buildTodayMeals(context, todayMealPlans),
                  _buildTodayChores(context, choresToday, choresCompletedToday),
                  _buildDevotional(context, todayDevotional),
                  _buildReadingPlan(context, db, user.id, readingPlans),
                  _buildPrayerWall(context, recentPrayer),
                  _buildFitness(context, recentFitness),
                  _buildOpenPolls(context, openPolls),
                ],
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

  /// Collapses birthdays, stats, and module summaries behind one affordance (Phase H).
  Widget _buildDashboardDeepSectionsToggle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _showDashboardDeepSections = !_showDashboardDeepSections);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showDashboardDeepSections ? 'Hide extra home sections' : 'More on Home',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Birthdays, stats, devotionals, and activity summaries',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          height: 1.3,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _showDashboardDeepSections ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: cs.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
      appBar: SubpageAppBar(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(String.fromCharCode(0x2728), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              AppConfig.appName,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        leading: SubpageLeading.none,
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Greeting
            HuddlePagePadding(
              horizontal: 20,
              vertical: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hey $firstName! \u{1F44B}', style: const TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.stone900)),
                  const SizedBox(height: 4),
                  Text("It's $dayName, $monthDay. Here's your day.", style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500)),
                ],
              ),
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
                            await provider.saveAndSync(
                              db.copyWith(
                                choreCompletions: [...db.choreCompletions, completion],
                              ),
                              pushTableScope: CloudSyncScope.choreBundle,
                            );
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

  /// “Today” hero: one glance at schedule + load for the day.
  Widget _buildTodayAtAGlance(
    BuildContext context,
    User user,
    Family family,
    int taskActionCount,
    List<CalendarEvent> upcomingWeek,
  ) {
    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now);
    final monthDay = DateFormat('MMMM d').format(now);
    final userFirst = user.name.trim().isEmpty
        ? 'there'
        : user.name.split(RegExp(r'\s+')).first;
    final fam = family.name.trim();
    final day = now.day;
    String suffix = 'th';
    if (day % 100 < 11 || day % 100 > 13) {
      switch (day % 10) {
        case 1: suffix = 'st'; break;
        case 2: suffix = 'nd'; break;
        case 3: suffix = 'rd'; break;
      }
    }
    final next = upcomingWeek.isNotEmpty ? upcomingWeek.first : null;
    final timeFmt = DateFormat("EEE, MMM d '·' h:mm a");
    String subtitle;
    if (next != null) {
      subtitle = 'Next: ${next.title} — ${timeFmt.format(next.start)}';
    } else if (taskActionCount > 0) {
      subtitle =
          '$taskActionCount thing${taskActionCount == 1 ? '' : 's'} on your list today';
    } else {
      subtitle = 'Nothing urgent on the calendar — a good moment to breathe.';
    }
    final String welcomeTitle = fam.isEmpty
        ? 'Hey, $userFirst — $dayName, $monthDay$suffix'
        : 'Hey, $userFirst · $fam — $dayName, $monthDay$suffix';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (next != null) {
              context.go('/calendar');
            } else if (taskActionCount > 0) {
              context.go('/tasks');
            } else {
              context.go('/calendar');
            }
            HapticFeedback.lightImpact();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 30,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TODAY',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.15,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        welcomeTitle,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.stone900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          height: 1.35,
                          color: AppTheme.stone600.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tasks, meals, and lists stay scoped to your household.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          height: 1.35,
                          color: AppTheme.stone500.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.stone400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// First-run hint when the family has no tasks and no events yet.
  Widget _buildEmptySetupHint(BuildContext context, Family family, String familyId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start in one place',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a calendar event or a task so {name} can show what’s next here.'
                  .replaceAll('{name}', AppConfig.appName),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go('/calendar'),
              icon: const Icon(Icons.event_available_rounded, size: 20),
              label: const Text('Add your first event', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Essentials and/or [User] pins + All tools.
  Widget _buildHomeQuickActions(BuildContext context, Family family, User user) {
    final paths = resolvedDashboardQuickPaths(family, user);
    final hasPins = pinnedModulePathsFromUser(user).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPins)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Favorites',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.2,
                color: AppTheme.stone500,
              ),
            ),
          ),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(20, hasPins ? 8 : 16, 20, 0),
            itemCount: paths.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              if (i == paths.length) {
                return _homeQuickCell(
                  icon: Icons.grid_view_rounded,
                  label: 'All tools',
                  color: const Color(0xFF64748B),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showAllToolsBottomSheet(context, family: family);
                  },
                );
              }
              final path = paths[i];
              final info = getModuleByPath(path);
              final label = info?.name ?? path;
              final color = _homeQuickColor(path);
              final icon = _homeQuickIcon(path);
              return _homeQuickCell(
                icon: icon,
                label: label,
                color: color,
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.go(path);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Color _homeQuickColor(String path) {
    switch (path) {
      case '/assistant': return const Color(0xFF7C3AED);
      case '/tasks': return const Color(0xFF6366F1);
      case '/calendar': return const Color(0xFFF59E0B);
      case '/meals': return const Color(0xFF10B981);
      case '/lists': return const Color(0xFF0EA5E9);
      case '/chores': return const Color(0xFF14B8A6);
      case '/rewards': return const Color(0xFFEC4899);
      case '/habits': return const Color(0xFF8B5CF6);
      default: return AppTheme.primary;
    }
  }

  IconData _homeQuickIcon(String path) {
    switch (path) {
      case '/assistant': return Icons.auto_awesome_rounded;
      case '/tasks': return Icons.check_circle_outline_rounded;
      case '/calendar': return Icons.event_rounded;
      case '/meals': return Icons.restaurant_rounded;
      case '/lists': return Icons.checklist_rounded;
      case '/chores': return Icons.assignment_turned_in_rounded;
      case '/rewards': return Icons.card_giftcard_rounded;
      case '/habits': return Icons.track_changes_rounded;
      default: return Icons.apps_rounded;
    }
  }

  Widget _homeQuickCell({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone600),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingHint(BuildContext context, String familyId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Get started',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: () => _dismissStartTip(familyId),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Dismiss',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A few quick wins for your home:',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            _onboardingBullet(context, 'Add this week’s tasks and assign them'),
            _onboardingBullet(context, 'Put dinner on the meal plan'),
            _onboardingBullet(context, 'Create a shared shopping list'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Tasks', style: TextStyle(fontFamily: 'Inter')),
                  onPressed: () => context.go('/tasks'),
                ),
                ActionChip(
                  label: const Text('Meals', style: TextStyle(fontFamily: 'Inter')),
                  onPressed: () => context.go('/meals'),
                ),
                ActionChip(
                  label: const Text('Lists', style: TextStyle(fontFamily: 'Inter')),
                  onPressed: () => context.go('/lists'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _onboardingBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.35)),
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

  Widget _buildAnnouncementSection(BuildContext context, AppProvider provider, Family family) {
    final userId = provider.activeUser?.id;
    final canEditAnnouncement =
        userId != null && provider.activeFamily?.ownerId == userId;
    final hasAnnouncement = family.announcement != null && family.announcement!.isNotEmpty && family.announcement != _dismissedAnnouncement;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GestureDetector(
        onTap: canEditAnnouncement
            ? () => _editAnnouncement(context, provider, family)
            : null,
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
            else if (canEditAnnouncement)
              Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  Future<void> _editAnnouncement(BuildContext context, AppProvider provider, Family family) async {
    final userId = provider.activeUser?.id;
    final canEditAnnouncement =
        userId != null && provider.activeFamily?.ownerId == userId;
    if (!canEditAnnouncement) return;
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
    await provider.saveAndSync(
      db.copyWith(
        families: db.families.map((f) => f.id == updated.id ? updated : f).toList(),
      ),
      pushTableScope: {CloudSyncScope.families},
    );
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
              child:             Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'AI',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Try smart features',
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
                    onPressed: () async {
                      final uid = provider.activeUser?.id;
                      final isOwner = uid != null && family.ownerId == uid;
                      if (!isOwner) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Only the family owner can dismiss this banner for everyone.',
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      final updated = family.copyWith(welcomeDismissed: true);
                      final db = provider.db;
                      provider.updateFamily(updated);
                      await provider.saveAndSync(
                        db.copyWith(
                          families: db.families.map((f) => f.id == updated.id ? updated : f).toList(),
                        ),
                        pushTableScope: {CloudSyncScope.families},
                      );
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
                    onTap: () {
                      if (AiService.isAIBlocked) {
                        SubscriptionModal.show(
                          context,
                          kind: AiPaywallKind.explore,
                        );
                      } else {
                        context.push(f.route);
                      }
                    },
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
                  Text('Family AI suggestions', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF92400E))),
                  Text('Powered by Gemini', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFD97706))),
                ],
              )),
              GestureDetector(
                onTap: () => _loadAISuggestions(
                  showPaywallWhenLocked: true,
                  forceRefresh: true,
                ),
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
              ..._buildVisibleSuggestionRows(),
            if (!_suggestionsLoading && _suggestions.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _aiHomeSuggestionsExpanded = !_aiHomeSuggestionsExpanded);
                    },
                    child: Text(
                      _aiHomeSuggestionsExpanded
                          ? 'Show fewer'
                          : 'Show all (${_suggestions.length})',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildVisibleSuggestionRows() {
    final rows = <Widget>[];
    final limit = _aiHomeSuggestionsExpanded || _suggestions.length <= 2
        ? _suggestions.length
        : 2;
    for (var i = 0; i < limit; i++) {
      final s = _suggestions[i];
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i > 0 ? 10 : 0),
          child: _buildSuggestionCard(s, i),
        ),
      );
    }
    return rows;
  }

  Widget _buildSuggestionCard(_AISuggestion s, int index) {
    final gemini = _suggestionsFromGemini;
    final done = gemini && index >= 0 && index <= 2 && ((_suggestionCompletedMask >> index) & 1) == 1;
    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Container(
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
              if (s.route != null && !done)
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
            if (gemini && !done) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _markSuggestionDone(index);
                  },
                  child: const Text('Done', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
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
              if (_monthlyNarrativeExpanded) ...[
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _monthlyNarrativeExpanded = false);
                    },
                    child: const Text('Show less', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white70)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _monthlyNarrativeExpanded = true);
                    },
                    child: const Text('Show full recap', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                  ),
                ),
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
    final first =
        devotionals.isEmpty ? null : devotionalEntryForDisplay(devotionals.first);
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
            CatalogModuleEmptyState(
              compact: true,
              modulePath: '/devotional',
              emojiSize: 36,
              title: 'No devotionals yet',
              subtitle: 'Open Devotional to read, save favorites, or get today\'s reading.',
              actionLabel: 'Open',
              onAction: () => context.go('/devotional'),
            )
          else ...[
            Text(DateFormat('MMM d').format(first!.date).toUpperCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Color(0xFF3B82F6))),
            const SizedBox(height: 4),
            Text(first.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900)),
            if (first.scripture != null)
              Text(first.scripture!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF3B82F6))),
          ],
        ],
      ),
    );
  }

  Widget _buildReadingPlan(
    BuildContext context,
    AppDB db,
    String userId,
    List<ReadingPlan> plans,
  ) {
    if (plans.isEmpty) return const SizedBox.shrink();
    final plan = plans.first;
    final totalEntries = plan.entryIds.length;
    final completedEntries =
        readingPlanEffectiveCompletedDays(plan, userId, db);
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

  Widget _buildBudgetSnapshot(BuildContext context, AppDB db, String familyId, String userId, DateTime monthStart) {
    final monthEntries = db.budgetEntries.where((e) =>
      e.familyId == familyId &&
      !e.date.isBefore(monthStart) &&
      (e.visibility == Visibility.FAMILY || (e.visibility == Visibility.PRIVATE && e.creatorId == userId))).toList();
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

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MedicalDisclaimerDialog extends StatefulWidget {
  final VoidCallback onAccepted;
  const _MedicalDisclaimerDialog({required this.onAccepted});

  @override
  State<_MedicalDisclaimerDialog> createState() => _MedicalDisclaimerDialogState();
}

class _MedicalDisclaimerDialogState extends State<_MedicalDisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.medical_information_rounded, color: Color(0xFFDC2626), size: 24),
          SizedBox(width: 10),
          Expanded(child: Text('Health Disclaimer')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Huddle includes health and wellness features such as fitness tracking, meal planning, period tracking, and health records.\n\n'
            'These features are for informational purposes only and are not a substitute for professional medical advice, diagnosis, or treatment.\n\n'
            'Always seek the advice of your doctor or qualified healthcare provider with any questions regarding a medical condition. Never disregard professional medical advice because of information provided by this app.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _accepted = !_accepted),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'I accept and understand this disclaimer',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _accepted ? widget.onAccepted : null,
            child: const Text('OK'),
          ),
        ),
      ],
    );
  }
}
