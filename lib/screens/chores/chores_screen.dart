// lib/screens/chores/chores_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

// ─── Icon & Color palettes for chore creation ────────────────────────────────

const _choreIcons = [
  '\u{1F9F9}', // broom
  '\u{1F5D1}', // wastebasket
  '\u{1F436}', // dog
  '\u{1F9FA}', // basket
  '\u{1F6C1}', // bathtub
  '\u{1F331}', // seedling
  '\u{1F697}', // car
  '\u{1F4DA}', // books
  '\u{1F6CF}', // bed
  '\u{1F9C0}', // cheese (cooking)
  '\u{1F34E}', // apple
  '\u{1F431}', // cat
  '\u{1F3E0}', // house
  '\u{1FAA3}', // bucket
  '\u{1F9F8}', // teddy bear
];

const _choreColors = [
  Color(0xFF7C6BFF), // purple
  Color(0xFF6366F1), // indigo
  Color(0xFF4F46E5), // deep indigo
  Color(0xFFA855F7), // violet
  Color(0xFFEC4899), // pink
  Color(0xFFF43F5E), // rose
  Color(0xFFEF4444), // red
  Color(0xFFF59E0B), // amber
  Color(0xFFEAB308), // yellow
  Color(0xFF84CC16), // lime
  Color(0xFF22C55E), // green
  Color(0xFF14B8A6), // teal
  Color(0xFF06B6D4), // cyan
  Color(0xFF3B82F6), // blue
  Color(0xFF94A3B8), // slate
];

class ChoresScreen extends StatefulWidget {
  const ChoresScreen({super.key});

  @override
  State<ChoresScreen> createState() => _ChoresScreenState();
}

class _ChoresScreenState extends State<ChoresScreen> {
  int _weekOffset = 0;

  DateTime get _weekStart {
    final now = DateTime.now();
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    return DateTime(sunday.year, sunday.month, sunday.day)
        .add(Duration(days: _weekOffset * 7));
  }

  List<ChoreCompletion> _completionsForChore(
    String choreId, String userId, DateTime day, List<ChoreCompletion> all,
  ) {
    return all.where((c) =>
        c.choreId == choreId &&
        c.userId == userId &&
        c.date.year == day.year &&
        c.date.month == day.month &&
        c.date.day == day.day).toList();
  }

  bool _isDoneOnDay(String choreId, String userId, DateTime day, List<ChoreCompletion> all) {
    return _completionsForChore(choreId, userId, day, all).isNotEmpty;
  }

  Future<void> _toggleCompletion(Chore chore, String userId, DateTime day) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final existing = _completionsForChore(chore.id, userId, day, db.choreCompletions);
    if (existing.isNotEmpty) {
      // Remove completion
      final ids = existing.map((e) => e.id).toSet();
      await provider.saveAndSync(db.copyWith(
        choreCompletions: db.choreCompletions.where((c) => !ids.contains(c.id)).toList(),
      ));
    } else {
      // Add completion
      final completion = ChoreCompletion(
        id: const Uuid().v4(),
        choreId: chore.id,
        userId: userId,
        familyId: chore.familyId,
        date: day,
        completedAt: DateTime.now(),
        approvalStatus: chore.requiresApproval ? ApprovalStatus.PENDING : ApprovalStatus.APPROVED,
      );
      await provider.saveAndSync(db.copyWith(
        choreCompletions: [...db.choreCompletions, completion],
      ));
      if (mounted && !chore.requiresApproval) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${chore.title} done! +${chore.points} pts'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  Future<void> _deleteChore(String choreId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      chores: db.chores.where((c) => c.id != choreId).toList(),
      choreCompletions: db.choreCompletions.where((c) => c.choreId != choreId).toList(),
    ));
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoreFormSheet(
        onSave: (chore) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(chores: [...db.chores, chore]));
          NotificationService.notifyFamilyActivity(
            title: 'New Chore Added',
            body: '${provider.activeUser?.name ?? "Someone"} added: ${chore.title}',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final familyId = family.id;
    final members = provider.db.users.where((u) =>
        provider.db.familyMembers.any((m) => m.familyId == familyId && m.userId == u.id)).toList();
    final allChores = provider.db.chores.where((c) => c.familyId == familyId).toList();
    final completions = provider.db.choreCompletions.where((c) => c.familyId == familyId).toList();

    // Today's progress
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayCompletions = completions.where((c) =>
        c.date.year == today.year && c.date.month == today.month && c.date.day == today.day &&
        c.approvalStatus == ApprovalStatus.APPROVED).toList();
    // Count unique chore-user pairs expected today
    int totalExpected = 0;
    for (final chore in allChores) {
      final assigneeCount = chore.assigneeIds.isEmpty ? 1 : chore.assigneeIds.length;
      totalExpected += assigneeCount;
    }
    final todayDone = todayCompletions.length;

    // Week data
    final weekStart = _weekStart;
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final todayIndex = weekDays.indexWhere((d) =>
        d.year == now.year && d.month == now.month && d.day == now.day);
    final isCurrentWeek = _weekOffset == 0;
    final weekLabel = isCurrentWeek
        ? 'This Week'
        : DateFormat('MMM d').format(weekStart);

    // Build chore rows: one row per chore-assignee combination
    final choreRows = <_ChoreRow>[];
    for (final chore in allChores) {
      if (chore.assigneeIds.isEmpty) {
        choreRows.add(_ChoreRow(chore: chore, userId: user.id, userName: 'You'));
      } else {
        for (final assigneeId in chore.assigneeIds) {
          final m = members.cast<User?>().firstWhere((u) => u?.id == assigneeId, orElse: () => null);
          choreRows.add(_ChoreRow(
            chore: chore,
            userId: assigneeId,
            userName: m?.name.split(' ').first ?? 'Member',
          ));
        }
      }
    }

    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: AppTheme.background,
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
            const Text('FamilyHub', style: TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary,
            )),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Page Header
          PageHeader(
            title: 'Chore Chart',
            subtitle: 'Keep the pack accountable',
            actions: [
              ActionChipButton(
                icon: Icons.add,
                label: 'Add Chore',
                onTap: _showAddSheet,
                isPrimary: true,
              ),
            ],
          ),

          // ── Today's Progress Card ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B7BF7), Color(0xFFB4A0FF)],
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
                      const Text("Today's Progress", style: TextStyle(
                        fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      )),
                      Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.5), size: 32),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$todayDone/$totalExpected',
                    style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: totalExpected > 0 ? todayDone / totalExpected : 0,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Weekly View Card ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.stone100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with nav arrows
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        const Text('Weekly View', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                        )),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _weekOffset--),
                          child: const Icon(Icons.chevron_left_rounded, size: 22, color: AppTheme.stone400),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: isCurrentWeek ? null : () => setState(() => _weekOffset = 0),
                          child: Text(weekLabel, style: TextStyle(
                            fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                            color: isCurrentWeek ? AppTheme.primary : AppTheme.stone600,
                          )),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _weekOffset++),
                          child: const Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.stone400),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Day column headers
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const SizedBox(width: 140), // chore label column
                        ...List.generate(7, (i) {
                          final isToday = i == todayIndex;
                          final dayDate = weekDays[i];
                          return Expanded(
                            child: Center(
                              child: Column(
                                children: [
                                  Text(dayLabels[i], style: TextStyle(
                                    fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600,
                                    color: isToday ? AppTheme.primary : AppTheme.stone400,
                                  )),
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 24, height: 24,
                                    decoration: isToday ? BoxDecoration(
                                      color: AppTheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ) : null,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${dayDate.day}',
                                      style: TextStyle(
                                        fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
                                        color: isToday ? Colors.white : AppTheme.stone500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const Divider(height: 16),

                  // Chore rows
                  if (choreRows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.assignment_turned_in_outlined, size: 32, color: AppTheme.stone300),
                            const SizedBox(height: 8),
                            const Text('No chores yet', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone500,
                            )),
                            const SizedBox(height: 4),
                            const Text('Add chores to keep the family on track.', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                            )),
                          ],
                        ),
                      ),
                    )
                  else
                    ...choreRows.map((row) {
                      final choreIcon = row.chore.icon ?? _guessEmoji(row.chore.title);
                      final choreColor = row.chore.color != null
                          ? Color(int.tryParse(row.chore.color!.replaceFirst('#', '0xFF')) ?? 0xFF7C6BFF)
                          : const Color(0xFF7C6BFF);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            // Chore icon + info
                            SizedBox(
                              width: 140,
                              child: Row(
                                children: [
                                  Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(
                                      color: choreColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(choreIcon, style: const TextStyle(fontSize: 18)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(row.chore.title, style: const TextStyle(
                                          fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone800,
                                        ), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        Text(row.userName, style: const TextStyle(
                                          fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400,
                                        )),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Day checkboxes
                            ...List.generate(7, (dayIdx) {
                              final day = weekDays[dayIdx];
                              final isToday = dayIdx == todayIndex;
                              final done = _isDoneOnDay(row.chore.id, row.userId, day, completions);
                              final isPast = day.isBefore(today);
                              final isFuture = day.isAfter(today);
                              return Expanded(
                                child: Center(
                                  child: GestureDetector(
                                    onTap: (isFuture && isCurrentWeek) ? null : () => _toggleCompletion(row.chore, row.userId, day),
                                    child: Container(
                                      width: 26, height: 26,
                                      decoration: BoxDecoration(
                                        color: done
                                            ? choreColor.withValues(alpha: 0.15)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: done
                                              ? choreColor
                                              : isToday
                                                  ? choreColor.withValues(alpha: 0.5)
                                                  : AppTheme.stone200,
                                          width: done ? 2 : 1,
                                          strokeAlign: BorderSide.strokeAlignInside,
                                        ),
                                      ),
                                      child: done
                                          ? Icon(Icons.check_rounded, size: 16, color: choreColor)
                                          : null,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Family Status Today ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.stone100),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.groups_outlined, size: 20, color: AppTheme.stone500),
                      const SizedBox(width: 8),
                      const Text('Family Status Today', style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900,
                      )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...members.map((member) {
                    // Chores assigned to this member
                    final memberChores = allChores.where((c) =>
                        c.assigneeIds.contains(member.id) || c.assigneeIds.isEmpty).toList();
                    final memberTotal = memberChores.length;
                    final memberDone = memberChores.where((c) =>
                        _isDoneOnDay(c.id, member.id, today, completions)).length;
                    final progress = memberTotal > 0 ? memberDone / memberTotal : 0.0;

                    final memberName = provider.memberDisplayName(member);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              UserAvatarWidget(name: memberName, radius: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(member.id == user.id ? 'You' : memberName.split(' ').first,
                                  style: const TextStyle(
                                    fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800,
                                  ),
                                ),
                              ),
                              Text('$memberDone/$memberTotal', style: const TextStyle(
                                fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400,
                              )),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: AppTheme.stone100,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress >= 1.0 ? AppTheme.success : AppTheme.primary,
                              ),
                            ),
                          ),
                          if (memberChores.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: memberChores.where((c) =>
                                  !_isDoneOnDay(c.id, member.id, today, completions)).take(3).map((c) {
                                final icon = c.icon ?? _guessEmoji(c.title);
                                return Text('$icon ${c.title}', style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400,
                                ));
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Helper to expand chore rows per assignee
class _ChoreRow {
  final Chore chore;
  final String userId;
  final String userName;
  const _ChoreRow({required this.chore, required this.userId, required this.userName});
}

String _guessEmoji(String title) {
  final t = title.toLowerCase();
  if (t.contains('dish') || t.contains('wash')) return '\u{1F37D}';
  if (t.contains('trash') || t.contains('rubbish') || t.contains('garbage') || t.contains('recycl')) return '\u{1F5D1}';
  if (t.contains('laundry') || t.contains('clothes')) return '\u{1F455}';
  if (t.contains('vacuum') || t.contains('clean') || t.contains('sweep') || t.contains('mop')) return '\u{1F9F9}';
  if (t.contains('cook') || t.contains('meal') || t.contains('dinner')) return '\u{1F373}';
  if (t.contains('walk') || t.contains('dog') || t.contains('pet')) return '\u{1F436}';
  if (t.contains('bed') || t.contains('room')) return '\u{1F6CF}';
  if (t.contains('yard') || t.contains('garden') || t.contains('lawn')) return '\u{1F331}';
  if (t.contains('bath')) return '\u{1F6C1}';
  if (t.contains('car')) return '\u{1F697}';
  if (t.contains('homework') || t.contains('study') || t.contains('read')) return '\u{1F4DA}';
  return '\u{2728}';
}

// ─── New Chore Form Sheet ────────────────────────────────────────────────────

class _ChoreFormSheet extends StatefulWidget {
  final Future<void> Function(Chore) onSave;
  const _ChoreFormSheet({required this.onSave});

  @override
  State<_ChoreFormSheet> createState() => _ChoreFormSheetState();
}

class _ChoreFormSheetState extends State<_ChoreFormSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _rewardCtrl = TextEditingController(text: '0.00');
  int _selectedIconIndex = 0;
  int _points = 10;
  int _selectedColorIndex = 0;
  double _rewardAmount = 0;
  ChoreFrequency _frequency = ChoreFrequency.DAILY;
  List<int> _customDays = [];
  List<String> _assigneeIds = [];
  bool _requiresApproval = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _rewardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final chore = Chore(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      icon: _choreIcons[_selectedIconIndex],
      points: _points,
      reward: _rewardAmount > 0 ? _rewardAmount.toStringAsFixed(2) : null,
      frequency: _frequency,
      daysOfWeek: _frequency == ChoreFrequency.CUSTOM ? _customDays : const [],
      assignees: _assigneeIds,
      color: '#${_choreColors[_selectedColorIndex].value.toRadixString(16).substring(2)}',
      requiresApproval: _requiresApproval,
      createdAt: DateTime.now(),
    );
    await widget.onSave(chore);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final members = provider.familyMembers;
    final currentUser = provider.activeUser;

    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SheetHandle(),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New Chore', style: TextStyle(
                    fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900,
                  )),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Chore Name
                  _formLabel('CHORE NAME'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleCtrl, autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g., Wash the dishes',
                      hintStyle: TextStyle(color: AppTheme.stone300),
                      filled: true, fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _formLabel('DESCRIPTION (OPTIONAL)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descCtrl, maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Any extra details...',
                      hintStyle: TextStyle(color: AppTheme.stone300),
                      filled: true, fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Icon & Points row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon picker
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _formLabel('ICON'),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: List.generate(_choreIcons.length, (i) {
                                final selected = i == _selectedIconIndex;
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedIconIndex = i),
                                  child: Container(
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(
                                      color: selected ? AppTheme.primaryLight : AppTheme.stone50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: selected ? Border.all(color: AppTheme.primary, width: 2) : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(_choreIcons[i], style: const TextStyle(fontSize: 18)),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Points picker
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _formLabel('POINTS'),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [5, 10, 15, 20].map((p) {
                                final selected = p == _points;
                                return GestureDetector(
                                  onTap: () => setState(() => _points = p),
                                  child: Container(
                                    width: 42, height: 36,
                                    decoration: BoxDecoration(
                                      color: selected ? Colors.white : AppTheme.stone50,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: selected ? const Color(0xFFF59E0B) : AppTheme.stone200,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('$p', style: TextStyle(
                                      fontFamily: 'Inter', fontSize: 13,
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      color: selected ? const Color(0xFFF59E0B) : AppTheme.stone600,
                                    )),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Color picker
                  _formLabel('COLOR'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: List.generate(_choreColors.length, (i) {
                      final selected = i == _selectedColorIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColorIndex = i),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: _choreColors[i],
                            shape: BoxShape.circle,
                            border: selected ? Border.all(color: AppTheme.stone300, width: 3) : null,
                            boxShadow: selected ? [BoxShadow(color: _choreColors[i].withValues(alpha: 0.4), blurRadius: 6)] : null,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Reward per completion
                  _formLabel('REWARD PER COMPLETION (OPTIONAL)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _rewardCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _rewardAmount = double.tryParse(v) ?? 0,
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone600),
                      filled: true, fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [0, 0.5, 1, 2, 5].map((amount) {
                      final label = amount == 0 ? 'None' : '\$$amount';
                      final selected = _rewardAmount == amount;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _rewardAmount = amount.toDouble();
                          _rewardCtrl.text = amount == 0 ? '0.00' : amount.toStringAsFixed(2);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFD1FAE5) : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? const Color(0xFF10B981) : AppTheme.stone200,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Text(label, style: TextStyle(
                            fontFamily: 'Inter', fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? const Color(0xFF10B981) : AppTheme.stone600,
                          )),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Frequency
                  _formLabel('FREQUENCY'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _freqChip('Every Day', ChoreFrequency.DAILY),
                      _freqChip('Weekdays', ChoreFrequency.WEEKLY),
                      _freqChip('Custom', ChoreFrequency.CUSTOM),
                    ],
                  ),
                  if (_frequency == ChoreFrequency.CUSTOM) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].asMap().entries.map((e) {
                        final selected = _customDays.contains(e.key);
                        return GestureDetector(
                          onTap: () => setState(() {
                            selected ? _customDays.remove(e.key) : _customDays.add(e.key);
                          }),
                          child: Container(
                            width: 40, height: 36,
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.primaryLight : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200),
                            ),
                            alignment: Alignment.center,
                            child: Text(e.value, style: TextStyle(
                              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600,
                              color: selected ? AppTheme.primary : AppTheme.stone500,
                            )),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Assign To
                  if (members.isNotEmpty) ...[
                    _formLabel('ASSIGN TO'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: members.map((m) {
                        final isAssigned = _assigneeIds.contains(m.userId);
                        final memberUser = provider.userById(m.userId);
                        final name = memberUser?.name ?? m.displayName ?? 'Member';
                        final isMe = m.userId == currentUser?.id;
                        return GestureDetector(
                          onTap: () => setState(() {
                            isAssigned ? _assigneeIds.remove(m.userId) : _assigneeIds.add(m.userId);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isAssigned ? AppTheme.primaryLight : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isAssigned ? AppTheme.primary : AppTheme.stone200,
                                width: isAssigned ? 2 : 1,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              UserAvatarWidget(name: name, radius: 12),
                              const SizedBox(width: 6),
                              Text(isMe ? 'Me' : name.split(' ').first, style: TextStyle(
                                fontFamily: 'Inter', fontWeight: isAssigned ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 13, color: isAssigned ? AppTheme.primary : AppTheme.stone700,
                              )),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Requires Parental Approval
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.stone50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.stone200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_outlined, size: 20, color: AppTheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Requires Parental Approval', style: TextStyle(
                                fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone800,
                              )),
                              Text('Parents must approve before points are awarded', style: TextStyle(
                                fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400,
                              )),
                            ],
                          ),
                        ),
                        Switch(
                          value: _requiresApproval,
                          onChanged: (v) => setState(() => _requiresApproval = v),
                          activeColor: AppTheme.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Create button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Create Chore', style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16,
                            )),
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

  Widget _freqChip(String label, ChoreFrequency freq) {
    final selected = _frequency == freq;
    return GestureDetector(
      onTap: () => setState(() => _frequency = freq),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryLight : AppTheme.stone50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.stone200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(label, style: TextStyle(
          fontFamily: 'Inter', fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13, color: selected ? AppTheme.primary : AppTheme.stone600,
        )),
      ),
    );
  }

  Widget _formLabel(String text) {
    return Text(text, style: const TextStyle(
      fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11,
      color: AppTheme.stone400, letterSpacing: 0.8,
    ));
  }
}
