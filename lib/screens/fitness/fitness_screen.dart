// lib/screens/fitness/fitness_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
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
          await provider.saveAndSync(db.copyWith(fitnessLogs: [...db.fitnessLogs, log]));
        },
      ),
    );
  }

  Future<void> _deleteLog(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(fitnessLogs: db.fitnessLogs.where((l) => l.id != id).toList()));
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

    final allLogs = provider.db.fitnessLogs
        .where((l) => l.familyId == family.id)
        .toList();

    final shown = _filter == _FitnessFilter.mine
        ? allLogs.where((l) => l.userId == user.id).toList()
        : allLogs;
    shown.sort((a, b) => b.date.compareTo(a.date));

    final now = DateTime.now();
    final todayLogs = shown.where((l) {
      return l.date.year == now.year && l.date.month == now.month && l.date.day == now.day;
    }).toList();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekLogs = shown.where((l) => l.date.isAfter(weekStart.subtract(const Duration(days: 1)))).toList();
    final totalWeekMinutes = weekLogs.fold(0, (s, l) => s + l.durationMinutes);

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Fitness'), floating: true),
          // Quick stats
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(child: StatCard(label: "Today's workouts", value: '${todayLogs.length}', emoji: '🔥', color: AppTheme.error)),
                const SizedBox(width: 10),
                Expanded(child: StatCard(label: 'Minutes this week', value: '$totalWeekMinutes', emoji: '⏱️', color: AppTheme.primary)),
                const SizedBox(width: 10),
                Expanded(child: StatCard(label: 'This week', value: '${weekLogs.length}', emoji: '📊', color: AppTheme.success)),
              ]),
            ),
          ),
          // Filter
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: AppTabBar(
                tabs: const ['My Logs', 'Family'],
                selectedIndex: _filter.index,
                onSelected: (i) => setState(() => _filter = _FitnessFilter.values[i]),
              ),
            ),
          ),
          shown.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '💪',
                    title: 'No fitness logs',
                    subtitle: 'Track your workouts and activities.',
                    actionLabel: 'Add Log',
                    onAction: _showAddSheet,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final log = shown[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LogCard(
                            log: log,
                            emoji: _activityEmoji(log.activity),
                            memberName: provider.userById(log.userId)?.name ?? 'Member',
                            onDelete: () => _deleteLog(log.id),
                          ),
                        );
                      },
                      childCount: shown.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final FitnessLog log;
  final String emoji;
  final String memberName;
  final VoidCallback onDelete;

  const _LogCard({required this.log, required this.emoji, required this.memberName, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Log'),
          content: const Text('Remove this fitness log?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
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
            width: 46, height: 46,
            decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(log.activity, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _Chip(label: '${log.durationMinutes} min', color: AppTheme.primary),
              if (log.caloriesBurned != null) _Chip(label: '${log.caloriesBurned} cal', color: AppTheme.error),
              _Chip(label: memberName.split(' ').first, color: AppTheme.stone500),
            ]),
            if (log.notes != null && log.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(log.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('MMM d').format(log.date), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
            Text(DateFormat('h:mm a').format(log.date), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone300)),
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
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );
}

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

  static const _suggestions = ['Running', 'Walking', 'Swimming', 'Cycling', 'Yoga', 'Weight Training', 'HIIT', 'Hiking'];

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
    if (_activityCtrl.text.trim().isEmpty || _durationCtrl.text.trim().isEmpty) return;
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
      initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Log Workout', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              TextField(
                controller: _activityCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Activity *', prefixIcon: Icon(Icons.fitness_center_rounded)),
              ),
              const SizedBox(height: 8),
              // Quick suggestions
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _suggestions.map((s) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _activityCtrl.text = s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _activityCtrl.text == s ? AppTheme.primaryLight : AppTheme.stone100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(s, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone700)),
                      ),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Duration (min) *', prefixIcon: Icon(Icons.timer_outlined)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _caloriesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Calories (optional)', prefixIcon: Icon(Icons.local_fire_department_rounded)),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEE, MMM d, y').format(_date), style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
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
