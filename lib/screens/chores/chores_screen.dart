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

class ChoresScreen extends StatefulWidget {
  const ChoresScreen({super.key});

  @override
  State<ChoresScreen> createState() => _ChoresScreenState();
}

class _ChoresScreenState extends State<ChoresScreen> {
  String? _filterUserId;

  bool _isCompletedToday(Chore chore) {
    if (chore.lastCompletedAt == null) return false;
    final now = DateTime.now();
    final last = chore.lastCompletedAt!;
    return last.year == now.year && last.month == now.month && last.day == now.day;
  }

  Future<void> _completeChore(Chore chore) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;
    final db = provider.db;
    final updated = db.chores.map((c) {
      if (c.id == chore.id) {
        return c.copyWith();
      }
      return c;
    }).toList();
    await provider.saveAndSync(db.copyWith(chores: updated));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${chore.title} done! +${chore.points} pts'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  Future<void> _deleteChore(String choreId) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      chores: db.chores.where((c) => c.id != choreId).toList(),
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
    final members = provider.db.users.where((u) => provider.db.familyMembers.any((m) => m.familyId == familyId && m.userId == u.id)).toList();
    final allChores = provider.db.chores.where((c) => c.familyId == family.id).toList();
    final shown = _filterUserId == null
        ? allChores
        : allChores.where((c) => c.assigneeIds.contains(_filterUserId)).toList();

    shown.sort((a, b) {
      final aD = _isCompletedToday(a) ? 1 : 0;
      final bD = _isCompletedToday(b) ? 1 : 0;
      if (aD != bD) return aD - bD;
      return a.title.compareTo(b.title);
    });

    // Weekly view data
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday % 7)); // Sunday
    final dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final todayIndex = now.weekday % 7;

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
            const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
        ],
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

          // Weekly View Card
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
                  // Weekly View header with arrows
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        const Text(
                          'Weekly View',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.stone900,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_left_rounded, size: 22, color: AppTheme.stone400),
                        const SizedBox(width: 4),
                        const Text(
                          'This Week',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.stone600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.stone400),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Day headers
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const SizedBox(width: 140), // space for chore name column
                        ...List.generate(7, (i) {
                          final isToday = i == todayIndex;
                          return Expanded(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                decoration: isToday
                                    ? BoxDecoration(
                                        color: AppTheme.primary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      )
                                    : null,
                                child: Text(
                                  dayLabels[i],
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isToday ? AppTheme.primary : AppTheme.stone400,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const Divider(height: 16),

                  // Chore rows
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            const Text('🧹', style: TextStyle(fontSize: 32)),
                            const SizedBox(height: 8),
                            const Text(
                              'No chores yet',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Add chores to keep the family on track.',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...shown.map((chore) {
                      final doneToday = _isCompletedToday(chore);
                      final assigneeNames = chore.assigneeIds.map((id) {
                        final m = members.cast<User?>().firstWhere(
                            (m) => m?.id == id, orElse: () => null);
                        return m?.name.split(' ').first ?? 'Member';
                      }).toList();
                      final emoji = chore.title.contains('Dish') ? '🍽️'
                          : chore.title.contains('Trash') || chore.title.contains('Garbage') ? '🗑️'
                          : chore.title.contains('Laundry') ? '👕'
                          : chore.title.contains('Vacuum') || chore.title.contains('Clean') ? '🧹'
                          : chore.title.contains('Cook') || chore.title.contains('Meal') ? '🍳'
                          : chore.title.contains('Walk') || chore.title.contains('Dog') ? '🐕'
                          : '✨';

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            // Chore info column
                            SizedBox(
                              width: 140,
                              child: Row(
                                children: [
                                  Text(emoji, style: const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          chore.title,
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.stone800,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (assigneeNames.isNotEmpty)
                                          Text(
                                            assigneeNames.first,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 11,
                                              color: AppTheme.stone400,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Day checkboxes
                            ...List.generate(7, (dayIdx) {
                              final isToday = dayIdx == todayIndex;
                              final checked = isToday && doneToday;
                              return Expanded(
                                child: Center(
                                  child: GestureDetector(
                                    onTap: isToday && !doneToday ? () => _completeChore(chore) : null,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: checked
                                            ? AppTheme.success.withOpacity(0.15)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: checked
                                              ? AppTheme.success
                                              : isToday
                                                  ? AppTheme.stone300
                                                  : AppTheme.stone200,
                                          width: checked ? 2 : 1,
                                        ),
                                      ),
                                      child: checked
                                          ? const Icon(Icons.check_rounded, size: 14, color: AppTheme.success)
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
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PointsStrip extends StatelessWidget {
  final List<User> members;
  final Map<String, int> userPoints;
  const _PointsStrip({required this.members, required this.userPoints});

  @override
  Widget build(BuildContext context) {
    final sorted = [...members]
      ..sort((a, b) => (userPoints[b.id] ?? 0).compareTo(userPoints[a.id] ?? 0));
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('POINTS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sorted.asMap().entries.map((e) {
              final idx = e.key;
              final m = e.value;
              final pts = userPoints[m.id] ?? 0;
              final medal = idx == 0 ? '🥇' : idx == 1 ? '🥈' : idx == 2 ? '🥉' : '';
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: idx == 0 ? AppTheme.primary.withOpacity(0.1) : AppTheme.stone50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: idx == 0 ? AppTheme.primary.withOpacity(0.3) : AppTheme.stone200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (medal.isNotEmpty) Text(medal, style: const TextStyle(fontSize: 16)),
                  if (medal.isNotEmpty) const SizedBox(width: 4),
                  UserAvatarWidget(name: m.name, radius: 13),
                  const SizedBox(width: 6),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name.split(' ').first, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                    Text('$pts pts', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: idx == 0 ? AppTheme.primary : AppTheme.stone500)),
                  ]),
                ]),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

class _ChoreCard extends StatelessWidget {
  final Chore chore;
  final bool doneToday;
  final List<String> assigneeNames;
  final VoidCallback? onComplete;
  final VoidCallback onDelete;

  const _ChoreCard({
    required this.chore,
    required this.doneToday,
    required this.assigneeNames,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(chore.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Chore'),
          content: Text('Delete "${chore.title}"?'),
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
          color: doneToday ? AppTheme.success.withOpacity(0.05) : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: doneToday ? AppTheme.success.withOpacity(0.3) : AppTheme.stone100),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: onComplete,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: doneToday ? AppTheme.success.withOpacity(0.15) : AppTheme.stone50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: doneToday ? AppTheme.success : AppTheme.stone200),
              ),
              child: Icon(doneToday ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: doneToday ? AppTheme.success : AppTheme.stone300, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(chore.title, style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15,
                color: doneToday ? AppTheme.stone400 : AppTheme.stone900,
                decoration: doneToday ? TextDecoration.lineThrough : null,
              )),
              if (chore.description != null && chore.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(chore.description!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _Badge(label: chore.frequency.name, color: AppTheme.primary),
                _Badge(label: '${chore.points} pts', color: AppTheme.warning),
                if (assigneeNames.isNotEmpty)
                  _Badge(label: assigneeNames.take(2).join(', '), color: AppTheme.stone500, icon: Icons.person_outline_rounded),
              ]),
              if (chore.lastCompletedAt != null) ...[
                const SizedBox(height: 4),
                Text('Last: ${DateFormat('MMM d').format(chore.lastCompletedAt!)}',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 10, color: color), const SizedBox(width: 3)],
        Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _ChoreFormSheet extends StatefulWidget {
  final Future<void> Function(Chore) onSave;
  const _ChoreFormSheet({required this.onSave});

  @override
  State<_ChoreFormSheet> createState() => _ChoreFormSheetState();
}

class _ChoreFormSheetState extends State<_ChoreFormSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _pointsCtrl = TextEditingController(text: '5');
  ChoreFrequency _frequency = ChoreFrequency.WEEKLY;
  List<String> _assigneeIds = [];
  bool _isSaving = false;
  final _uuid = const Uuid();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _pointsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final chore = Chore(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      assignees: _assigneeIds,
      frequency: _frequency,
      points: int.tryParse(_pointsCtrl.text) ?? 5,
      createdAt: DateTime.now(),
    );
    await widget.onSave(chore);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final members = context.read<AppProvider>().familyMembers;
    return DraggableScrollableSheet(
      initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('New Chore', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
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
              TextField(controller: _titleCtrl, autofocus: true, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Chore Title *', prefixIcon: Icon(Icons.cleaning_services_rounded))),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, maxLines: 2, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Description (optional)', prefixIcon: Icon(Icons.notes_rounded), alignLabelWithHint: true)),
              const SizedBox(height: 12),
              TextField(controller: _pointsCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Points', prefixIcon: Icon(Icons.star_rounded))),
              const SizedBox(height: 20),
              const Text('Frequency', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: ChoreFrequency.values.map((f) {
                final isSelected = f == _frequency;
                return GestureDetector(
                  onTap: () => setState(() => _frequency = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryLight : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.stone200, width: isSelected ? 2 : 1),
                    ),
                    child: Text(f.name, style: TextStyle(fontFamily: 'Inter', fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, fontSize: 13, color: isSelected ? AppTheme.primary : AppTheme.stone600)),
                  ),
                );
              }).toList()),
              if (members.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Assign To', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: members.map((m) {
                  final isAssigned = _assigneeIds.contains(m.id);
                  return GestureDetector(
                    onTap: () => setState(() { isAssigned ? _assigneeIds.remove(m.id) : _assigneeIds.add(m.id); }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isAssigned ? AppTheme.primaryLight : AppTheme.stone50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isAssigned ? AppTheme.primary : AppTheme.stone200, width: isAssigned ? 2 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        UserAvatarWidget(name: m.name, radius: 12),
                        const SizedBox(width: 6),
                        Text(m.name.split(' ').first, style: TextStyle(fontFamily: 'Inter', fontWeight: isAssigned ? FontWeight.w700 : FontWeight.w500, fontSize: 13, color: isAssigned ? AppTheme.primary : AppTheme.stone700)),
                      ]),
                    ),
                  );
                }).toList()),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
