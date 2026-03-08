// lib/screens/fitness/fitness_screen.dart

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class FitnessScreen extends StatefulWidget {
  const FitnessScreen({super.key});

  @override
  State<FitnessScreen> createState() => _FitnessScreenState();
}

enum _FitnessFilter { all, mine }

class _FitnessScreenState extends State<FitnessScreen> {
  _FitnessFilter _filter = _FitnessFilter.mine;

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FitnessLogSheet(
        onSave: (log) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider
              .saveAndSync(db.copyWith(fitnessLogs: [...db.fitnessLogs, log]));
        },
      ),
    );
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
          final userId = provider.activeUser!.id;
          // Replace existing plan for this user, or add new
          final plans = db.fitnessPlans.toList();
          plans.removeWhere((p) => p is Map && p['userId'] == userId);
          plans.add({...planMap, 'userId': userId, 'createdAt': DateTime.now().toIso8601String()});
          await provider.saveAndSync(db.copyWith(fitnessPlans: plans));
        },
      ),
    );
  }

  Future<void> _deleteLog(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
        fitnessLogs: db.fitnessLogs.where((l) => l.id != id).toList()));
  }

  String _activityEmoji(String activity) {
    final a = activity.toLowerCase();
    if (a.contains('run')) return '🏃';
    if (a.contains('walk')) return '🚶';
    if (a.contains('swim')) return '🏊';
    if (a.contains('bike') || a.contains('cycl')) return '🚴';
    if (a.contains('yoga')) return '🧘';
    if (a.contains('weight') || a.contains('lift')) return '🏋️';
    if (a.contains('hike')) return '🥾';
    return '💪';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final allLogs =
        provider.db.fitnessLogs.where((l) => l.familyId == family.id).toList();

    final shown = _filter == _FitnessFilter.mine
        ? allLogs.where((l) => l.userId == user.id).toList()
        : allLogs;
    shown.sort((a, b) => b.date.compareTo(a.date));

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekLogs = shown
        .where((l) =>
            l.date.isAfter(weekStart.subtract(const Duration(days: 1))))
        .toList();

    // Calculate active streak (consecutive days with logs)
    int streak = 0;
    DateTime checkDate = DateTime(now.year, now.month, now.day);
    while (true) {
      final hasLog = shown.any((l) =>
          l.date.year == checkDate.year &&
          l.date.month == checkDate.month &&
          l.date.day == checkDate.day);
      if (!hasLog) break;
      streak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    // Find stored AI fitness plan for current user
    final storedPlan = provider.db.fitnessPlans
        .whereType<Map>()
        .where((p) => p['userId'] == user.id)
        .toList();
    final latestPlan = storedPlan.isNotEmpty ? storedPlan.last : null;

    // Weight progress placeholder
    const weightProgress = '+0.0 kg';

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppTheme.stone700),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('FamilyHub',
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500),
              onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ── Page Header ──
          PageHeader(
            title: 'Fitness & Health',
            subtitle: 'Track your vitals and stay active together.',
            actions: [
              ActionChipButton(
                icon: Icons.monitor_weight_outlined,
                label: 'Metric Value...',
                onTap: _showAddSheet,
                backgroundColor: AppTheme.stone100,
                foregroundColor: AppTheme.stone700,
              ),
              ActionChipButton(
                icon: Icons.fitness_center_rounded,
                label: 'Log Weight',
                onTap: _showAddSheet,
                isPrimary: true,
              ),
            ],
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
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: Colors.white.withOpacity(0.9), size: 20),
                      const SizedBox(width: 8),
                      const Text('AI Health Coach',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Click the button for a personalized motivation boost based on your recent activity.',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _showAiPlanSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Get Motivation',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF6366F1))),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Stats Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WEIGHT PROGRESS',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.stone400,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 6),
                        const Text(weightProgress,
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ACTIVE STREAK',
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.stone400,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 6),
                        Text('$streak days',
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── AI Fitness Plan Section ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text('AI Fitness Plan',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.stone900)),
                const Spacer(),
                GestureDetector(
                  onTap: _showAiPlanSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('New Plan', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          if (latestPlan != null)
            _StoredPlanView(plan: latestPlan)
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
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Column(children: [
                    Icon(Icons.fitness_center_rounded, size: 32, color: AppTheme.primary.withOpacity(0.5)),
                    const SizedBox(height: 8),
                    const Text("Click 'New Plan' to get a personalised AI fitness plan based on your profile.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400, height: 1.5)),
                  ]),
                ),
              ),
            ),

          // ── Filter Tabs ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: AppTabBar(
              tabs: const ['My Logs', 'Family'],
              selectedIndex: _filter.index,
              onSelected: (i) =>
                  setState(() => _filter = _FitnessFilter.values[i]),
            ),
          ),

          // ── Workout Logs ──
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: EmptyState(
                emoji: '💪',
                title: 'No fitness logs',
                subtitle: 'Track your workouts and activities.',
                actionLabel: 'Add Log',
                onAction: _showAddSheet,
              ),
            )
          else
            ...shown.map((log) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _LogCard(
                    log: log,
                    emoji: _activityEmoji(log.activity),
                    memberName:
                        provider.userById(log.userId)?.name ?? 'Member',
                    onDelete: () => _deleteLog(log.id),
                  ),
                )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stored Plan View (inline on fitness page)
// ─────────────────────────────────────────────

class _StoredPlanView extends StatefulWidget {
  final Map plan;
  const _StoredPlanView({required this.plan});

  @override
  State<_StoredPlanView> createState() => _StoredPlanViewState();
}

class _StoredPlanViewState extends State<_StoredPlanView> {
  int _expandedDay = 0;

  @override
  Widget build(BuildContext context) {
    final summary = widget.plan['summary'] as String? ?? '';
    final weeklyPlan = (widget.plan['weeklyPlan'] as List?)?.cast<Map>() ?? [];
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
              gradient: LinearGradient(colors: [const Color(0xFFEEF2FF), const Color(0xFFF5F3FF)]),
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
        ...weeklyPlan.asMap().entries.map((entry) {
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
                  border: Border.all(color: isExpanded ? AppTheme.primary.withOpacity(0.3) : AppTheme.stone100),
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
                      Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppTheme.stone400),
                    ]),
                  ),
                  if (isExpanded && exercises.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(children: exercises.asMap().entries.map((ex) {
                        final idx = ex.key;
                        final exercise = ex.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
                              child: Center(child: Text('${idx + 1}', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: AppTheme.primary))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(exercise['name'] as String? ?? '', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone800)),
                              if (exercise['detail'] != null)
                                Text(exercise['detail'] as String, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                            ])),
                          ]),
                        );
                      }).toList()),
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
              Row(children: const [
                Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 6),
                Text('Pro Tips', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF92400E))),
              ]),
              const SizedBox(height: 8),
              ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('- ', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFFB45309))),
                  Expanded(child: Text(t, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF92400E), height: 1.4))),
                ]),
              )),
            ]),
          ),
        ],
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

// ─────────────────────────────────────────────
// AI Fitness Plan Sheet (Vite-style form)
// ─────────────────────────────────────────────

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

  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];
  static const _homeEquipment = [
    'Dumbbells', 'Resistance Bands', 'Barbell & Plates', 'Pull-up Bar',
    'Kettlebell', 'Bench', 'Jump Rope', 'Bodyweight Only',
  ];

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
    { "day": "Monday", "focus": "...", "duration": "45 minutes", "exercises": [{ "name": "...", "detail": "4 sets x 8 reps" }] }
  ],
  "tips": ["tip 1", "tip 2", "tip 3"]
}''';

    try {
      final raw = await AiService.ask(
        prompt: prompt,
        module: 'fitness',
        systemPrompt: 'You are a certified personal trainer. Respond with valid JSON only, no markdown or code fences.',
      );

      if (raw != null && mounted) {
        // Try to parse as JSON
        try {
          // Strip markdown code fences if present
          String cleaned = raw.trim();
          if (cleaned.startsWith('```')) {
            cleaned = cleaned.replaceFirst(RegExp(r'^```\w*\n?'), '').replaceFirst(RegExp(r'\n?```$'), '');
          }
          final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
          // Save the plan with profile info
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
          // If JSON parse fails, save as plain text summary
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
              // Intro
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
                  Row(children: _levels.map((l) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: l != _levels.last ? 8 : 0),
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
                    decoration: InputDecoration(
                      hintText: 'e.g. 175',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Weight
                  _sectionLabel('WEIGHT (KG)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _weightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'e.g. 80',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
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
                        child: Container(
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
                          child: Container(
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      child: Container(
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
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

// ─────────────────────────────────────────────
// Log Card
// ─────────────────────────────────────────────

class _LogCard extends StatelessWidget {
  final FitnessLog log;
  final String emoji;
  final String memberName;
  final VoidCallback onDelete;

  const _LogCard(
      {required this.log,
      required this.emoji,
      required this.memberName,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Log'),
          content: const Text('Remove this fitness log?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: AppTheme.error))),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12)),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(log.activity,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.stone900)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _Chip(label: '${log.durationMinutes} min', color: AppTheme.primary),
              if (log.caloriesBurned != null)
                _Chip(
                    label: '${log.caloriesBurned} cal', color: AppTheme.error),
              _Chip(
                  label: memberName.split(' ').first,
                  color: AppTheme.stone500),
            ]),
            if (log.notes != null && log.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(log.notes!,
                  style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppTheme.stone400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('MMM d').format(log.date),
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppTheme.stone400)),
            Text(DateFormat('h:mm a').format(log.date),
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.stone300)),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color)),
      );
}

// ─────────────────────────────────────────────
// Fitness Log Sheet (unchanged)
// ─────────────────────────────────────────────

class _FitnessLogSheet extends StatefulWidget {
  final Future<void> Function(FitnessLog) onSave;
  const _FitnessLogSheet({required this.onSave});

  @override
  State<_FitnessLogSheet> createState() => _FitnessLogSheetState();
}

class _FitnessLogSheetState extends State<_FitnessLogSheet> {
  final _activityCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _suggestions = [
    'Running',
    'Walking',
    'Swimming',
    'Cycling',
    'Yoga',
    'Weight Training',
    'HIIT',
    'Hiking'
  ];

  @override
  void dispose() {
    _activityCtrl.dispose();
    _durationCtrl.dispose();
    _caloriesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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

  Future<void> _save() async {
    if (_activityCtrl.text.trim().isEmpty ||
        _durationCtrl.text.trim().isEmpty) return;
    final duration = int.tryParse(_durationCtrl.text);
    if (duration == null || duration <= 0) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final log = FitnessLog(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      activity: _activityCtrl.text.trim(),
      durationMinutes: duration,
      caloriesBurned: int.tryParse(_caloriesCtrl.text),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      date: _date,
    );
    await widget.onSave(log);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Log Workout',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: AppTheme.stone900)),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
          ),
          Expanded(
            child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  TextField(
                    controller: _activityCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Activity *',
                        prefixIcon: Icon(Icons.fitness_center_rounded)),
                  ),
                  const SizedBox(height: 8),
                  // Quick suggestions
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _suggestions
                          .map((s) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _activityCtrl.text = s),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _activityCtrl.text == s
                                          ? AppTheme.primaryLight
                                          : AppTheme.stone100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(s,
                                        style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.stone700)),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _durationCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Duration (min) *',
                            prefixIcon: Icon(Icons.timer_outlined)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _caloriesCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Calories (optional)',
                            prefixIcon:
                                Icon(Icons.local_fire_department_rounded)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          alignLabelWithHint: true)),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.stone200)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppTheme.stone500),
                        const SizedBox(width: 10),
                        Text(DateFormat('EEE, MMM d, y').format(_date),
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: AppTheme.stone800)),
                      ]),
                    ),
                  ),
                ]),
          ),
        ]),
      ),
    );
  }
}
