// lib/screens/habits/habits_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

const _uuid = Uuid();

// ─── Helpers ──────────────────────────────────────────────────────────────────

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _calcStreak(DailyHabit habit, List<DailyHabitCompletion> all, String userId) {
  int streak = 0;
  DateTime check = DateTime.now().subtract(const Duration(days: 1));
  for (int i = 0; i < 365; i++) {
    final date = check.subtract(Duration(days: i));
    final done = all.any((c) => c.habitId == habit.id && c.userId == userId && _isSameDay(c.date, date));
    if (done) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

const List<String> _defaultEmojis = [
  '💪', '🏃', '🧘', '💧', '🥗', '📚', '✍️', '🎯',
  '🌅', '🛌', '🚴', '🏊', '🧠', '🎨', '🎵', '🙏',
  '💊', '🥤', '🌿', '✅',
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    final db = provider.db;

    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = DateTime.now();
    final allHabits = db.dailyHabits
        .where((h) => h.userId == user.id || h.isShared)
        .toList();

    final todayCompletions = db.habitCompletions
        .where((c) => c.userId == user.id && _isSameDay(c.date, today))
        .toList();

    final completed = allHabits
        .where((h) => todayCompletions.any((c) => c.habitId == h.id))
        .length;

    // Best streak across all habits
    int bestStreak = 0;
    for (final h in allHabits) {
      final s = _calcStreak(h, db.habitCompletions, user.id);
      if (s > bestStreak) bestStreak = s;
    }

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ──────────────────────────────────────────
            PageHeader(
              title: '\u{1F3AF} Daily Habits',
              subtitle: DateFormat('EEEE, MMMM d').format(today),
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'Add Habit',
                  onTap: () => _showAddHabitSheet(context, user, family, db, provider),
                  isPrimary: true,
                ),
              ],
            ),

            // ─── Stat cards ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.track_changes_rounded,
                  iconColor: AppTheme.primary,
                  value: '${allHabits.length}',
                  label: 'Habits',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.check_circle_rounded,
                  iconColor: AppTheme.success,
                  value: '$completed',
                  label: 'Done Today',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  value: '$bestStreak',
                  label: 'Best Streak',
                ),
              ]),
            ),

            // ─── Progress card ───────────────────────────────────
            if (allHabits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _ProgressCard(completed: completed, total: allHabits.length),
              ),

            // ─── Habit list ──────────────────────────────────────
            if (allHabits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '\u{1F3AF}',
                  title: 'Start Tracking Habits',
                  bullets: [
                    'Build positive daily routines',
                    'Track streaks and progress',
                    'Share habits with family members',
                  ],
                  actionLabel: '+ Add Habit',
                  onAction: () => _showAddHabitSheet(context, user, family, db, provider),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section header
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text('TODAY\'S HABITS', style: TextStyle(
                        fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                        color: AppTheme.stone400, letterSpacing: 1.1,
                      )),
                    ),
                    ...allHabits.map((habit) {
                      final isDone = todayCompletions.any((c) => c.habitId == habit.id);
                      final streak = _calcStreak(habit, db.habitCompletions, user.id);
                      return Dismissible(
                        key: ValueKey(habit.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Habit'),
                              content: Text('Delete "${habit.label}"?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          ) ?? false;
                        },
                        onDismissed: (_) async {
                          final updatedHabits = db.dailyHabits.where((h) => h.id != habit.id).toList();
                          final updatedCompletions = db.habitCompletions.where((c) => c.habitId != habit.id).toList();
                          await provider.saveAndSync(db.copyWith(dailyHabits: updatedHabits, habitCompletions: updatedCompletions));
                          if (context.mounted) _showSnack(context, 'Habit deleted');
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline_rounded, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                              )),
                            ],
                          ),
                        ),
                        child: _HabitCard(
                          habit: habit,
                          isDone: isDone,
                          streak: streak,
                          onToggle: () => _toggleCompletion(context, provider, db, habit, isDone, user, todayCompletions),
                          onLongPress: () => _showHabitOptions(context, provider, db, habit, user, family),
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Toggle completion ──────────────────────────────────────────────────────

  Future<void> _toggleCompletion(
    BuildContext context, AppProvider provider, AppDB db,
    DailyHabit habit, bool isDone, User user,
    List<DailyHabitCompletion> todayCompletions,
  ) async {
    List<DailyHabitCompletion> updated;
    if (isDone) {
      updated = db.habitCompletions
          .where((c) => !(c.habitId == habit.id && c.userId == user.id && _isSameDay(c.date, DateTime.now())))
          .toList();
    } else {
      final completion = DailyHabitCompletion(
        id: _uuid.v4(),
        habitId: habit.id,
        userId: user.id,
        date: DateTime.now(),
        completedAt: DateTime.now(),
      );
      updated = [...db.habitCompletions, completion];
    }
    await provider.saveAndSync(db.copyWith(habitCompletions: updated));
  }

  // ─── Habit options (edit / delete) ──────────────────────────────────────────

  Future<void> _showHabitOptions(
    BuildContext context, AppProvider provider, AppDB db,
    DailyHabit habit, User user, Family family,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(child: Text(habit.emoji, style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(habit.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
                    if (habit.frequency != null)
                      Text(
                        habit.frequency!.substring(0, 1).toUpperCase() + habit.frequency!.substring(1),
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                      ),
                  ]),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppTheme.stone100),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
              ),
              title: const Text('Edit Habit', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _showAddHabitSheet(context, user, family, db, provider, editHabit: habit);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
              ),
              title: const Text('Delete Habit', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.error)),
              onTap: () async {
                Navigator.pop(context);
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
                      const Text('Delete Habit', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
                    ]),
                    content: Text(
                      'Delete "${habit.title}" and all its history? This cannot be undone.',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final updated = db.dailyHabits.where((h) => h.id != habit.id).toList();
                final updatedCompletions = db.habitCompletions.where((c) => c.habitId != habit.id).toList();
                await provider.saveAndSync(db.copyWith(dailyHabits: updated, habitCompletions: updatedCompletions));
                if (context.mounted) _showSnack(context, 'Habit deleted');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Add / Edit habit ───────────────────────────────────────────────────────

  Future<void> _showAddHabitSheet(
    BuildContext context, User user, Family family, AppDB db, AppProvider provider,
    {DailyHabit? editHabit}
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddHabitSheet(
        editHabit: editHabit,
        onSave: (habit) async {
          List<DailyHabit> updatedHabits;
          if (editHabit != null) {
            updatedHabits = db.dailyHabits.map((h) => h.id == habit.id ? habit : h).toList();
          } else {
            updatedHabits = [...db.dailyHabits, habit];
          }
          await provider.saveAndSync(db.copyWith(dailyHabits: updatedHabits));
        },
        userId: user.id,
        familyId: family.id,
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
                )),
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

// ─── Progress Card ────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  final int completed;
  final int total;

  const _ProgressCard({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Today\'s Progress', style: TextStyle(
                fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15,
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$completed / $total', style: const TextStyle(
                  fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14,
                )),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            total == 0
                ? 'Add your first habit below!'
                : completed == total
                    ? '\u{1F389} All habits complete!'
                    : '${total - completed} habit${total - completed == 1 ? '' : 's'} remaining',
            style: TextStyle(
              fontFamily: 'Inter', color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Habit Card ───────────────────────────────────────────────────────────────

class _HabitCard extends StatelessWidget {
  final DailyHabit habit;
  final bool isDone;
  final int streak;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const _HabitCard({
    required this.habit,
    required this.isDone,
    required this.streak,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onToggle,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDone ? AppTheme.primaryLight : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDone ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.stone100,
            ),
          ),
          child: Row(children: [
            // Emoji icon badge
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isDone
                    ? AppTheme.primary.withValues(alpha: 0.12)
                    : AppTheme.stone50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(habit.emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),

            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.title,
                    style: TextStyle(
                      fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppTheme.stone900,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: AppTheme.stone400,
                    ),
                  ),
                  if (habit.description != null && habit.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      habit.description!,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(children: [
                    if (streak > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('\u{1F525}', style: TextStyle(fontSize: 10)),
                          const SizedBox(width: 3),
                          Text('$streak day${streak == 1 ? '' : 's'}', style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B),
                          )),
                        ]),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (habit.isShared) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.people_outline, size: 11, color: AppTheme.primary),
                          SizedBox(width: 3),
                          Text('Shared', style: TextStyle(
                            fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary,
                          )),
                        ]),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (habit.targetValue != null && habit.targetUnit != null)
                      Text(
                        '${habit.targetValue} ${habit.targetUnit}',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                      ),
                  ]),
                ],
              ),
            ),

            // Completion toggle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34, height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color: isDone ? AppTheme.primary : AppTheme.stone300,
                  width: 2,
                ),
              ),
              child: isDone
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                  : null,
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Add / Edit Habit Sheet ──────────────────────────────────────────────────

class _AddHabitSheet extends StatefulWidget {
  final DailyHabit? editHabit;
  final Future<void> Function(DailyHabit) onSave;
  final String userId;
  final String familyId;

  const _AddHabitSheet({
    required this.editHabit,
    required this.onSave,
    required this.userId,
    required this.familyId,
  });

  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _targetValueCtrl = TextEditingController();
  final _targetUnitCtrl = TextEditingController();

  String _emoji = '✅';
  String _frequency = 'daily';
  bool _isShared = false;
  bool _saving = false;

  bool get _isEditing => widget.editHabit != null;

  @override
  void initState() {
    super.initState();
    final h = widget.editHabit;
    if (h != null) {
      _emoji = h.emoji;
      _titleCtrl.text = h.title;
      _descCtrl.text = h.description ?? '';
      _frequency = h.frequency ?? 'daily';
      _isShared = h.isShared;
      _targetValueCtrl.text = h.targetValue?.toString() ?? '';
      _targetUnitCtrl.text = h.targetUnit ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _targetValueCtrl.dispose();
    _targetUnitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack(context, 'Please enter a habit name');
      return;
    }
    setState(() => _saving = true);

    final habit = DailyHabit(
      id: widget.editHabit?.id ?? _uuid.v4(),
      familyId: widget.familyId,
      userId: widget.userId,
      label: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      icon: _emoji,
      frequency: _frequency,
      isShared: _isShared,
      targetValue: int.tryParse(_targetValueCtrl.text.trim()),
      targetUnit: _targetUnitCtrl.text.trim().isEmpty ? null : _targetUnitCtrl.text.trim(),
      createdAt: widget.editHabit?.createdAt ?? DateTime.now(),
    );

    await widget.onSave(habit);
    if (mounted) {
      Navigator.pop(context);
      _showSnack(context, _isEditing ? 'Habit updated' : 'Habit added!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with icon badge
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.track_changes_rounded, size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isEditing ? 'Edit Habit' : 'New Habit',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Emoji picker
                  const Text('Icon', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  _EmojiPicker(
                    selected: _emoji,
                    onSelect: (e) => setState(() => _emoji = e),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  const Text('Habit Name', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  _buildInput(_titleCtrl, 'e.g. Drink water'),
                  const SizedBox(height: 16),

                  // Description
                  const Text('Description (optional)', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  _buildInput(_descCtrl, 'A short note about this habit'),
                  const SizedBox(height: 20),

                  // Frequency
                  const Text('Frequency', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  _FrequencySelector(
                    selected: _frequency,
                    onSelect: (f) => setState(() => _frequency = f),
                  ),
                  const SizedBox(height: 20),

                  // Target
                  const Text('Target (optional)', style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700,
                  )),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _buildInput(_targetValueCtrl, '8', keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildInput(_targetUnitCtrl, 'glasses')),
                  ]),
                  const SizedBox(height: 20),

                  // Share toggle
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.people_outline_rounded, size: 16, color: AppTheme.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                        Text('Share with family', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                        Text('Family members can see this habit', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                      ])),
                      Switch.adaptive(
                        value: _isShared,
                        activeColor: AppTheme.primary,
                        onChanged: (v) => setState(() => _isShared = v),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Save button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                          : Text(
                              _isEditing ? 'Save Changes' : 'Add Habit',
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15),
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

  Widget _buildInput(TextEditingController ctrl, String hint, {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      textCapitalization: keyboardType == TextInputType.text ? TextCapitalization.sentences : TextCapitalization.none,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.stone300, fontFamily: 'Inter', fontSize: 14),
        filled: true,
        fillColor: AppTheme.stone50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.stone200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.stone200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Emoji Picker ─────────────────────────────────────────────────────────────

class _EmojiPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _EmojiPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 10,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: _defaultEmojis.length,
      itemBuilder: (_, i) {
        final emoji = _defaultEmojis[i];
        final isSelected = emoji == selected;
        return GestureDetector(
          onTap: () => onSelect(emoji),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryLight : AppTheme.stone50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.stone200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18))),
          ),
        );
      },
    );
  }
}

// ─── Frequency Selector ───────────────────────────────────────────────────────

class _FrequencySelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  static const _options = [
    ('daily', 'Daily'),
    ('weekdays', 'Weekdays'),
    ('weekends', 'Weekends'),
  ];

  const _FrequencySelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((opt) {
        final (value, label) = opt;
        final isSelected = value == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: opt != _options.last ? 8 : 0),
            child: GestureDetector(
              onTap: () => onSelect(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : AppTheme.stone50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.stone200,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.stone600,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
