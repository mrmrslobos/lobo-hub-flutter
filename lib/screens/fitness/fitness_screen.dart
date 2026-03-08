// lib/screens/fitness/fitness_screen.dart
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
      builder: (_) => _AiWorkoutPlanSheet(
        onSaveAsNote: (planText) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          final log = FitnessLog(
            id: const Uuid().v4(),
            familyId: provider.activeFamily!.id,
            userId: provider.activeUser!.id,
            activity: 'AI Plan',
            durationMinutes: 0,
            notes: planText,
            date: DateTime.now(),
          );
          await provider
              .saveAndSync(db.copyWith(fitnessLogs: [...db.fitnessLogs, log]));
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

    // Find AI plan logs
    final aiPlanLogs = shown.where((l) => l.activity == 'AI Plan').toList();
    final latestAiPlan = aiPlanLogs.isNotEmpty ? aiPlanLogs.first : null;

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
                const Text('AI Fitness Plan',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppTheme.stone900)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _showAiPlanSheet,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('New Plan',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: latestAiPlan != null && latestAiPlan.notes != null
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Text(latestAiPlan.notes!,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppTheme.stone700,
                            height: 1.6)),
                  )
                : Text(
                    'Generate a personalized workout plan tailored to your fitness goals and schedule.',
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppTheme.stone400,
                        height: 1.5),
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
// AI Workout Plan Banner
// ─────────────────────────────────────────────

class _AiPlanBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _AiPlanBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✨ AI Workout Plan',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white)),
              SizedBox(height: 2),
              Text('Generate a personalized plan based on your goals',
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              size: 16, color: Colors.white70),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AI Workout Plan Sheet
// ─────────────────────────────────────────────

class _AiWorkoutPlanSheet extends StatefulWidget {
  final Future<void> Function(String planText) onSaveAsNote;
  const _AiWorkoutPlanSheet({required this.onSaveAsNote});

  @override
  State<_AiWorkoutPlanSheet> createState() => _AiWorkoutPlanSheetState();
}

class _AiWorkoutPlanSheetState extends State<_AiWorkoutPlanSheet> {
  final _goalsCtrl = TextEditingController();
  double _daysPerWeek = 3;
  String _fitnessLevel = 'Beginner';
  bool _isGenerating = false;
  String? _plan;
  String? _error;
  bool _isSaving = false;

  static const _levels = ['Beginner', 'Intermediate', 'Advanced'];

  @override
  void dispose() {
    _goalsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final goals = _goalsCtrl.text.trim();
    if (goals.isEmpty) {
      setState(() => _error = 'Please describe your fitness goals.');
      return;
    }
    setState(() {
      _isGenerating = true;
      _error = null;
      _plan = null;
    });

    final result = await AiService.generateFitnessPlan(
      goals: goals,
      daysPerWeek: _daysPerWeek.round(),
      fitnessLevel: _fitnessLevel,
    );

    if (mounted) {
      setState(() {
        _isGenerating = false;
        if (result != null) {
          _plan = result;
        } else {
          _error = 'Failed to generate plan. Please try again.';
        }
      });
    }
  }

  Future<void> _saveAsNote() async {
    if (_plan == null) return;
    setState(() => _isSaving = true);
    await widget.onSaveAsNote(_plan!);
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
    }
  }

  void _copyToClipboard() {
    if (_plan == null) return;
    Clipboard.setData(ClipboardData(text: _plan!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plan copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              const Text('AI Workout Plan',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppTheme.stone900)),
            ]),
          ),
          Expanded(
            child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  // Goals field
                  TextField(
                    controller: _goalsCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Your Goals',
                      hintText: 'e.g. Lose 10 lbs, build muscle, improve endurance',
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.flag_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Days per week slider
                  Text(
                    'Days per week: ${_daysPerWeek.round()}',
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.stone700),
                  ),
                  Slider(
                    value: _daysPerWeek,
                    min: 2,
                    max: 6,
                    divisions: 4,
                    activeColor: AppTheme.primary,
                    label: '${_daysPerWeek.round()} days',
                    onChanged: (v) => setState(() => _daysPerWeek = v),
                  ),
                  const SizedBox(height: 8),
                  // Fitness level chips
                  const Text('Fitness Level',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.stone700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _levels.map((level) {
                      final selected = _fitnessLevel == level;
                      return ChoiceChip(
                        label: Text(level),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _fitnessLevel = level),
                        selectedColor: AppTheme.primaryLight,
                        labelStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.stone600,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Error message
                  if (_error != null) ...[
                    Text(_error!,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppTheme.error)),
                    const SizedBox(height: 8),
                  ],
                  // Generate button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generate,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                          _isGenerating ? 'Generating Plan...' : 'Generate Plan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  // Plan result
                  if (_plan != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                          const Text('Your Plan',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppTheme.stone800)),
                          TextButton.icon(
                            onPressed: _copyToClipboard,
                            icon: const Icon(Icons.copy_rounded, size: 15),
                            label: const Text('Copy'),
                            style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          _plan!,
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: AppTheme.stone700,
                              height: 1.6),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _saveAsNote,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.save_alt_rounded, size: 18),
                        label: Text(_isSaving
                            ? 'Saving...'
                            : 'Save as Note'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ]),
          ),
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
