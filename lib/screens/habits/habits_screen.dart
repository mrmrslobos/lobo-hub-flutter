// lib/screens/habits/habits_screen.dart
// Daily Habits tracker screen for FamilyHub

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

/// Count consecutive completed days ending yesterday (streak before today).
int _calcStreak(
  DailyHabit habit,
  List<DailyHabitCompletion> allCompletions,
  String userId,
) {
  int streak = 0;
  DateTime check = DateTime.now().subtract(const Duration(days: 1));

  for (int i = 0; i < 365; i++) {
    final date = check.subtract(Duration(days: i));
    final done = allCompletions.any(
      (c) => c.habitId == habit.id && c.userId == userId && _isSameDay(c.date, date),
    );
    if (done) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
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
      return const Scaffold(
        body: Center(child: Text('Please log in to view habits.')),
      );
    }

    final today = DateTime.now();
    final allHabits = db.dailyHabits
        .where(
          (h) => h.userId == user.id || h.isShared,
        )
        .toList();

    final todayCompletions = db.habitCompletions
        .where(
          (c) => c.userId == user.id && _isSameDay(c.date, today),
        )
        .toList();

    final completed = allHabits
        .where((h) => todayCompletions.any((c) => c.habitId == h.id))
        .length;

    return Scaffold(
      backgroundColor: AppTheme.background,
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
            const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: const [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: '\u{1F3AF} Daily Habits',
              subtitle: DateFormat('EEEE, MMMM d').format(DateTime.now()),
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'Add Habit',
                  onTap: () => _showAddHabitSheet(context, user, family, db, provider),
                ),
              ],
            ),

            // ── Progress card ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _ProgressCard(
                completed: completed,
                total: allHabits.length,
              ),
            ),

            // ── Habit list ──
            if (allHabits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OnboardingCard(
                  emoji: '\u{1F3AF}',
                  title: 'Start Tracking Habits',
                  bullets: ['Build positive daily routines', 'Track streaks and progress', 'Share habits with family members'],
                  actionLabel: '+ Add Habit',
                  onAction: () => _showAddHabitSheet(context, user, family, db, provider),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: allHabits.map((habit) {
                    final isDone = todayCompletions.any((c) => c.habitId == habit.id);
                    final streak = _calcStreak(
                      habit,
                      db.habitCompletions,
                      user.id,
                    );
                    return _HabitCard(
                      habit: habit,
                      isDone: isDone,
                      streak: streak,
                      onToggle: () => _toggleCompletion(
                        context,
                        provider,
                        db,
                        habit,
                        isDone,
                        user,
                        todayCompletions,
                      ),
                      onLongPress: () => _showHabitOptions(
                        context,
                        provider,
                        db,
                        habit,
                        user,
                        family,
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Toggle completion ──────────────────────────────────────────────────────

  Future<void> _toggleCompletion(
    BuildContext context,
    AppProvider provider,
    AppDB db,
    DailyHabit habit,
    bool isDone,
    User user,
    List<DailyHabitCompletion> todayCompletions,
  ) async {
    List<DailyHabitCompletion> updated;

    if (isDone) {
      // Remove today's completion
      updated = db.habitCompletions
          .where(
            (c) =>
                !(c.habitId == habit.id &&
                  c.userId == user.id &&
                  _isSameDay(c.date, DateTime.now())),
          )
          .toList();
    } else {
      // Add completion
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

  // ── Habit options (edit / delete) ──────────────────────────────────────────

  Future<void> _showHabitOptions(
    BuildContext context,
    AppProvider provider,
    AppDB db,
    DailyHabit habit,
    User user,
    Family family,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _HabitOptionsSheet(
        habit: habit,
        onEdit: () {
          Navigator.of(context).pop();
          _showAddHabitSheet(
            context,
            user,
            family,
            db,
            provider,
            editHabit: habit,
          );
        },
        onDelete: () async {
          Navigator.of(context).pop();
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Habit?'),
              content: Text('Delete "${habit.title}" and all its history? This cannot be undone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          final updated = db.dailyHabits
              .where((h) => h.id != habit.id)
              .toList();
          final updatedCompletions = db.habitCompletions
              .where((c) => c.habitId != habit.id)
              .toList();
          await provider.saveAndSync(db.copyWith(
            dailyHabits: updated,
            habitCompletions: updatedCompletions,
          ));
        },
      ),
    );
  }

  // ── Add / Edit habit bottom sheet ──────────────────────────────────────────

  Future<void> _showAddHabitSheet(
    BuildContext context,
    User user,
    Family family,
    AppDB db,
    AppProvider provider, {
    DailyHabit? editHabit,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddHabitSheet(
        editHabit: editHabit,
        onSave: (habit) async {
          List<DailyHabit> updatedHabits;
          if (editHabit != null) {
            updatedHabits = db.dailyHabits
                .map((h) => h.id == habit.id ? habit : h)
                .toList();
          } else {
            updatedHabits = [...db.dailyHabits, habit];
          }
          await provider.saveAndSync(
            db.copyWith(dailyHabits: updatedHabits),
          );
        },
        userId: user.id,
        familyId: family.id,
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
      padding: const EdgeInsets.all(16),
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
              const Text(
                'Today\'s Progress',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                '$completed / $total',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total == 0
                ? 'Add your first habit below!'
                : completed == total
                    ? '🎉 All habits complete!'
                    : '${total - completed} habit${total - completed == 1 ? '' : 's'} remaining',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
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
      child: Material(
        color: isDone ? AppTheme.primaryLight : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onToggle,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDone
                    ? AppTheme.primary.withValues(alpha: 0.3)
                    : AppTheme.stone200,
              ),
            ),
            child: Row(
              children: [
                // Emoji
                Text(habit.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),

                // Title + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.stone900,
                          decoration:
                              isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (habit.description != null &&
                          habit.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          habit.description!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.stone500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (streak > 0) ...[
                            const Text('🔥', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 3),
                            Text(
                              '$streak day streak',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.stone500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (habit.isShared) ...[
                            const Icon(
                              Icons.people_outline,
                              size: 13,
                              color: AppTheme.stone400,
                            ),
                            const SizedBox(width: 3),
                            const Text(
                              'Shared',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.stone400,
                              ),
                            ),
                          ],
                          if (habit.targetValue != null &&
                              habit.targetUnit != null) ...[
                            if (habit.isShared) const SizedBox(width: 8),
                            Text(
                              '${habit.targetValue} ${habit.targetUnit}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.stone400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Completion toggle
                GestureDetector(
                  onTap: onToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? AppTheme.primary : Colors.transparent,
                      border: Border.all(
                        color: isDone ? AppTheme.primary : AppTheme.stone300,
                        width: 2,
                      ),
                    ),
                    child: isDone
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎯', style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text(
              'No habits yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.stone900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Build positive routines by adding your first daily habit.',
              style: TextStyle(color: AppTheme.stone500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Habit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Habit Options Sheet ──────────────────────────────────────────────────────

class _HabitOptionsSheet extends StatelessWidget {
  final DailyHabit habit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HabitOptionsSheet({
    required this.habit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(habit.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  habit.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.stone900,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _OptionTile(
            icon: Icons.edit_outlined,
            label: 'Edit Habit',
            onTap: onEdit,
          ),
          _OptionTile(
            icon: Icons.delete_outline,
            label: 'Delete Habit',
            color: Colors.red,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.stone900;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(color: c, fontSize: 15)),
      onTap: onTap,
    );
  }
}

// ─── Add / Edit Habit Sheet ───────────────────────────────────────────────────

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
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _targetValueCtrl = TextEditingController();
  final TextEditingController _targetUnitCtrl = TextEditingController();

  String _emoji = '✅';
  String _frequency = 'daily';
  bool _isShared = false;
  bool _saving = false;

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
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a habit name'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now();
    final habit = DailyHabit(
      id: widget.editHabit?.id ?? _uuid.v4(),
      familyId: widget.familyId,
      userId: widget.userId,
      label: title,
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      icon: _emoji,
      frequency: _frequency,
      isShared: _isShared,
      targetValue: int.tryParse(_targetValueCtrl.text.trim()),
      targetUnit: _targetUnitCtrl.text.trim().isEmpty
          ? null
          : _targetUnitCtrl.text.trim(),
      createdAt: widget.editHabit?.createdAt ?? now,
    );

    await widget.onSave(habit);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editHabit != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.stone300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              isEdit ? 'Edit Habit' : 'New Habit',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.stone900,
              ),
            ),
            const SizedBox(height: 20),

            // Emoji picker
            const Text(
              'Pick an emoji',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.stone700),
            ),
            const SizedBox(height: 8),
            _EmojiPicker(
              selected: _emoji,
              onSelect: (e) => setState(() => _emoji = e),
            ),
            const SizedBox(height: 16),

            // Title
            _Field(
              label: 'Habit Name',
              controller: _titleCtrl,
              hint: 'e.g. Drink water',
            ),
            const SizedBox(height: 12),

            // Description
            _Field(
              label: 'Description (optional)',
              controller: _descCtrl,
              hint: 'A short note about this habit',
            ),
            const SizedBox(height: 16),

            // Frequency
            const Text(
              'Frequency',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.stone700),
            ),
            const SizedBox(height: 8),
            _FrequencySelector(
              selected: _frequency,
              onSelect: (f) => setState(() => _frequency = f),
            ),
            const SizedBox(height: 16),

            // Target
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Target (optional)',
                    controller: _targetValueCtrl,
                    hint: '8',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Field(
                    label: 'Unit (optional)',
                    controller: _targetUnitCtrl,
                    hint: 'glasses',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Share with family
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Share with family',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.stone900),
              ),
              subtitle: const Text(
                'Family members can see this habit',
                style: TextStyle(fontSize: 12, color: AppTheme.stone500),
              ),
              value: _isShared,
              activeColor: AppTheme.primary,
              onChanged: (v) => setState(() => _isShared = v),
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isEdit ? 'Save Changes' : 'Add Habit',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
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
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.stone100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
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
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onSelect(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      isSelected ? AppTheme.primary : AppTheme.stone100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.stone200,
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.stone700,
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

// ─── Reusable field ───────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.stone700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppTheme.stone400, fontSize: 14),
            filled: true,
            fillColor: AppTheme.stone100,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
