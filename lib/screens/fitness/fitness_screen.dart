// lib/screens/fitness/fitness_screen.dart

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../utils/module_disclaimer.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../services/exercise_pr_service.dart';
import '../../services/locale_service.dart';
import '../../services/exercise_plan_media_service.dart';
import '../../services/workout_health_sync.dart';
import '../../widgets/exercise_media_image.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/module_ui_kit.dart';
import '../../widgets/huddle_subpage_scaffold.dart';
import '../../widgets/subscription_modal.dart';
import '../../utils/debounce.dart';
import '../../utils/fitness_plan_storage.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _uuid = Uuid();

const _activityEmojis = {
  'run': '🏃',
  'walk': '🚶',
  'swim': '🏊',
  'bike': '🚴',
  'cycl': '🚴',
  'yoga': '🧘',
  'weight': '🏋️',
  'lift': '🏋️',
  'hike': '🥾',
  'hiit': '🔥',
};

const _homeEquipment = [
  'Dumbbells',
  'Resistance Bands',
  'Barbell & Plates',
  'Pull-up Bar',
  'Kettlebell',
  'Bench',
  'Jump Rope',
  'Bodyweight Only',
];

const _fitnessLevels = ['Beginner', 'Intermediate', 'Advanced'];

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

Future<bool> _confirmRemove(BuildContext context, String title, String message) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800))),
      ]),
      content: Text(message, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

InputDecoration _styledInput(String hint, {IconData? icon}) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppTheme.stone300, fontFamily: 'Inter', fontSize: 13),
  prefixIcon: icon != null ? Icon(icon, size: 20, color: AppTheme.stone400) : null,
  filled: true,
  fillColor: Colors.white,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: AppTheme.stone200),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: AppTheme.stone200),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
  ),
);

String _activityEmoji(String activity) {
  final a = activity.toLowerCase();
  for (final entry in _activityEmojis.entries) {
    if (a.contains(entry.key)) return entry.value;
  }
  return '💪';
}

String _stripFences(String raw) {
  var s = raw.trim();
  if (s.startsWith('```')) s = s.substring(s.indexOf('\n') + 1);
  if (s.endsWith('```')) s = s.substring(0, s.lastIndexOf('```'));
  return s.trim();
}

(int sets, int reps) _parseSetsRepsFromDetail(String? detail) {
  if (detail == null || detail.trim().isEmpty) return (3, 10);
  final lower = detail.toLowerCase();
  final xMatch = RegExp(r'(\d+)\s*[x×]\s*(\d+)').firstMatch(lower);
  if (xMatch != null) {
    return (int.parse(xMatch.group(1)!), int.parse(xMatch.group(2)!));
  }
  final setMatch = RegExp(r'(\d+)\s*sets?').firstMatch(lower);
  final repMatch = RegExp(r'(\d+)\s*reps?').firstMatch(lower);
  final sets = setMatch != null ? int.parse(setMatch.group(1)!) : 3;
  final reps = repMatch != null ? int.parse(repMatch.group(1)!) : 10;
  return (sets.clamp(1, 20), reps.clamp(1, 999));
}

int _parseRestSeconds(String? detail) {
  if (detail == null || detail.trim().isEmpty) return 60;
  final lower = detail.toLowerCase();
  final sec = RegExp(r'(\d+)\s*(?:s|sec|secs|second)').firstMatch(lower);
  if (sec != null) return int.parse(sec.group(1)!).clamp(10, 600);
  final rest = RegExp(r'rest\s*(\d+)').firstMatch(lower);
  if (rest != null) return int.parse(rest.group(1)!).clamp(10, 600);
  return 60;
}

Future<void> _persistCompletedWorkout(
  BuildContext context,
  AppProvider provider, {
  required WorkoutSession session,
  required List<WorkoutExercise> exercises,
  required List<WorkoutSet> sets,
}) async {
  final user = provider.activeUser;
  final family = provider.activeFamily;
  if (user == null || family == null) return;

  var next = ExercisePrService.updateFromSession(
    provider.db,
    familyId: family.id,
    userId: user.id,
    session: session,
    exercises: exercises,
    sets: sets,
  );

  var sessionToSave = session;
  final healthOn = user.settings['health_workout_sync'] == true;
  if (healthOn) {
    final ok = await writeWorkoutSessionToHealth(session);
    if (ok) {
      sessionToSave = session.copyWith(healthSyncedAt: DateTime.now());
    } else if (context.mounted) {
      _showSnack(
        context,
        'Could not save to Health (install Health Connect on Android or enable HealthKit). Workout saved in Huddle.',
      );
    }
  }

  next = next.copyWith(
    workoutSessions: [...next.workoutSessions, sessionToSave],
    workoutExercises: [...next.workoutExercises, ...exercises],
    workoutSets: [...next.workoutSets, ...sets],
  );
  await provider.saveAndSync(
    next,
    pushTableScope: CloudSyncScope.fitnessFullBundle,
  );
}

String? _exerciseImageUrl(Map exercise) {
  for (final k in ['imageUrl', 'image_url', 'illustrationUrl']) {
    final v = exercise[k]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

String? _exerciseDbIdFromMap(Map exercise) {
  final v = exercise['exerciseDbId']?.toString().trim();
  if (v != null && v.isNotEmpty) return v;
  return null;
}

Widget _exerciseIllustrationTile(String? url, {String? exerciseDbId, double size = 56}) {
  if ((url == null || url.isEmpty) && (exerciseDbId == null || exerciseDbId.isEmpty)) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.stone200),
      ),
      child: Icon(Icons.fitness_center_rounded, size: size * 0.4, color: AppTheme.stone400),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Semantics(
      label: 'Exercise illustration',
      image: true,
      child: ExerciseMediaImage(
        imageUrl: url,
        exerciseDbId: exerciseDbId,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    ),
  );
}

Widget _exerciseIllustrationBanner(String? url, {String? exerciseDbId}) {
  if ((url == null || url.isEmpty) && (exerciseDbId == null || exerciseDbId.isEmpty)) {
    return const SizedBox.shrink();
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Semantics(
        label: 'Exercise illustration',
        image: true,
        child: ExerciseMediaImage(
          imageUrl: url,
          exerciseDbId: exerciseDbId,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    ),
  );
}

// ─── Fitness Screen ───────────────────────────────────────────────────────────

class FitnessScreen extends StatefulWidget {
  const FitnessScreen({super.key});

  @override
  State<FitnessScreen> createState() => _FitnessScreenState();
}

enum _FitnessFilter { mine, family }

class _FitnessScreenState extends State<FitnessScreen> {
  _FitnessFilter _filter = _FitnessFilter.mine;
  String? _motivation;
  bool _motivationLoading = false;
  final _logSearchCtrl = TextEditingController();
  final _logSearchDebounce = Debouncer();
  String _logSearchQuery = '';
  int _selectedPlanIndex = 0;
  String? _weeklyRecap;
  bool _weeklyRecapLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<AppProvider>()
          .scheduleModuleEnterCloudPull(CloudSyncScope.fitnessFullBundle);
      final uid = context.read<AppProvider>().activeUser?.id;
      if (uid == null) return;
      showModuleDisclaimer(
        context: context,
        userId: uid,
        moduleKey: 'fitness',
        title: 'Fitness Disclaimer',
        icon: Icons.fitness_center_rounded,
        body: 'Fitness features including AI-generated workout plans are for informational purposes only.\n\n'
            'Consult a healthcare professional before starting any new exercise program, especially if you have pre-existing health conditions.\n\n'
            'Stop exercising immediately if you feel pain, dizziness, or discomfort. This app does not provide professional fitness or medical advice.',
      );
    });
    _logSearchCtrl.addListener(() {
      final t = _logSearchCtrl.text;
      _logSearchDebounce.run(() {
        if (!mounted) return;
        setState(() => _logSearchQuery = t);
      });
    });
  }

  @override
  void dispose() {
    _logSearchCtrl.dispose();
    _logSearchDebounce.dispose();
    super.dispose();
  }

  Future<void> _getMotivation() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.fitness)) return;
    setState(() => _motivationLoading = true);

    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final db = provider.db;
    final family = provider.activeFamily;
    if (family == null) {
      if (mounted) setState(() => _motivationLoading = false);
      return;
    }
    final familyId = family.id;

    final logsCount = db.workoutSessions.where((l) => l.familyId == familyId).length;
    final habitsCount = db.dailyHabits.where((h) => h.familyId == familyId).length;

    final prompt = 'You are a supportive fitness coach. Keep it short and punchy.\n\n'
        'Provide a short, highly motivating message for a family with ${user?.name ?? 'someone'} '
        'who has logged $logsCount workouts and has $habitsCount daily habits. '
        'Keep it to 1-2 sentences, encouraging and personal.';

    try {
      final raw = await AiService.ask(prompt: prompt, feature: 'ai_fitness', familyId: familyId);
      if (mounted && raw != null) {
        provider.saveAiHistory(module: 'fitness', prompt: 'Generate fitness motivation message', response: raw);
        setState(() { _motivation = raw.trim(); _motivationLoading = false; });
      } else {
        if (mounted) setState(() => _motivationLoading = false);
      }
    } catch (e) {
      debugPrint('[Fitness] motivation error: $e');
      if (mounted) setState(() => _motivationLoading = false);
    }
  }

  Future<void> _loadWeeklyRecap({
    required List<WorkoutSession> mySessions,
    required int weekMinutes,
  }) async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.fitness)) return;
    setState(() => _weeklyRecapLoading = true);
    final provider = context.read<AppProvider>();
    final family = provider.activeFamily;
    final user = provider.activeUser;
    if (family == null || user == null) {
      if (mounted) setState(() => _weeklyRecapLoading = false);
      return;
    }
    final familyId = family.id;
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final inWeek = mySessions.where((s) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      return !d.isBefore(weekStart) && !d.isAfter(weekEnd);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final lines = <String>[];
    for (final s in inWeek.take(14)) {
      final exs = provider.db.workoutExercises.where((e) => e.sessionId == s.id).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      final names = exs.map((e) => e.exerciseName).take(5).join(', ');
      lines.add(
        '- ${DateFormat('EEE MMM d').format(s.date)}: ${s.title} (${s.durationMinutes} min)'
        '${names.isNotEmpty ? ' — $names' : ''}',
      );
    }

    final prompt = '''You are a concise fitness coach. Write a short weekly recap from the logged workouts below.

Stats: ${inWeek.length} session(s) this week, about $weekMinutes total minutes (from logs).

Sessions (newest first):
${lines.isEmpty ? '(none logged this week)' : lines.join('\n')}

Write 2-4 short paragraphs: (1) what went well or patterns you notice, (2) one concrete suggestion for next week, (3) optional recovery or consistency tip. Plain text only, no markdown.''';

    try {
      final raw = await AiService.ask(prompt: prompt, feature: 'ai_fitness', familyId: familyId);
      if (mounted) {
        provider.saveAiHistory(module: 'fitness', prompt: 'Weekly fitness recap', response: raw ?? '');
        setState(() {
          _weeklyRecap = (raw ?? '').trim();
          _weeklyRecapLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[Fitness] weekly recap: $e');
      if (mounted) setState(() => _weeklyRecapLoading = false);
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkoutSessionSheet(
        onSave: (session, exercises, sets) async {
          final provider = context.read<AppProvider>();
          await _persistCompletedWorkout(
            context,
            provider,
            session: session,
            exercises: exercises,
            sets: sets,
          );
        },
      ),
    );
  }

  void _showLogWeightSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogWeightSheet(
        onSave: (metric) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(
            db.copyWith(fitness: [...db.fitness, metric]),
            pushTableScope: {CloudSyncScope.fitness},
          );
        },
      ),
    );
  }

  Future<void> _toggleHealthWorkoutSync() async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    if (user == null) return;
    final on = user.settings['health_workout_sync'] == true;
    final nextSettings = Map<String, dynamic>.from(user.settings);
    if (on) {
      nextSettings.remove('health_workout_sync');
    } else {
      nextSettings['health_workout_sync'] = true;
    }
    final updatedUser = user.copyWith(settings: nextSettings);
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(
        users: db.users.map((u) => u.id == user.id ? updatedUser : u).toList(),
      ),
      pushTableScope: <String>{},
    );
    if (mounted) {
      _showSnack(
        context,
        on ? 'Health workout sync off' : 'Health workout sync on — new workouts will be saved to Apple Health / Health Connect',
      );
    }
  }

  void _showAiPlanSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiFitnessPlanSheet(
        onSavePlan: (planMap) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          final userId = provider.activeUser?.id;
          final family = provider.activeFamily;
          if (userId == null || family == null) return;
          await ExercisePlanMediaService.enrichPlanMap(planMap);
          final withId = ensureFitnessPlanHasId(Map<String, dynamic>.from(planMap));
          final plans = db.fitnessPlans.toList();
          plans.add({
            ...withId,
            'user_id': userId,
            'family_id': family.id,
            'created_at': DateTime.now().toIso8601String(),
          });
          await provider.saveAndSync(
            db.copyWith(fitnessPlans: plans),
            pushTableScope: {CloudSyncScope.fitnessPlans},
          );
          if (mounted) setState(() => _selectedPlanIndex = 0);
        },
      ),
    );
  }

  Future<void> _deleteLog(BuildContext context, String sessionId) async {
    final provider = this.context.read<AppProvider>();
    final session = provider.db.workoutSessions.cast<WorkoutSession?>().firstWhere(
      (s) => s?.id == sessionId,
      orElse: () => null,
    );
    final userId = provider.activeUser?.id;
    final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
    final canManage = session != null && userId != null && (session.userId == userId || isOwner);
    if (!canManage) {
      if (mounted) _showSnack(context, 'Only the workout owner or family owner can delete this log.');
      return;
    }
    final ok = await _confirmRemove(context, 'Delete Session', 'Remove this workout session?');
    if (!ok) return;
    final db = provider.db;
    final exerciseIdsToDelete =
        db.workoutExercises.where((e) => e.sessionId == sessionId).map((e) => e.id).toSet();
    final exercisesToKeep =
        db.workoutExercises.where((e) => e.sessionId != sessionId).toList();
    final setsToKeep =
        db.workoutSets.where((s) => !exerciseIdsToDelete.contains(s.exerciseId)).toList();
    final sessionsToKeep =
        db.workoutSessions.where((s) => s.id != sessionId).toList();

    await provider.saveAndSync(
      db.copyWith(
        workoutSessions: sessionsToKeep,
        workoutExercises: exercisesToKeep,
        workoutSets: setsToKeep,
      ),
      pushTableScope: CloudSyncScope.workoutSessionBundle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const ModuleFamilyLoadingScaffold();
    }

    final locale = context.read<LocaleService>().config;
    final unit = locale.useMetric ? 'kg' : 'lbs';

    final allSessions = provider.db.workoutSessions.where((s) => s.familyId == family.id).toList();
    final mySessions = allSessions.where((s) => s.userId == user.id).toList();
    final baseSessions = _filter == _FitnessFilter.mine ? mySessions : allSessions;
    final q = _logSearchQuery.trim().toLowerCase();
    final sessionsForList = q.isEmpty
        ? List<WorkoutSession>.from(baseSessions)
        : baseSessions.where((s) {
            if (s.title.toLowerCase().contains(q)) return true;
            return provider.db.workoutExercises
                .where((e) => e.sessionId == s.id)
                .any((e) => e.exerciseName.toLowerCase().contains(q));
          }).toList();
    sessionsForList.sort((a, b) => b.date.compareTo(a.date));

    final now = DateTime.now();

    // Weekly sessions
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekLogs = baseSessions.where((s) => s.date.isAfter(weekStart.subtract(const Duration(days: 1)))).toList();

    // Active streak
    int streak = 0;
    DateTime checkDate = DateTime(now.year, now.month, now.day);
    while (true) {
      final hasSession = baseSessions.any((s) =>
          s.date.year == checkDate.year &&
          s.date.month == checkDate.month &&
          s.date.day == checkDate.day);
      if (!hasSession) break;
      streak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    // Stored AI fitness plans (newest first)
    final myPlans = provider.db.fitnessPlans
        .whereType<Map>()
        .where((p) => p['user_id'] == user.id)
        .map((p) => Map<dynamic, dynamic>.from(p))
        .toList()
      ..sort((a, b) => fitnessPlanCreatedAt(b).compareTo(fitnessPlanCreatedAt(a)));
    final safePlanIndex = myPlans.isEmpty ? 0 : _selectedPlanIndex.clamp(0, myPlans.length - 1);
    if (myPlans.isNotEmpty && safePlanIndex != _selectedPlanIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedPlanIndex = safePlanIndex);
      });
    }
    final latestPlan = myPlans.isEmpty ? null : myPlans[safePlanIndex];

    // Weight data
    final weightMetrics = provider.db.fitness
        .where((m) => m.type == 'WEIGHT' && m.userId == user.id)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    String weightProgress;
    if (weightMetrics.length >= 2) {
      final diff = weightMetrics.last.value - weightMetrics.first.value;
      final sign = diff >= 0 ? '+' : '';
      weightProgress = '$sign${diff.toStringAsFixed(1)} $unit';
    } else if (weightMetrics.length == 1) {
      weightProgress = '${weightMetrics.first.value.toStringAsFixed(1)} $unit';
    } else {
      weightProgress = 'No data';
    }

    // Total minutes this week
    final weekMinutes = weekLogs.fold<int>(0, (sum, s) => sum + s.durationMinutes);

    return HuddleModuleScaffold(
      modulePath: '/fitness',
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Page Header ──
          PageHeader(
            title: screenTitleForModulePath('/fitness'),
            subtitle: 'Track workouts, weight & stay active together.',
            actions: [
              ActionChipButton(
                icon: Icons.fitness_center_rounded,
                label: 'Log Exercise',
                onTap: _showAddSheet,
              ),
              ActionChipButton(
                icon: user.settings['health_workout_sync'] == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: user.settings['health_workout_sync'] == true ? 'Health on' : 'Health',
                onTap: _toggleHealthWorkoutSync,
                backgroundColor: AppTheme.stone100,
                foregroundColor: AppTheme.stone700,
              ),
              ActionChipButton(
                icon: Icons.monitor_weight_outlined,
                label: 'Log Weight',
                onTap: _showLogWeightSheet,
                isPrimary: true,
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFFA8A29E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI-generated plans are for informational purposes only. Consult a healthcare professional before starting any exercise program.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFFA8A29E),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Builder(builder: (ctx) {
            final prs = provider.db.exercisePrs
                .where((p) => p.userId == user.id && p.familyId == family.id)
                .toList()
              ..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
            if (prs.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personal records',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Based on completed sets (volume uses weight × reps; kg or lb supported).',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 8),
                    ...prs.take(8).map((p) {
                      final label = p.exerciseKey;
                      String detail;
                      if (p.bestVolume != null && p.bestVolume! > 0) {
                        detail = 'Vol ${p.bestVolume!.toStringAsFixed(0)}';
                        if (p.bestWeight != null && p.bestWeight!.isNotEmpty) {
                          detail += ' · ${p.bestWeight}';
                        }
                      } else if (p.bestReps != null) {
                        detail = '${p.bestReps} reps';
                      } else {
                        detail = '—';
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              detail,
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),

          // ── Stats Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              _MiniStat(
                icon: Icons.monitor_weight_outlined,
                iconColor: AppTheme.primary,
                value: weightProgress,
                label: 'Weight',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.local_fire_department_rounded,
                iconColor: const Color(0xFFF97316),
                value: '$streak',
                label: 'Day Streak',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.timer_outlined,
                iconColor: const Color(0xFF22C55E),
                value: '${weekMinutes}m',
                label: 'This Week',
              ),
            ]),
          ),

          // ── AI Health Coach Card ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
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
                  Row(children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white.withValues(alpha: 0.9), size: 20),
                    const SizedBox(width: 8),
                    const Text('AI Health Coach',
                        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                  ]),
                  const SizedBox(height: 10),
                  if (_motivation != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('"$_motivation"',
                          style: TextStyle(
                              fontFamily: 'Inter', fontSize: 14, fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: 0.95), height: 1.5)),
                    ),
                    const SizedBox(height: 10),
                  ] else
                    Text(
                      'Get a motivation boost or generate a personalised fitness plan.',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white.withValues(alpha: 0.85), height: 1.5),
                    ),
                  const SizedBox(height: 14),
                  Row(children: [
                    GestureDetector(
                      onTap: _motivationLoading ? null : _getMotivation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: _motivationLoading
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
                            : const Text('Motivate Me',
                                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF6366F1))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showAiPlanSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('New Plan',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),

          // ── Weight Trend Chart ──
          if (weightMetrics.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.monitor_weight_outlined, size: 16, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 8),
                      const Text('Weight Trends',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.stone800)),
                    ]),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 5,
                            getDrawingHorizontalLine: (value) => FlLine(color: AppTheme.stone100, strokeWidth: 1),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: (weightMetrics.length / 4).ceilToDouble().clamp(1, double.infinity),
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= weightMetrics.length) return const SizedBox();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      DateFormat('MMM d').format(weightMetrics[idx].date),
                                      style: const TextStyle(fontSize: 9, color: AppTheme.stone400),
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) => Text(
                                  value.toStringAsFixed(0),
                                  style: const TextStyle(fontSize: 10, color: AppTheme.stone400),
                                ),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(
                                weightMetrics.length,
                                (i) => FlSpot(i.toDouble(), weightMetrics[i].value),
                              ),
                              isCurved: true,
                              color: AppTheme.primary,
                              barWidth: 3,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, percent, barData, index) =>
                                    FlDotCirclePainter(radius: 3, color: AppTheme.primary, strokeWidth: 0),
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppTheme.primary.withValues(alpha: 0.08),
                              ),
                            ),
                          ],
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipItems: (spots) => spots.map((s) =>
                                LineTooltipItem(
                                  '${s.y.toStringAsFixed(1)} $unit',
                                  const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white),
                                ),
                              ).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── AI Fitness Plan Section ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              const Text('AI Fitness Plan',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.stone900)),
              const Spacer(),
              GestureDetector(
                onTap: _showAiPlanSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('New Plan', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),
          if (myPlans.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Semantics(
                label: 'Select past AI fitness plan',
                child: DropdownButtonFormField<int>(
                  value: safePlanIndex,
                  decoration: InputDecoration(
                    labelText: 'Saved plans',
                    filled: true,
                    fillColor: AppTheme.stone50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: List.generate(myPlans.length, (i) {
                    final p = myPlans[i];
                    final dt = fitnessPlanCreatedAt(p);
                    final sum = (p['summary'] as String?)?.trim() ?? '';
                    final short = sum.isEmpty ? 'Plan' : (sum.length > 42 ? '${sum.substring(0, 42)}…' : sum);
                    return DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${DateFormat('MMM d, y').format(dt)} · $short',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                  onChanged: (i) {
                    if (i == null) return;
                    setState(() => _selectedPlanIndex = i);
                  },
                ),
              ),
            ),
          if (mySessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.insights_rounded, size: 18, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Weekly recap',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: _weeklyRecapLoading ? null : () => _loadWeeklyRecap(
                            mySessions: mySessions,
                            weekMinutes: weekMinutes,
                          ),
                          child: _weeklyRecapLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_weeklyRecap == null ? 'Get AI recap' : 'Refresh'),
                        ),
                      ],
                    ),
                    if (_weeklyRecap != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _weeklyRecap!,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13, height: 1.45, color: AppTheme.stone700),
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        '${weekLogs.length} session${weekLogs.length == 1 ? '' : 's'} this week · ~$weekMinutes min',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (latestPlan != null)
            _StoredPlanView(
              key: ValueKey('plan_${fitnessPlanStableId(latestPlan)}'),
              plan: latestPlan,
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: GestureDetector(
                onTap: _showAiPlanSheet,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Column(children: [
                    Icon(Icons.fitness_center_rounded, size: 32, color: AppTheme.primary.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    const Text("Tap 'New Plan' to get a personalised AI fitness plan based on your profile.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400, height: 1.5)),
                  ]),
                ),
              ),
            ),

          // ── Filter Tabs ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: AppTabBar(
              tabs: const ['My Logs', 'Family'],
              selectedIndex: _filter.index,
              onSelected: (i) => setState(() => _filter = _FitnessFilter.values[i]),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              controller: _logSearchCtrl,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search workouts or exercises…',
                hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
                suffixIcon: _logSearchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                        onPressed: () {
                          _logSearchCtrl.clear();
                          setState(() => _logSearchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: AppTheme.stone50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.stone200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.stone200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // ── Workout Logs ──
          if (sessionsForList.isEmpty)
            CatalogModuleEmptyState(
              modulePath: '/fitness',
              title: baseSessions.isEmpty
                  ? 'No workout sessions yet'
                  : 'No matches',
              subtitle: baseSessions.isEmpty
                  ? 'Log a structured workout session to see it here.'
                  : 'Try a different search.',
              actionLabel: baseSessions.isEmpty ? 'Log Exercise' : null,
              onAction: baseSessions.isEmpty ? _showAddSheet : null,
            )
          else
            ...sessionsForList.map((session) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Builder(builder: (ctx) {
                    final userId = provider.activeUser?.id;
                    final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
                    final canManage = userId != null && (session.userId == userId || isOwner);
                    return Dismissible(
                      key: ValueKey(session.id),
                      direction: canManage ? DismissDirection.endToStart : DismissDirection.none,
                      confirmDismiss: (_) async {
                        if (!canManage) return false;
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Session'),
                            content: const Text('Remove this workout session?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) => _deleteLog(context, session.id),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Delete',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.delete, color: Colors.white),
                          ],
                        ),
                      ),
                      child: _SessionCard(
                        session: session,
                        exercises: provider.db.workoutExercises
                            .where((e) => e.sessionId == session.id)
                            .toList()
                          ..sort((a, b) => a.order.compareTo(b.order)),
                        emoji: _activityEmoji(session.title),
                        memberName:
                            provider.displayNameForUserId(session.userId),
                        onDelete: canManage ? () => _deleteLog(context, session.id) : () {},
                      ),
                    );
                  }),
                )),
        ],
      ),
    );
  }
}

// ─── Mini Stat Card ───────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MiniStat({required this.icon, required this.iconColor, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone800,
                ), overflow: TextOverflow.ellipsis),
                Text(label, style: const TextStyle(
                  fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.stone400,
                )),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Stored Plan View ─────────────────────────────────────────────────────────

class _StoredPlanView extends StatefulWidget {
  final Map plan;
  const _StoredPlanView({super.key, required this.plan});

  @override
  State<_StoredPlanView> createState() => _StoredPlanViewState();
}

class _StoredPlanViewState extends State<_StoredPlanView> {
  int _expandedDay = 0;
  final _refineController = TextEditingController();
  bool _refining = false;
  bool _imageEnrichStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enrichPlanImagesIfNeeded());
  }

  /// Older plans or first-hit wger misses may lack thumbnails; fill once in background.
  Future<void> _enrichPlanImagesIfNeeded() async {
    if (_imageEnrichStarted || !mounted) {
      return;
    }
    final planMap = widget.plan; // FIXED: plan is always Map
    ExercisePlanMediaService.normalizeWeeklyPlanKey(planMap);
    final wp = planMap['weeklyPlan'] ?? planMap['weekly_plan'];
    if (wp is! List) {
      return;
    }
    var anyMissing = false;
    for (final day in wp) {
      if (day is! Map) {
        continue;
      }
      final exs = day['exercises'];
      if (exs is! List) {
        continue;
      }
      for (final e in exs) {
        if (e is! Map) {
          continue;
        }
        if ((_exerciseImageUrl(Map<String, dynamic>.from(e)) ?? '').isEmpty) { // FIXED: e promoted to Map
          anyMissing = true;
          break;
        }
      }
      if (anyMissing) {
        break;
      }
    }
    if (!anyMissing) {
      return;
    }
    _imageEnrichStarted = true;
    try {
      planMap['weeklyPlan'] ??= wp;
      await ExercisePlanMediaService.enrichWeeklyPlan(wp);
      if (!mounted) {
        return;
      }
      final provider = context.read<AppProvider>();
      final uid = provider.activeUser?.id;
      final db = provider.db;
      if (uid != null) {
        final plans = [...db.fitnessPlans];
        final sid = fitnessPlanStableId(planMap);
        final idx = plans.indexWhere((p) => p is Map && fitnessPlanStableId(p) == sid);
        if (idx >= 0) {
          plans[idx] = planMap;
          await provider.saveAndSync(
            db.copyWith(fitnessPlans: plans),
            pushTableScope: {CloudSyncScope.fitnessPlans},
          );
        } else {
          await provider.saveAndSync(
            db,
            pushTableScope: CloudSyncScope.fitnessFullBundle,
          );
        }
      } else {
        await provider.saveAndSync(
          db,
          pushTableScope: CloudSyncScope.fitnessFullBundle,
        );
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[Fitness] enrich plan images: $e');
    }
  }

  @override
  void dispose() {
    _refineController.dispose();
    super.dispose();
  }

  Future<void> _startGuidedPlanDay(BuildContext context, Map day) async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;
    final rawEx = (day['exercises'] as List?)?.cast<Map>() ?? [];
    if (rawEx.isEmpty) return;

    final dayName = day['day'] as String? ?? 'Day';
    final focus = day['focus'] as String? ?? 'Workout';
    final title = '$dayName · $focus';

    final exercises = <_GuidedPlanExercise>[];
    for (final ex in rawEx) {
      final name = ex['name'] as String? ?? 'Exercise';
      final detail = ex['detail'] as String?;
      final howTo = ex['howTo']?.toString().trim();
      final img = _exerciseImageUrl(ex)?.trim();
      final edb = _exerciseDbIdFromMap(ex);
      final (sc, rep) = _parseSetsRepsFromDetail(detail);
      exercises.add(_GuidedPlanExercise(
        name: name,
        detail: detail,
        howTo: (howTo == null || howTo.isEmpty) ? null : howTo,
        imageUrl: (img == null || img.isEmpty) ? null : img,
        exerciseDbId: (edb == null || edb.isEmpty) ? null : edb,
        setsCount: sc,
        defaultReps: rep,
        restSeconds: _parseRestSeconds(detail),
      ));
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => _GuidedPlanWorkoutScreen(
          title: title,
          exercises: exercises,
          onComplete: (session, wex, sets) async {
            await _persistCompletedWorkout(ctx, provider, session: session, exercises: wex, sets: sets);
            if (ctx.mounted) {
              _showSnack(ctx, 'Workout saved to My Logs');
            }
          },
        ),
      ),
    );
  }

  Future<void> _startPlanDayAsWorkout(BuildContext context, Map day) async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;
    final rawEx = (day['exercises'] as List?)?.cast<Map>() ?? [];
    if (rawEx.isEmpty) return;

    final dayName = day['day'] as String? ?? 'Day';
    final focus = day['focus'] as String? ?? 'Workout';
    final title = '$dayName · $focus';
    final fid = family.id;
    final uid = user.id;
    final now = DateTime.now();

    var totalMin = 0;
    final exercises = <WorkoutExercise>[];
    final sets = <WorkoutSet>[];

    final session = WorkoutSession(
      id: _uuid.v4(),
      familyId: fid,
      userId: uid,
      title: title,
      date: now,
      durationMinutes: 0,
      notes: null,
      createdAt: now,
    );

    for (var i = 0; i < rawEx.length; i++) {
      final ex = rawEx[i];
      final name = ex['name'] as String? ?? 'Exercise';
      final detail = ex['detail'] as String?;
      final howToRaw = ex['howTo']?.toString().trim();
      final imgRaw = _exerciseImageUrl(ex)?.trim();
      final edbId = _exerciseDbIdFromMap(ex);
      final (setCount, repNum) = _parseSetsRepsFromDetail(detail);
      totalMin += setCount * 3 + (setCount - 1);

      final we = WorkoutExercise(
        id: _uuid.v4(),
        familyId: fid,
        userId: uid,
        sessionId: session.id,
        exerciseName: name,
        order: i,
        restSeconds: 60,
        notes: detail,
        techniqueNotes: (howToRaw == null || howToRaw.isEmpty) ? null : howToRaw,
        referenceUrl: null,
        techniqueImageUrl: (imgRaw == null || imgRaw.isEmpty) ? null : imgRaw,
        exerciseDbId: (edbId == null || edbId.isEmpty) ? null : edbId,
        createdAt: now,
      );
      exercises.add(we);

      for (var s = 0; s < setCount; s++) {
        sets.add(
          WorkoutSet(
            id: _uuid.v4(),
            familyId: fid,
            userId: uid,
            exerciseId: we.id,
            setNumber: s + 1,
            reps: '$repNum',
            weight: null,
            completed: true,
            notes: null,
            createdAt: now,
          ),
        );
      }
    }

    final sessionDone = session.copyWith(durationMinutes: totalMin.clamp(5, 300));
    await _persistCompletedWorkout(
      context,
      provider,
      session: sessionDone,
      exercises: exercises,
      sets: sets,
    );
    if (context.mounted) {
      _showSnack(context, 'Logged in My Logs — tap the card for steps and illustration');
    }
  }

  Future<void> _refinePlan() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.fitness)) return;
    final request = _refineController.text.trim();
    if (request.isEmpty) {
      _showSnack(context, 'Please describe how to refine the plan');
      return;
    }
    setState(() => _refining = true);

    final currentPlanJson = jsonEncode(widget.plan);
    final profile = widget.plan['profile'] as Map? ?? {};

    final familyId = context.read<AppProvider>().activeFamily?.id;
    if (familyId == null) {
      if (mounted) setState(() => _refining = false);
      return;
    }
    final prompt = '''You are updating an existing weekly fitness plan based on a user's refinement request. Always respond with valid JSON only, no markdown fences.

Current plan (JSON):
$currentPlanJson

User's profile:
${profile.entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}

The user wants to make this change:
"$request"

Return the COMPLETE updated plan in the same JSON format as before (each exercise must include "name", "detail", and "howTo"). The app adds exercise illustrations automatically; omit "imageUrl" or leave it empty.

Apply the requested change while keeping everything else sensible.
''';

    try {
      final raw = await AiService.ask(prompt: prompt, feature: 'ai_fitness', familyId: familyId);
      if (raw == null || !mounted) {
        if (mounted) setState(() => _refining = false);
        return;
      }
      context.read<AppProvider>().saveAiHistory(module: 'fitness', prompt: 'Refine fitness plan: "$request"', response: raw);
      final cleaned = _stripFences(raw);
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        final provider = context.read<AppProvider>();
        final db = provider.db;
        final userId = provider.activeUser?.id ?? '';
        final familyId = provider.activeFamily?.id;
        if (familyId == null) {
          if (mounted) setState(() => _refining = false);
          return;
        }
        await ExercisePlanMediaService.enrichPlanMap(decoded);
        if (!mounted) return;
        final pid = widget.plan['plan_id']?.toString();
        final sid = fitnessPlanStableId(widget.plan);
        final plans = db.fitnessPlans.toList();
        plans.removeWhere((p) => p is Map && fitnessPlanStableId(p) == sid);
        plans.add({
          ...decoded,
          'plan_id': (pid != null && pid.isNotEmpty) ? pid : ensureFitnessPlanHasId(decoded)['plan_id'],
          'profile': profile,
          'user_id': userId,
          'family_id': familyId,
          'created_at': DateTime.now().toIso8601String(),
        });
        await provider.saveAndSync(
          db.copyWith(fitnessPlans: plans),
          pushTableScope: {CloudSyncScope.fitnessPlans},
        );

        if (mounted) {
          _refineController.clear();
          setState(() => _refining = false);
          _showSnack(context, 'Plan refined successfully!');
        }
      } else {
        if (mounted) setState(() => _refining = false);
      }
    } catch (e) {
      debugPrint('[Fitness] refine error: $e');
      if (mounted) {
        setState(() => _refining = false);
        _showSnack(context, 'Could not refine plan. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.plan['summary'] as String? ?? '';
    final weeklyPlan = (widget.plan['weeklyPlan'] ?? widget.plan['weekly_plan']) as List?;
    final weeklyPlanMaps = weeklyPlan?.whereType<Map>().toList() ?? <Map>[];
    final tips = (widget.plan['tips'] as List?)?.cast<String>() ?? [];
    final profile = widget.plan['profile'] as Map? ?? {};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Summary
        if (summary.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFEEF2FF), Color(0xFFF5F3FF)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(summary, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone700, height: 1.5)),
              if (profile.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (profile['location'] != null)
                    _planChip(profile['location'] as String, true),
                  if (profile['equipment'] is List)
                    ...(profile['equipment'] as List).map((e) => _planChip(e.toString(), false)),
                ]),
              ],
            ]),
          ),
        const SizedBox(height: 12),

        // Weekly Plan
        ...weeklyPlanMaps.asMap().entries.map((entry) {
          final i = entry.key;
          final day = entry.value;
          final dayName = day['day'] as String? ?? 'Day ${i + 1}';
          final focus = day['focus'] as String? ?? '';
          final duration = day['duration'] as String? ?? '';
          final exercises = (day['exercises'] as List?)?.cast<Map>() ?? [];
          final isRest = focus.toLowerCase().contains('rest') || focus.toLowerCase().contains('recovery');
          final isExpanded = _expandedDay == i;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _expandedDay = isExpanded ? -1 : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isExpanded ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.stone100),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: isRest ? const Color(0xFFDCFCE7) : AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(child: Text(
                          dayName.length >= 3 ? dayName.substring(0, 3) : dayName,
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11, color: isRest ? const Color(0xFF16A34A) : AppTheme.primary),
                        )),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(focus, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900)),
                        if (duration.isNotEmpty) Row(children: [
                          const Icon(Icons.schedule_rounded, size: 12, color: AppTheme.stone400),
                          const SizedBox(width: 3),
                          Text(duration, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                        ]),
                      ])),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more_rounded, color: AppTheme.stone400),
                      ),
                    ]),
                  ),
                  if (isExpanded && exercises.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(children: exercises.asMap().entries.map((ex) {
                        final idx = ex.key;
                        final exercise = ex.value;
                        final imgUrl = _exerciseImageUrl(exercise); // FIXED: List<Map> element
                        final edbId = _exerciseDbIdFromMap(exercise);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _exerciseIllustrationTile(imgUrl, exerciseDbId: edbId, size: 88),
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFC7D2FE), width: 0.5),
                                    ),
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 10, color: AppTheme.primary),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(exercise['name'] as String? ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone800)),
                              if (exercise['detail'] != null)
                                Text(exercise['detail'] as String, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                              if (exercise['howTo'] != null && (exercise['howTo'] as String).trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  exercise['howTo'] as String,
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500, height: 1.35),
                                ),
                              ],
                              if ((imgUrl == null || imgUrl.isEmpty) &&
                                  (edbId == null || edbId.isEmpty)) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'No illustration found for this name. Try a simpler name next time (e.g. "Push-up", "Squat").',
                                  style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400.withValues(alpha: 0.9), height: 1.3),
                                ),
                              ],
                            ])),
                          ]),
                        );
                      }).toList()),
                    ),
                  if (isExpanded && !isRest && exercises.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _startGuidedPlanDay(context, day),
                            icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                            label: const Text('Guided workout (rest timer)', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _startPlanDayAsWorkout(context, day),
                            icon: const Icon(Icons.fitness_center_rounded, size: 18),
                            label: const Text('Quick log this day', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
          );
        }),

        // Pro Tips
        if (tips.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 6),
                Text('Pro Tips', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF92400E))),
              ]),
              const SizedBox(height: 8),
              ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('• ', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFFB45309))),
                  Expanded(child: Text(t, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF92400E), height: 1.4))),
                ]),
              )),
            ]),
          ),
        ],

        // AI Refine section
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF6366F1)),
              SizedBox(width: 6),
              Text('Refine Plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF6366F1))),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _refineController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. "Replace squats with lunges" or "Add more cardio"',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC7D2FE))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC7D2FE))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _refining ? null : _refinePlan,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _refining
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Refine', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _planChip(String label, bool primary) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: primary ? const Color(0xFFEEF2FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: primary ? const Color(0xFFC7D2FE) : AppTheme.stone200),
    ),
    child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: primary ? AppTheme.primary : AppTheme.stone600)),
  );
}

// ─── AI Fitness Plan Sheet ────────────────────────────────────────────────────

class _AiFitnessPlanSheet extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onSavePlan;
  const _AiFitnessPlanSheet({required this.onSavePlan});

  @override
  State<_AiFitnessPlanSheet> createState() => _AiFitnessPlanSheetState();
}

class _AiFitnessPlanSheetState extends State<_AiFitnessPlanSheet> {
  String _gender = '';
  String _level = '';
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String _location = '';
  final List<String> _equipment = [];
  int _daysPerWeek = 5;
  bool _isGenerating = false;
  String? _error;

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _toggleEquipment(String item) {
    setState(() {
      if (item == 'Bodyweight Only') {
        _equipment.clear();
        _equipment.add(item);
      } else {
        _equipment.remove('Bodyweight Only');
        if (_equipment.contains(item)) {
          _equipment.remove(item);
        } else {
          _equipment.add(item);
        }
      }
    });
  }

  Future<void> _generate() async {
    if (SubscriptionModal.guardAI(context, kind: AiPaywallKind.fitness)) return;
    if (_gender.isEmpty || _level.isEmpty || _heightCtrl.text.trim().isEmpty || _weightCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields before generating.');
      return;
    }
    setState(() { _isGenerating = true; _error = null; });

    final workoutDays = _daysPerWeek;
    final restDays = 7 - workoutDays;
    final height = _heightCtrl.text.trim();
    final weight = _weightCtrl.text.trim();

    String locationLine = '';
    String equipmentLine = '';
    String homeNote = '';

    if (_location == 'Gym') {
      locationLine = '- Training location: Gym (full equipment available — machines, cables, free weights, etc.)';
    } else if (_location == 'Home') {
      locationLine = '- Training location: Home';
      if (_equipment.isNotEmpty) {
        equipmentLine = '- Available equipment: ${_equipment.join(", ")}\n  IMPORTANT: Only prescribe exercises that use this exact equipment. Do not suggest machines, cables, or gear not listed.';
      }
      homeNote = 'All exercises must be doable at home with only the listed equipment.';
    }

    final prompt = '''Create a detailed weekly fitness plan for someone with this profile:
- Gender: $_gender
- Height: $height cm
- Weight: $weight kg
- Fitness Level: $_level
- Available workout days per week: $workoutDays ($restDays rest/recovery day(s))
$locationLine
$equipmentLine

Provide a structured 7-day workout plan. The person can only train $workoutDays days per week — the remaining $restDays day(s) must be rest or light active recovery (stretching, walking). Spread the workout days sensibly throughout the week with adequate recovery between muscle groups. Each workout day should have a focus area, a list of exercises with sets/reps, and an estimated duration. Tailor the intensity to their fitness level ($_level). $homeNote

Return ONLY valid JSON (no markdown) with this structure:
{
  "summary": "brief overview of the plan",
  "weeklyPlan": [
    {
      "day": "Monday",
      "focus": "...",
      "duration": "45 minutes",
      "exercises": [
        {
          "name": "Barbell squat",
          "detail": "4 sets x 8 reps",
          "howTo": "3-5 short bullet steps: stance, brace core, path of movement, breathing, common mistake to avoid"
        }
      ]
    }
  ],
  "tips": ["tip 1", "tip 2", "tip 3"]
}

For every exercise, "howTo" is REQUIRED (plain text, not markdown). Use simple, standard exercise names (e.g. "Push-up", "Squat", "Romanian deadlift") so the app can match still images from the exercise database. Do not include video links.''';

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() { _isGenerating = false; _error = 'No active family'; });
        return;
      }
      final raw = await AiService.ask(
        prompt: 'You are a helpful fitness assistant. Respond with valid JSON only, no markdown or code fences.\n\n$prompt',
        feature: 'ai_fitness',
        familyId: familyId,
      );

      if (raw != null && mounted) {
        context.read<AppProvider>().saveAiHistory(module: 'fitness', prompt: 'Generate personalized fitness plan', response: raw);
        try {
          final cleaned = _stripFences(raw);
          final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
          parsed['profile'] = {
            'gender': _gender,
            'height': height,
            'weight': weight,
            'level': _level,
            'location': _location.isEmpty ? null : _location,
            'equipment': _equipment.isEmpty ? null : List<String>.from(_equipment),
            'daysPerWeek': _daysPerWeek,
          };
          await widget.onSavePlan(parsed);
          if (mounted) Navigator.pop(context);
          return;
        } catch (_) {
          await widget.onSavePlan({
            'summary': raw,
            'weeklyPlan': <Map>[],
            'tips': <String>[],
            'profile': {'gender': _gender, 'level': _level, 'location': _location},
          });
          if (mounted) Navigator.pop(context);
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isGenerating = false;
        _error = 'Failed to generate plan. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92, maxChildSize: 0.97, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              const Expanded(child: Text('AI Fitness Plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.stone900))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 22, color: AppTheme.stone400),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone100)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Tell us about yourself to generate a personalised fitness plan:', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600, height: 1.4)),
                  const SizedBox(height: 20),

                  // Gender
                  _sectionLabel('GENDER'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _toggleButton('\u{1F6B9}  Male', _gender == 'Male', () => setState(() => _gender = 'Male'))),
                    const SizedBox(width: 10),
                    Expanded(child: _toggleButton('\u{1F6BA}  Female', _gender == 'Female', () => setState(() => _gender = 'Female'))),
                  ]),
                  const SizedBox(height: 20),

                  // Fitness Level
                  _sectionLabel('FITNESS LEVEL'),
                  const SizedBox(height: 8),
                  Row(children: _fitnessLevels.map((l) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: l != _fitnessLevels.last ? 8 : 0),
                      child: _toggleButton(l, _level == l, () => setState(() => _level = l)),
                    ),
                  )).toList()),
                  const SizedBox(height: 20),

                  // Height
                  _sectionLabel('HEIGHT (CM)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _heightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _styledInput('e.g. 175'),
                  ),
                  const SizedBox(height: 20),

                  // Weight
                  _sectionLabel('WEIGHT (KG)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _styledInput('e.g. 80'),
                  ),
                  const SizedBox(height: 20),

                  // Workout Location
                  _sectionLabel('WHERE WILL YOU WORK OUT?'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _locationButton('\u{1F3CB}\u{FE0F}', 'Gym', 'Full equipment\navailable', _location == 'Gym', () => setState(() { _location = 'Gym'; _equipment.clear(); }))),
                    const SizedBox(width: 10),
                    Expanded(child: _locationButton('\u{1F3E0}', 'Home', 'Choose your\nequipment', _location == 'Home', () => setState(() { _location = 'Home'; _equipment.clear(); }))),
                  ]),

                  // Equipment (if Home)
                  if (_location == 'Home') ...[
                    const SizedBox(height: 20),
                    _sectionLabel('EQUIPMENT YOU HAVE AT HOME'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: _homeEquipment.map((e) {
                      final selected = _equipment.contains(e);
                      return GestureDetector(
                        onTap: () => _toggleEquipment(e),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200),
                          ),
                          child: Text(e, style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppTheme.stone600)),
                        ),
                      );
                    }).toList()),
                    const SizedBox(height: 4),
                    const Text('Select all equipment you have. The plan will only use what you pick.', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                  ],
                  const SizedBox(height: 20),

                  // Days per week
                  _sectionLabel('DAYS AVAILABLE TO WORK OUT'),
                  const SizedBox(height: 8),
                  Row(children: [2, 3, 4, 5, 6, 7].map((d) {
                    final selected = _daysPerWeek == d;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => setState(() => _daysPerWeek = d),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 48,
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.primary : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200, width: selected ? 2 : 1),
                            ),
                            child: Center(child: Text('$d', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: selected ? Colors.white : AppTheme.stone600))),
                          ),
                        ),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 4),
                  const Text('Remaining days will be rest or active recovery', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                ]),
              ),
              const SizedBox(height: 16),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.error)),
                ),

              // Generate button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generate,
                  icon: _isGenerating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_isGenerating ? 'Generating Your Plan...' : 'Generate My Fitness Plan',
                      style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppTheme.stone400),
  );

  Widget _toggleButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200),
        ),
        child: Center(child: Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: selected ? Colors.white : AppTheme.stone600))),
      ),
    );
  }

  Widget _locationButton(String emoji, String title, String subtitle, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: selected ? Colors.white : AppTheme.stone800)),
          const SizedBox(height: 2),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: selected ? Colors.white70 : AppTheme.stone400)),
        ]),
      ),
    );
  }
}

// ─── Workout Session Card ─────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final WorkoutSession session;
  final List<WorkoutExercise> exercises;
  final String emoji;
  final String memberName;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.exercises,
    required this.emoji,
    required this.memberName,
    required this.onDelete,
  });

  void _showExerciseDetail(BuildContext context, WorkoutExercise ex) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        expand: false,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                ex.exerciseName,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppTheme.stone900,
                ),
              ),
              if (ex.notes != null && ex.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(ex.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone600)),
              ],
              const SizedBox(height: 12),
              _exerciseIllustrationBanner(ex.techniqueImageUrl, exerciseDbId: ex.exerciseDbId),
              if (ex.techniqueNotes != null && ex.techniqueNotes!.trim().isNotEmpty) ...[
                const Text('How to do it', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  ex.techniqueNotes!,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.45, color: AppTheme.stone800),
                ),
                const SizedBox(height: 16),
              ] else ...[
                const Text(
                  'No written steps yet. Add notes when you log the workout, or open the AI plan for cues.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
                ),
                const SizedBox(height: 8),
              ],
              if ((ex.techniqueImageUrl == null || ex.techniqueImageUrl!.trim().isEmpty) &&
                  (ex.exerciseDbId == null || ex.exerciseDbId!.trim().isEmpty)) ...[
                const SizedBox(height: 4),
                Text(
                  'No illustration on file for this exercise.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400.withValues(alpha: 0.95)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: exercises.isEmpty ? null : () {
        if (exercises.length == 1) {
          _showExerciseDetail(context, exercises.first);
        } else {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => DraggableScrollableSheet(
              initialChildSize: 0.45,
              maxChildSize: 0.85,
              minChildSize: 0.3,
              expand: false,
              builder: (_, sc) => Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ListView.builder(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: exercises.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          session.title,
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      );
                    }
                    final ex = exercises[i - 1];
                    return ListTile(
                      title: Text(ex.exerciseName, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                      subtitle: ex.techniqueNotes != null && ex.techniqueNotes!.trim().isNotEmpty
                          ? Text(
                              ex.techniqueNotes!.split('\n').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12),
                            )
                          : const Text('Tap for steps or demo', style: TextStyle(fontFamily: 'Inter', fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showExerciseDetail(context, ex);
                      },
                    );
                  },
                ),
              ),
            ),
          );
        }
      },
      onLongPress: onDelete,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.stone900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Chip(label: '${session.durationMinutes} min', color: AppTheme.primary),
                      _Chip(label: memberName.split(' ').first, color: AppTheme.stone500),
                      if (exercises.isNotEmpty)
                        _Chip(
                          label: '${exercises.length} exercise${exercises.length == 1 ? '' : 's'} · tap for how-to',
                          color: const Color(0xFF6366F1),
                        ),
                    ],
                  ),
                  if (session.notes != null && session.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      session.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.stone400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  DateFormat('MMM d').format(session.date),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppTheme.stone400,
                  ),
                ),
                Text(
                  DateFormat('h:mm a').format(session.date),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.stone300,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );
}

// ─── Workout Session Sheet (Strong-like) ──────────────────────────────────

class _FitnessLogSheet extends StatefulWidget {
  // Strong integration: one session contains exercises, and each exercise contains sets.
  final Future<void> Function(
    WorkoutSession session,
    List<WorkoutExercise> exercises,
    List<WorkoutSet> sets,
  )
      onSave;

  const _FitnessLogSheet({required this.onSave});

  @override
  State<_FitnessLogSheet> createState() => _FitnessLogSheetState();
}

class _FitnessLogSheetState extends State<_FitnessLogSheet> {
  final _sessionTitleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _exerciseNameCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  bool _isSaving = false;

  int _setsCount = 3;
  int _restSeconds = 60;

  // Per-set user inputs
  late List<String> _reps;
  late List<String?> _weights;
  late List<bool> _completed;

  // Simple Strong-style rest timer between sets
  Timer? _restTimer;
  int _restRemaining = 0;

  @override
  void initState() {
    super.initState();
    _reps = List.generate(_setsCount, (_) => '');
    _weights = List.generate(_setsCount, (_) => null);
    _completed = List.generate(_setsCount, (_) => false);
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _sessionTitleCtrl.dispose();
    _notesCtrl.dispose();
    _exerciseNameCtrl.dispose();
    super.dispose();
  }

  void _syncSetListLengths(int newCount) {
    setState(() {
      _setsCount = newCount.clamp(1, 20);
      _reps = List.generate(_setsCount, (i) => i < _reps.length ? _reps[i] : '');
      _weights = List.generate(
        _setsCount,
        (i) => i < _weights.length ? _weights[i] : null,
      );
      _completed = List.generate(
        _setsCount,
        (i) => i < _completed.length ? _completed[i] : false,
      );
      // Reset timer if set list changed
      _restTimer?.cancel();
      _restTimer = null;
      _restRemaining = 0;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    setState(() {
      _restRemaining = _restSeconds;
    });

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_restRemaining <= 1) {
          _restRemaining = 0;
          timer.cancel();
        } else {
          _restRemaining -= 1;
        }
      });
    });
  }

  String _formatRest(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _save() async {
    final sessionTitle = _sessionTitleCtrl.text.trim();
    final exerciseName = _exerciseNameCtrl.text.trim();

    if (sessionTitle.isEmpty) {
      _showSnack(context, 'Please enter a workout title');
      return;
    }
    if (exerciseName.isEmpty) {
      _showSnack(context, 'Please enter an exercise name');
      return;
    }
    if (_setsCount <= 0) {
      _showSnack(context, 'Please set a valid number of sets');
      return;
    }
    for (var i = 0; i < _setsCount; i++) {
      final r = _reps[i].trim();
      if (r.isEmpty) {
        _showSnack(context, 'Set ${i + 1}: reps are required');
        return;
      }
    }

    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final fid = provider.activeFamily?.id ?? '';
    final uid = provider.activeUser?.id ?? '';
    final now = DateTime.now();

    ({String? imageUrl, String? exerciseDbId}) media = (imageUrl: null, exerciseDbId: null);
    try {
      media = await ExercisePlanMediaService.resolveForExerciseName(exerciseName);
    } catch (_) {}

    final session = WorkoutSession(
      id: _uuid.v4(),
      familyId: fid,
      userId: uid,
      title: sessionTitle,
      date: _date,
      durationMinutes: (_setsCount * 3) + (_restSeconds ~/ 60),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: now,
    );

    final exercise = WorkoutExercise(
      id: _uuid.v4(),
      familyId: fid,
      userId: uid,
      sessionId: session.id,
      exerciseName: exerciseName,
      order: 0,
      restSeconds: _restSeconds,
      notes: null,
      techniqueNotes: null,
      referenceUrl: null,
      techniqueImageUrl: (media.imageUrl == null || media.imageUrl!.isEmpty) ? null : media.imageUrl,
      exerciseDbId: (media.exerciseDbId == null || media.exerciseDbId!.isEmpty) ? null : media.exerciseDbId,
      createdAt: now,
    );

    final sets = <WorkoutSet>[];
    for (var i = 0; i < _setsCount; i++) {
      final weight = _weights[i];
      sets.add(
        WorkoutSet(
          id: _uuid.v4(),
          familyId: fid,
          userId: uid,
          exerciseId: exercise.id,
          setNumber: i + 1,
          reps: _reps[i].trim(),
          weight: (weight == null || weight.trim().isEmpty) ? null : weight.trim(),
          completed: _completed[i],
          notes: null,
          createdAt: now,
        ),
      );
    }

    await widget.onSave(session, [exercise], sets);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      maxChildSize: 0.98,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Workout Session',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppTheme.stone900,
                  ),
                ),
                TextButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                TextField(
                  controller: _sessionTitleCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration:
                      _styledInput('Workout title *', icon: Icons.sports_gymnastics),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _exerciseNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      _styledInput('Exercise *', icon: Icons.fitness_center_rounded),
                ),
                const SizedBox(height: 10),

                Row(children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('restSeconds'),
                      keyboardType: TextInputType.number,
                      initialValue: _restSeconds.toString(),
                      decoration: _styledInput(
                        'Rest seconds',
                        icon: Icons.timer_outlined,
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n == null) return;
                        setState(() => _restSeconds = n.clamp(10, 600));
                      },
                    ),
                  ),
                ]),

                const SizedBox(height: 14),

                // Sets count stepper
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sets',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppTheme.stone400,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: _setsCount <= 1 ? null : () => _syncSetListLengths(_setsCount - 1),
                          ),
                          Text(
                            '$_setsCount',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.stone900,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            onPressed: _setsCount >= 20 ? null : () => _syncSetListLengths(_setsCount + 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                if (_restRemaining > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_rounded, size: 18, color: AppTheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'Rest: ${_formatRest(_restRemaining)}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppTheme.stone900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Per-set inputs
                ...List.generate(_setsCount, (i) {
                  final setIndex = i;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Set ${i + 1}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppTheme.stone800,
                              ),
                            ),
                            const Spacer(),
                            if (_completed[i])
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                                ),
                                child: const Text(
                                  'Done',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          key: ValueKey('reps_$setIndex'),
                          keyboardType: TextInputType.number,
                          initialValue: _reps[setIndex],
                          decoration: _styledInput('Reps *'),
                          onChanged: (v) => _reps[setIndex] = v,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey('weight_$setIndex'),
                          keyboardType: TextInputType.number,
                          decoration: _styledInput('Weight (optional)'),
                          onChanged: (v) => _weights[setIndex] = v,
                          initialValue: _weights[setIndex] ?? '',
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _completed[i]
                                ? null
                                : () {
                                    setState(() => _completed[i] = true);
                                    _startRestTimer();
                                  },
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                            label: const Text('Complete set'),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 10),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: _styledInput('Notes (optional)'),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEE, MMM d, y').format(_date),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: AppTheme.stone800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Workout Session Sheet (Multi-Exercise Builder) ───────────────────────

class _WorkoutExerciseDraft {
  final String id;
  String name;
  String techniqueNotes;
  int setsCount;
  int restSeconds;
  final List<String> reps;
  final List<String?> weights;
  final List<bool> completed;

  _WorkoutExerciseDraft({
    required this.id,
    this.name = '',
  })  : techniqueNotes = '',
        setsCount = 3,
        restSeconds = 60,
        reps = <String>[],
        weights = <String?>[],
        completed = <bool>[] {
    syncSets(3); // FIXED: ctor defaults moved to initializers (unused optional params)
  }

  void syncSets(int newCount) {
    setsCount = newCount.clamp(1, 20).toInt();

    while (reps.length < setsCount) {
      reps.add('');
      weights.add(null);
      completed.add(false);
    }
    if (reps.length > setsCount) {
      reps.removeRange(setsCount, reps.length);
      weights.removeRange(setsCount, weights.length);
      completed.removeRange(setsCount, completed.length);
    }
  }
}

class _WorkoutSessionSheet extends StatefulWidget {
  final Future<void> Function(
    WorkoutSession session,
    List<WorkoutExercise> exercises,
    List<WorkoutSet> sets,
  )
      onSave;

  const _WorkoutSessionSheet({required this.onSave});

  @override
  State<_WorkoutSessionSheet> createState() => _WorkoutSessionSheetState();
}

class _WorkoutSessionSheetState extends State<_WorkoutSessionSheet> {
  final _sessionTitleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _newExerciseNameCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  bool _isSaving = false;

  final List<_WorkoutExerciseDraft> _exercises = [
    _WorkoutExerciseDraft(id: _uuid.v4()),
  ];

  // Rest timer state (starts after completing a set, stops when starting the next).
  Timer? _restTimer;
  int _restRemaining = 0;
  String? _restActiveExerciseId;
  int _restActiveCompletedSetIndex = -1;

  @override
  void dispose() {
    _restTimer?.cancel();
    _sessionTitleCtrl.dispose();
    _notesCtrl.dispose();
    _newExerciseNameCtrl.dispose();
    super.dispose();
  }

  void _cancelRestTimer() {
    _restTimer?.cancel();
    _restTimer = null;
    setState(() {
      _restRemaining = 0;
      _restActiveExerciseId = null;
      _restActiveCompletedSetIndex = -1;
    });
  }

  void _startRestTimer({
    required String exerciseId,
    required int completedSetIndex,
    required int durationSeconds,
  }) {
    _restTimer?.cancel();
    setState(() {
      _restActiveExerciseId = exerciseId;
      _restActiveCompletedSetIndex = completedSetIndex;
      _restRemaining = durationSeconds;
    });

    if (durationSeconds <= 0) return;

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_restRemaining <= 1) {
          _restRemaining = 0;
          timer.cancel();
          _restActiveExerciseId = null;
          _restActiveCompletedSetIndex = -1;
        } else {
          _restRemaining -= 1;
        }
      });
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  void _onAddExercise() {
    final name = _newExerciseNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _exercises.add(
        _WorkoutExerciseDraft(id: _uuid.v4(), name: name),
      );
      _newExerciseNameCtrl.clear();
    });
  }

  void _syncExerciseSetCount(int exerciseIndex, int newCount) {
    final ex = _exercises[exerciseIndex];
    ex.syncSets(newCount);

    if (_restActiveExerciseId == ex.id) {
      final nextSetIndex = _restActiveCompletedSetIndex + 1;
      if (nextSetIndex < 0 || nextSetIndex >= ex.setsCount) {
        _cancelRestTimer();
      }
    }
    setState(() {});
  }

  void _onStartNextSet({
    required _WorkoutExerciseDraft exercise,
    required int setIndex,
  }) {
    if (_restActiveExerciseId != exercise.id) return;
    final nextSetIndex = _restActiveCompletedSetIndex + 1;
    if (setIndex != nextSetIndex) return;
    _cancelRestTimer();
  }

  void _onCompleteSet({
    required _WorkoutExerciseDraft exercise,
    required int setIndex,
  }) {
    if (exercise.completed[setIndex]) return;

    setState(() {
      exercise.completed[setIndex] = true;
    });

    // Start rest after completing a set, except after the last set.
    if (setIndex < exercise.setsCount - 1) {
      _startRestTimer(
        exerciseId: exercise.id,
        completedSetIndex: setIndex,
        durationSeconds: exercise.restSeconds,
      );
    } else {
      _cancelRestTimer();
    }
  }

  String _formatRest(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _save() async {
    final sessionTitle = _sessionTitleCtrl.text.trim();
    if (sessionTitle.isEmpty) {
      _showSnack(context, 'Please enter a workout title');
      return;
    }

    if (_exercises.isEmpty) {
      _showSnack(context, 'Please add at least one exercise');
      return;
    }

    for (final ex in _exercises) {
      if (ex.name.trim().isEmpty) {
        _showSnack(context, 'Please name every exercise');
        return;
      }
      for (var i = 0; i < ex.setsCount; i++) {
        if (ex.reps[i].trim().isEmpty) {
          _showSnack(
            context,
            'Reps are required for ${ex.name} set ${i + 1}',
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    final provider = context.read<AppProvider>();
    final fid = provider.activeFamily?.id ?? '';
    final uid = provider.activeUser?.id ?? '';
    final now = DateTime.now();

    int totalMinutes = 0;
    for (final ex in _exercises) {
      final restMinutes = ex.restSeconds ~/ 60;
      totalMinutes += ex.setsCount * 3 + ((ex.setsCount - 1) * restMinutes);
    }

    final session = WorkoutSession(
      id: _uuid.v4(),
      familyId: fid,
      userId: uid,
      title: sessionTitle,
      date: _date,
      durationMinutes: totalMinutes,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: now,
    );

    final exercises = <WorkoutExercise>[];
    final sets = <WorkoutSet>[];

    for (var exIndex = 0; exIndex < _exercises.length; exIndex++) {
      final draft = _exercises[exIndex];
      ({String? imageUrl, String? exerciseDbId}) media = (imageUrl: null, exerciseDbId: null);
      try {
        media = await ExercisePlanMediaService.resolveForExerciseName(draft.name.trim());
      } catch (_) {}

      final exercise = WorkoutExercise(
        id: _uuid.v4(),
        familyId: fid,
        userId: uid,
        sessionId: session.id,
        exerciseName: draft.name.trim(),
        order: exIndex,
        restSeconds: draft.restSeconds,
        notes: null,
        techniqueNotes: draft.techniqueNotes.trim().isEmpty ? null : draft.techniqueNotes.trim(),
        referenceUrl: null,
        techniqueImageUrl: (media.imageUrl == null || media.imageUrl!.isEmpty) ? null : media.imageUrl,
        exerciseDbId: (media.exerciseDbId == null || media.exerciseDbId!.isEmpty) ? null : media.exerciseDbId,
        createdAt: now,
      );
      exercises.add(exercise);

      for (var setIndex = 0; setIndex < draft.setsCount; setIndex++) {
        final weightRaw = draft.weights[setIndex];
        sets.add(
          WorkoutSet(
            id: _uuid.v4(),
            familyId: fid,
            userId: uid,
            exerciseId: exercise.id,
            setNumber: setIndex + 1,
            reps: draft.reps[setIndex].trim(),
            weight: (weightRaw == null || weightRaw.trim().isEmpty)
                ? null
                : weightRaw.trim(),
            completed: draft.completed[setIndex],
            notes: null,
            createdAt: now,
          ),
        );
      }
    }

    await widget.onSave(session, exercises, sets);
    if (mounted) Navigator.pop(context);
  }

  Widget _exerciseCard(int exerciseIndex) {
    final ex = _exercises[exerciseIndex];
    final isRestActiveForThisExercise =
        _restActiveExerciseId == ex.id && _restRemaining > 0;
    final restNextSetIndex = _restActiveCompletedSetIndex + 1;
    final isNextSetBlocked =
        isRestActiveForThisExercise &&
        restNextSetIndex >= 0 &&
        restNextSetIndex < ex.setsCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.stone50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stone200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('exerciseName_${ex.id}'),
                  initialValue: ex.name,
                  decoration: _styledInput(
                    'Exercise name *',
                    icon: Icons.fitness_center_rounded,
                  ),
                  onChanged: (v) => setState(() => ex.name = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove exercise',
                onPressed: _exercises.length <= 1
                    ? null
                    : () {
                        if (_restActiveExerciseId == ex.id) {
                          _cancelRestTimer();
                        }
                        setState(() => _exercises.removeAt(exerciseIndex));
                      },
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.error),
              ),
            ],
          ),

          const SizedBox(height: 10),

          TextFormField(
            key: ValueKey('exerciseRest_${ex.id}'),
            keyboardType: TextInputType.number,
            initialValue: ex.restSeconds.toString(),
            decoration: _styledInput(
              'Rest seconds',
              icon: Icons.timer_outlined,
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n == null) return;
              setState(() => ex.restSeconds = n.clamp(10, 600).toInt());
            },
          ),

          const SizedBox(height: 10),

          TextFormField(
            key: ValueKey('exerciseHow_${ex.id}'),
            initialValue: ex.techniqueNotes,
            maxLines: 3,
            decoration: _styledInput(
              'How to (optional)',
              icon: Icons.menu_book_outlined,
            ).copyWith(
              hintText: 'Short steps: stance, movement, breathing…',
            ),
            onChanged: (v) => setState(() => ex.techniqueNotes = v),
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Sets',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.stone400,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.stone50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.stone200),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: ex.setsCount <= 1
                          ? null
                          : () => _syncExerciseSetCount(
                                exerciseIndex,
                                ex.setsCount - 1,
                              ),
                    ),
                    Text(
                      '${ex.setsCount}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.stone900,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: ex.setsCount >= 20
                          ? null
                          : () => _syncExerciseSetCount(
                                exerciseIndex,
                                ex.setsCount + 1,
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (isRestActiveForThisExercise) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_rounded, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Rest: ${_formatRest(_restRemaining)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppTheme.stone900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          ...List.generate(ex.setsCount, (setIndex) {
            final isNextSet = isRestActiveForThisExercise &&
                isNextSetBlocked &&
                setIndex == restNextSetIndex;
            final isDone = ex.completed[setIndex];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.stone200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Set ${setIndex + 1}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppTheme.stone800,
                        ),
                      ),
                      const Spacer(),
                      if (isDone)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey('reps_${ex.id}_$setIndex'),
                    keyboardType: TextInputType.number,
                    initialValue: ex.reps[setIndex],
                    decoration: _styledInput('Reps *'),
                    onChanged: (v) => setState(() => ex.reps[setIndex] = v),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('weight_${ex.id}_$setIndex'),
                    keyboardType: TextInputType.number,
                    decoration: _styledInput('Weight (optional)'),
                    initialValue: ex.weights[setIndex] ?? '',
                    onChanged: (v) =>
                        setState(() => ex.weights[setIndex] = v),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isDone && isNextSet) ...[
                          TextButton.icon(
                            onPressed: () => _onStartNextSet(
                              exercise: ex,
                              setIndex: setIndex,
                            ),
                            icon: const Icon(Icons.play_arrow_rounded,
                                size: 18),
                            label: const Text('Start set (stop rest)'),
                          ),
                          const SizedBox(height: 6),
                        ],
                        TextButton.icon(
                          onPressed: isDone || isNextSet
                              ? null
                              : () => _onCompleteSet(
                                    exercise: ex,
                                    setIndex: setIndex,
                                  ),
                          icon: const Icon(Icons.check_circle_outline_rounded,
                              size: 18),
                          label: const Text('Complete set'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.98,
      minChildSize: 0.55,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Workout Session',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppTheme.stone900,
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  TextField(
                    controller: _sessionTitleCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _styledInput(
                      'Workout title *',
                      icon: Icons.sports_gymnastics,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newExerciseNameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: _styledInput(
                            'Add exercise name',
                            icon: Icons.add_circle_outline_rounded,
                          ),
                          onSubmitted: (_) => _onAddExercise(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          tooltip: 'Add exercise',
                          color: Colors.white,
                          onPressed: _onAddExercise,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(_exercises.length, (i) => _exerciseCard(i)),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: _styledInput('Notes (optional)'),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: AppTheme.stone500,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat('EEE, MMM d, y').format(_date),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: AppTheme.stone800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Guided plan workout (rest timer between sets) ─────────────────────────

class _GuidedPlanExercise {
  _GuidedPlanExercise({
    required this.name,
    this.detail,
    this.howTo,
    this.imageUrl,
    this.exerciseDbId,
    required this.setsCount,
    required this.defaultReps,
    required this.restSeconds,
  });

  final String name;
  final String? detail;
  final String? howTo;
  final String? imageUrl;
  final String? exerciseDbId;
  final int setsCount;
  final int defaultReps;
  final int restSeconds;
}

class _GuidedPlanWorkoutScreen extends StatefulWidget {
  const _GuidedPlanWorkoutScreen({
    required this.title,
    required this.exercises,
    required this.onComplete,
  });

  final String title;
  final List<_GuidedPlanExercise> exercises;
  final Future<void> Function(WorkoutSession session, List<WorkoutExercise> exercises, List<WorkoutSet> sets) onComplete;

  @override
  State<_GuidedPlanWorkoutScreen> createState() => _GuidedPlanWorkoutScreenState();
}

class _GuidedPlanWorkoutScreenState extends State<_GuidedPlanWorkoutScreen> {
  final _uuid = const Uuid();
  late DateTime _startedAt;
  int _exerciseIndex = 0;
  int _setIndex = 0;
  final _repsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  Timer? _restTimer;
  int _restRemaining = 0;
  late List<List<({String reps, String? weight})>> _logged;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _logged = List.generate(widget.exercises.length, (_) => []);
    _primeFields();
  }

  void _primeFields() {
    final ex = widget.exercises[_exerciseIndex];
    _repsCtrl.text = ex.defaultReps.toString();
    _weightCtrl.clear();
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _cancelRest() {
    _restTimer?.cancel();
    _restTimer = null;
    setState(() => _restRemaining = 0);
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    if (seconds <= 0) return;
    setState(() => _restRemaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_restRemaining <= 1) {
          _restRemaining = 0;
          t.cancel();
          _restTimer = null;
        } else {
          _restRemaining -= 1;
        }
      });
    });
  }

  String _formatRest(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _finish() async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) return;

    final fid = family.id;
    final uid = user.id;
    final now = DateTime.now();
    final durationMin = now.difference(_startedAt).inMinutes.clamp(1, 600);

    final session = WorkoutSession(
      id: _uuid.v4(),
      familyId: fid,
      userId: uid,
      title: widget.title,
      date: now,
      durationMinutes: durationMin,
      notes: 'Guided from AI plan',
      createdAt: now,
    );

    final wex = <WorkoutExercise>[];
    final allSets = <WorkoutSet>[];

    for (var ei = 0; ei < widget.exercises.length; ei++) {
      final ge = widget.exercises[ei];
      ({String? imageUrl, String? exerciseDbId}) media = (imageUrl: null, exerciseDbId: null);
      try {
        media = await ExercisePlanMediaService.resolveForExerciseName(ge.name);
      } catch (_) {}

      final we = WorkoutExercise(
        id: _uuid.v4(),
        familyId: fid,
        userId: uid,
        sessionId: session.id,
        exerciseName: ge.name,
        order: ei,
        restSeconds: ge.restSeconds,
        notes: ge.detail,
        techniqueNotes: ge.howTo,
        referenceUrl: null,
        techniqueImageUrl: (ge.imageUrl != null && ge.imageUrl!.isNotEmpty)
            ? ge.imageUrl
            : ((media.imageUrl == null || media.imageUrl!.isEmpty) ? null : media.imageUrl),
        exerciseDbId: (ge.exerciseDbId != null && ge.exerciseDbId!.isNotEmpty)
            ? ge.exerciseDbId
            : ((media.exerciseDbId == null || media.exerciseDbId!.isEmpty) ? null : media.exerciseDbId),
        createdAt: now,
      );
      wex.add(we);

      final rows = _logged[ei];
      for (var si = 0; si < rows.length; si++) {
        final r = rows[si];
        allSets.add(
          WorkoutSet(
            id: _uuid.v4(),
            familyId: fid,
            userId: uid,
            exerciseId: we.id,
            setNumber: si + 1,
            reps: r.reps,
            weight: (r.weight == null || r.weight!.trim().isEmpty) ? null : r.weight!.trim(),
            completed: true,
            notes: null,
            createdAt: now,
          ),
        );
      }
    }

    await widget.onComplete(session, wex, allSets);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _completeSet() async {
    final ex = widget.exercises[_exerciseIndex];
    final reps = _repsCtrl.text.trim();
    if (reps.isEmpty) {
      _showSnack(context, 'Enter reps for this set');
      return;
    }
    final w = _weightCtrl.text.trim();
    setState(() {
      _logged[_exerciseIndex].add((reps: reps, weight: w.isEmpty ? null : w));
    });

    if (_setIndex < ex.setsCount - 1) {
      _setIndex++;
      _primeFields();
      _startRest(ex.restSeconds);
    } else if (_exerciseIndex < widget.exercises.length - 1) {
      _exerciseIndex++;
      _setIndex = 0;
      _primeFields();
      _cancelRest();
    } else {
      await _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercises[_exerciseIndex];
    final isLast =
        _exerciseIndex == widget.exercises.length - 1 && _setIndex == ex.setsCount - 1;

    return Scaffold(
      appBar: SubpageAppBar(
        title: widget.title,
        leading: SubpageLeading.close,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Exercise ${_exerciseIndex + 1} of ${widget.exercises.length}',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500),
              ),
              const SizedBox(height: 4),
              Text(
                ex.name,
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.stone900),
              ),
              if (ex.detail != null && ex.detail!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(ex.detail!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone600)),
              ],
              const SizedBox(height: 12),
              _exerciseIllustrationBanner(
                (ex.imageUrl != null && ex.imageUrl!.isNotEmpty) ? ex.imageUrl : null,
                exerciseDbId: ex.exerciseDbId,
              ),
              if (ex.howTo != null && ex.howTo!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('How to', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 6),
                Text(ex.howTo!, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.45)),
              ],
              const SizedBox(height: 20),
              Text(
                'Set ${_setIndex + 1} of ${ex.setsCount}',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _repsCtrl,
                keyboardType: TextInputType.number,
                decoration: _styledInput('Reps *', icon: Icons.repeat_rounded),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _weightCtrl,
                keyboardType: TextInputType.number,
                decoration: _styledInput('Weight (optional)', icon: Icons.scale_rounded),
              ),
              const SizedBox(height: 8),
              Text(
                'Rest between sets: ${ex.restSeconds}s',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _restRemaining > 0 ? null : _completeSet,
                icon: Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_rounded),
                label: Text(
                  isLast ? 'Finish & save' : 'Complete set',
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (_restRemaining > 0)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded, size: 40, color: AppTheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        _formatRest(_restRemaining),
                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900, fontSize: 36, color: AppTheme.stone900),
                      ),
                      const SizedBox(height: 8),
                      const Text('Rest', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _cancelRest,
                        child: const Text('Skip rest'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Log Weight Sheet ─────────────────────────────────────────────────────────

class _LogWeightSheet extends StatefulWidget {
  final Future<void> Function(FitnessMetric) onSave;
  const _LogWeightSheet({required this.onSave});

  @override
  State<_LogWeightSheet> createState() => _LogWeightSheetState();
}

class _LogWeightSheetState extends State<_LogWeightSheet> {
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  FitnessMetric? _lastWeight;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    final locale = context.read<LocaleService>().config;
    _unit = locale.useMetric ? 'kg' : 'lbs';
    final userId = provider.activeUser?.id;
    final weightMetrics = provider.db.fitness
        .where((m) => m.type == 'WEIGHT' && m.userId == userId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    _lastWeight = weightMetrics.isNotEmpty ? weightMetrics.first : null;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text.trim());
    if (weight == null || weight <= 0) {
      _showSnack(context, 'Please enter a valid weight');
      return;
    }

    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final metric = FitnessMetric(
      id: _uuid.v4(),
      userId: provider.activeUser?.id ?? '',
      type: 'WEIGHT',
      value: weight,
      date: _date,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(metric);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.monitor_weight_outlined, size: 16, color: AppTheme.primary),
            ),
            const SizedBox(width: 8),
            const Text('Log Weight', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.stone900)),
          ]),
          const SizedBox(height: 6),
          if (_lastWeight != null)
            Text(
              'Last: ${_lastWeight!.value.toStringAsFixed(1)} $_unit on ${DateFormat('MMM d').format(_lastWeight!.date)}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
            ),
          const SizedBox(height: 20),

          // Weight input
          TextField(
            controller: _weightCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            style: const TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.stone900),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.stone200),
              suffixText: _unit,
              suffixStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.stone400),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.stone200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppTheme.stone200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),
          const SizedBox(height: 12),

          // Notes
          TextField(
            controller: _notesCtrl,
            maxLines: 1,
            decoration: _styledInput('Notes (optional)'),
          ),
          const SizedBox(height: 12),

          // Date picker
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.stone50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.stone200),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                const SizedBox(width: 10),
                Text(DateFormat('EEE, MMM d, y').format(_date),
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save Weight', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
