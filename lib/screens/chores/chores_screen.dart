// lib/screens/chores/chores_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/huddle_module_scaffold.dart';
import '../../widgets/module_ui_kit.dart';
import '../../utils/debounce.dart';
import '../../utils/sync_after_save.dart';

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
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

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
    HapticFeedback.lightImpact();
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final existing = _completionsForChore(chore.id, userId, day, db.choreCompletions);
    if (existing.isNotEmpty) {
      final ids = existing.map((e) => e.id).toSet();
      await saveAndSyncWithImmediatePush(
        provider,
        db.copyWith(
          choreCompletions:
              db.choreCompletions.where((c) => !ids.contains(c.id)).toList(),
        ),
        pushTableScope: CloudSyncScope.choreBundle,
      );
    } else {
      final completion = ChoreCompletion(
        id: const Uuid().v4(),
        choreId: chore.id,
        userId: userId,
        familyId: chore.familyId,
        date: day,
        completedAt: DateTime.now(),
        approvalStatus: chore.requiresApproval ? ApprovalStatus.PENDING : ApprovalStatus.APPROVED,
      );
      var nextDb = db.copyWith(
        choreCompletions: [...db.choreCompletions, completion],
      );
      if (!chore.requiresApproval &&
          chore.rotationEnabled &&
          chore.assignees.length > 1) {
        final nextCursor =
            (chore.rotationCursor + 1) % chore.assignees.length;
        nextDb = nextDb.copyWith(
          chores: nextDb.chores
              .map((c) =>
                  c.id == chore.id ? c.copyWith(rotationCursor: nextCursor) : c)
              .toList(),
        );
      }
      await saveAndSyncWithImmediatePush(
        provider,
        nextDb,
        pushTableScope: CloudSyncScope.choreBundle,
      );
      if (mounted && !chore.requiresApproval) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${chore.title} done! +${chore.points} pts'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  Future<void> _deleteChore(String choreId) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    final chore = provider.db.chores.cast<Chore?>().firstWhere(
      (c) => c?.id == choreId,
      orElse: () => null,
    );
    final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
    final canManage = chore != null && userId != null && (chore.creatorId == userId || isOwner);
    if (!canManage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the chore creator or family owner can delete chores.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chore'),
        content: const Text('Delete this chore and all completion history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(
        chores: db.chores.where((c) => c.id != choreId).toList(),
        choreCompletions:
            db.choreCompletions.where((c) => c.choreId != choreId).toList(),
      ),
      pushTableScope: CloudSyncScope.choreBundle,
    );
  }

  Future<void> _approveCompletion(String completionId, {bool approve = true}) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
    if (!isOwner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the family owner can approve chore completions.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final db = provider.db;
    final updated = db.choreCompletions.map((c) {
      if (c.id != completionId) return c;
      return ChoreCompletion(
        id: c.id,
        choreId: c.choreId,
        userId: c.userId,
        familyId: c.familyId,
        date: c.date,
        completedAt: c.completedAt,
        approvalStatus: approve ? ApprovalStatus.APPROVED : ApprovalStatus.REJECTED,
      );
    }).toList();
    var nextDb = db.copyWith(choreCompletions: updated);
    if (approve) {
      final cc = db.choreCompletions.firstWhere((c) => c.id == completionId);
      final chore = db.chores.firstWhereOrNull((c) => c.id == cc.choreId);
      if (chore != null &&
          chore.rotationEnabled &&
          chore.assignees.length > 1) {
        final nextCursor =
            (chore.rotationCursor + 1) % chore.assignees.length;
        nextDb = nextDb.copyWith(
          chores: nextDb.chores
              .map((c) =>
                  c.id == chore.id ? c.copyWith(rotationCursor: nextCursor) : c)
              .toList(),
        );
      }
    }
    await saveAndSyncWithImmediatePush(
      provider,
      nextDb,
      pushTableScope: CloudSyncScope.choreBundle,
    );
    if (mounted) {
      final chore = db.chores.where((c) => c.id == db.choreCompletions.firstWhere((cc) => cc.id == completionId).choreId).firstOrNull;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? 'Approved! +${chore?.points ?? 0} pts' : 'Rejected'),
        backgroundColor: approve ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _showAddSheet({Chore? editChore}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoreFormSheet(
        editChore: editChore,
        onSave: (chore) async {
          final provider = context.read<AppProvider>();
          final userId = provider.activeUser?.id;
          final isOwner = userId != null && provider.activeFamily?.ownerId == userId;
          if (editChore != null &&
              (userId == null || (editChore.creatorId != userId && !isOwner))) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Only the chore creator or family owner can edit this chore.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
          final db = provider.db;
          if (editChore != null) {
            await saveAndSyncWithImmediatePush(
              provider,
              db.copyWith(
                chores:
                    db.chores.map((c) => c.id == editChore.id ? chore : c).toList(),
              ),
              pushTableScope: CloudSyncScope.choreBundle,
            );
          } else {
            await saveAndSyncWithImmediatePush(
              provider,
              db.copyWith(chores: [...db.chores, chore]),
              pushTableScope: CloudSyncScope.choreBundle,
            );
            NotificationService.notifyFamilyActivityWithDb(
              provider.db,
              title: 'New Chore Added',
              body: '${provider.activeUser?.name ?? "Someone"} added: ${chore.title}',
              path: '/chores',
              familyId: provider.activeFamily?.id,
              excludeUserId: provider.activeUser?.id,
            );
          }
        },
      ),
    );
  }

  void _showChoreActions(Chore chore) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _parseChoreColor(chore.color).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(chore.icon ?? _guessEmoji(chore.title), style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chore.title, style: TextStyle(
                          fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.stone900,
                        )),
                        if (chore.description != null)
                          Text(chore.description!, style: TextStyle(
                            fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                          ), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _actionTile(Icons.edit_outlined, 'Edit Chore', AppTheme.stone700, () {
              Navigator.pop(ctx);
              _showAddSheet(editChore: chore);
            }),
            _actionTile(Icons.delete_outline_rounded, 'Delete Chore', AppTheme.error, () {
              Navigator.pop(ctx);
              _deleteChore(chore.id);
            }),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(
              fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: color,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingApprovals(AppProvider provider, User user, String familyId,
      List<Chore> allChores, List<ChoreCompletion> completions) {
    final myRole = provider.db.familyMembers
        .firstWhereOrNull((m) => m.familyId == familyId && m.userId == user.id)?.role;
    if (myRole != Role.OWNER && myRole != Role.ADMIN) return const SizedBox.shrink();

    final pending = completions.where((c) => c.approvalStatus == ApprovalStatus.PENDING).toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pending_actions_rounded, size: 16, color: AppTheme.warning),
              ),
              const SizedBox(width: 10),
              Text('Pending Approvals', style: TextStyle(
                fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900,
              )),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${pending.length}', style: TextStyle(
                  fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.warning,
                )),
              ),
            ]),
            const SizedBox(height: 14),
            ...pending.map((cc) {
              final chore = allChores.firstWhereOrNull((c) => c.id == cc.choreId);
              final displayName = provider.displayNameForUserId(cc.userId);
              final firstName = displayName.split(' ').first;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  AvatarInitials(name: displayName, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(chore?.title ?? 'Chore', style: TextStyle(
                          fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800,
                        )),
                        Text('$firstName \u00B7 ${DateFormat.MMMd().format(cc.date)}',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('+${chore?.points ?? 0}', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary,
                    )),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _approveCompletion(cc.id, approve: false),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.error),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _approveCompletion(cc.id),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_rounded, size: 16, color: AppTheme.success),
                    ),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _parseChoreColor(String? color) {
    if (color == null) return const Color(0xFF7C6BFF);
    return Color(int.tryParse(color.replaceFirst('#', '0xFF')) ?? 0xFF7C6BFF);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const ModuleFamilyLoadingScaffold();
    }

    final familyId = family.id;
    final members = provider.db.users.where((u) =>
        provider.db.familyMembers.any((m) => m.familyId == familyId && m.userId == u.id)).toList();
    final allChores = provider.db.chores.where((c) => c.familyId == familyId).toList();
    final completions = provider.db.choreCompletions.where((c) => c.familyId == familyId).toList();

    // Search filter
    final filteredChores = _searchQuery.isEmpty
        ? allChores
        : allChores.where((c) => c.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    // Today's progress
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayCompletions = completions.where((c) =>
        c.date.year == today.year && c.date.month == today.month && c.date.day == today.day &&
        c.approvalStatus == ApprovalStatus.APPROVED).toList();
    int totalExpected = 0;
    for (final chore in allChores) {
      final assigneeCount = chore.assigneeIds.isEmpty ? 1 : chore.assigneeIds.length;
      totalExpected += assigneeCount;
    }
    final todayDone = todayCompletions.length;

    // Total points earned
    final totalPoints = completions
        .where((c) => c.approvalStatus == ApprovalStatus.APPROVED)
        .fold<int>(0, (sum, cc) {
      final chore = allChores.firstWhereOrNull((c) => c.id == cc.choreId);
      return sum + (chore?.points ?? 0);
    });

    // Week data
    final weekStart = _weekStart;
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final todayIndex = weekDays.indexWhere((d) =>
        d.year == now.year && d.month == now.month && d.day == now.day);
    final isCurrentWeek = _weekOffset == 0;
    final weekLabel = isCurrentWeek
        ? 'This Week'
        : '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d').format(weekDays.last)}';

    // Build chore rows: one row per chore-assignee combination
    final choreRows = <_ChoreRow>[];
    for (final chore in filteredChores) {
      if (chore.assigneeIds.isEmpty) {
        choreRows.add(_ChoreRow(chore: chore, userId: user.id, userName: 'You'));
      } else {
        for (final assigneeId in chore.assigneeIds) {
          final label = assigneeId == user.id
              ? 'You'
              : provider.displayNameForUserId(assigneeId).split(' ').first;
          choreRows.add(_ChoreRow(
            chore: chore,
            userId: assigneeId,
            userName: label,
          ));
        }
      }
    }

    return HuddleModuleScaffold(
      modulePath: '/chores',
      enterPullTables: CloudSyncScope.choreBundle,
      drawer: const AppDrawer(),
      // backgroundColor handled by theme
      appBar: const MainAppBar(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Page Header ──────────────────────────────────────────
          PageHeader(
            title: screenTitleForModulePath('/chores'),
            subtitle: 'Keep the pack accountable.',
            actions: [
              ActionChipButton(
                icon: Icons.add_rounded,
                label: 'Add Chore',
                onTap: () => _showAddSheet(),
                isPrimary: true,
              ),
            ],
          ),

          // ── Stat Cards ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatCard(
                  icon: Icons.assignment_outlined,
                  label: 'Total',
                  value: '${allChores.length}',
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  icon: Icons.check_circle_outline,
                  label: 'Done Today',
                  value: '$todayDone',
                  color: AppTheme.success,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  icon: Icons.star_outline_rounded,
                  label: 'Points',
                  value: '$totalPoints',
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Search Bar ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _searchDebounce.run(() {
                  if (!mounted) return;
                  setState(() => _searchQuery = v);
                });
              },
              decoration: InputDecoration(
                hintText: 'Search chores...',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchDebounce.cancel();
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Today's Progress Card ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B7BF7), Color(0xFFB4A0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
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
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.8), size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$todayDone',
                        style: TextStyle(
                          fontFamily: 'Inter', fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, height: 1,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 4),
                        child: Text(
                          '/ $totalExpected',
                          style: TextStyle(
                            fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (totalExpected > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${(todayDone / totalExpected * 100).round()}%',
                            style: TextStyle(
                              fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: totalExpected > 0 ? todayDone / totalExpected : 0,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Weekly View Card ──────────────────────────────────────
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
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.calendar_view_week_rounded, size: 16, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 10),
                        const Text('Weekly View', style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900,
                        )),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 22, color: AppTheme.stone400),
                          onPressed: () => setState(() => _weekOffset--),
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                        ),
                        GestureDetector(
                          onTap: isCurrentWeek ? null : () => setState(() => _weekOffset = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isCurrentWeek ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(weekLabel, style: TextStyle(
                              fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600,
                              color: isCurrentWeek ? AppTheme.primary : AppTheme.stone600,
                            )),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.stone400),
                          onPressed: () => setState(() => _weekOffset++),
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
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
                        const SizedBox(width: 140),
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
                  const Divider(height: 16, color: AppTheme.stone100),

                  // Chore rows or empty state
                  if (choreRows.isEmpty)
                    _buildEmptyState()
                  else
                    ...choreRows.map((row) {
                      final choreIcon = row.chore.icon ?? _guessEmoji(row.chore.title);
                      final choreColor = _parseChoreColor(row.chore.color);

                      return Dismissible(
                        key: Key('${row.chore.id}_${row.userId}'),
                        direction: ((row.chore.creatorId == user.id) || (user.id == family.ownerId))
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('Delete', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.error)),
                              SizedBox(width: 8),
                              Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                            ],
                          ),
                        ),
                        confirmDismiss: (_) async {
                          if (!((row.chore.creatorId == user.id) || (user.id == family.ownerId))) {
                            return false;
                          }
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Chore'),
                              content: Text('Delete "${row.chore.title}" and all completion history?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) => _deleteChore(row.chore.id),
                        child: InkWell(
                        onLongPress: () => _showChoreActions(row.chore),
                        child: Padding(
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
                                      child: Text(choreIcon, style: TextStyle(fontSize: 18)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(row.chore.title, style: TextStyle(
                                            fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone800,
                                          ), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          Text(row.userName, style: TextStyle(
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
                                final isFuture = day.isAfter(today);
                                return Expanded(
                                  child: Center(
                                    child: GestureDetector(
                                      onTap: (isFuture && isCurrentWeek) ? null : () => _toggleCompletion(row.chore, row.userId, day),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
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
                                                    : (isFuture && isCurrentWeek)
                                                        ? AppTheme.stone100
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
                        ),
                      ),
                      );
                    }),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Pending Approvals (owners/admins only) ────────────────
          _buildPendingApprovals(provider, user, familyId, allChores, completions),

          // ── Family Status Today ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: const Text(
              'FAMILY STATUS',
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.1),
            ),
          ),
          const SizedBox(height: 4),
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
                  if (members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text('No family members yet', style: TextStyle(
                          fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400,
                        )),
                      ),
                    )
                  else
                    ...members.asMap().entries.map((entry) {
                      final member = entry.value;
                      final isLast = entry.key == members.length - 1;
                      final memberChores = allChores.where((c) =>
                          c.assigneeIds.contains(member.id) || c.assigneeIds.isEmpty).toList();
                      final memberTotal = memberChores.length;
                      final memberDone = memberChores.where((c) =>
                          _isDoneOnDay(c.id, member.id, today, completions)).length;
                      final progress = memberTotal > 0 ? memberDone / memberTotal : 0.0;
                      final isMe = member.id == user.id;

                      return Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AvatarInitials(name: member.name, size: 32),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isMe ? 'You' : member.name.split(' ').first,
                                        style: TextStyle(
                                          fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      if (memberChores.isNotEmpty)
                                        Wrap(
                                          spacing: 6,
                                          children: memberChores.where((c) =>
                                              !_isDoneOnDay(c.id, member.id, today, completions)).take(3).map((c) {
                                            final icon = c.icon ?? _guessEmoji(c.title);
                                            return Text('$icon ${c.title}', style: TextStyle(
                                              fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400,
                                            ));
                                          }).toList(),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: progress >= 1.0
                                        ? AppTheme.success.withValues(alpha: 0.1)
                                        : AppTheme.stone50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('$memberDone/$memberTotal', style: TextStyle(
                                    fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700,
                                    color: progress >= 1.0 ? AppTheme.success : AppTheme.stone500,
                                  )),
                                ),
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

  Widget _buildEmptyState() {
    final hasSearch = _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: CatalogModuleEmptyState(
        modulePath: '/chores',
        title: hasSearch ? 'No matching chores' : 'No chores yet',
        subtitle: hasSearch ? 'Try a different search term' : 'Tap "Add Chore" to get started',
        actionLabel: hasSearch ? null : 'Add chore',
        onAction: hasSearch ? null : () => _showAddSheet(),
      ),
    );
  }
}

// ─── Helper Classes ──────────────────────────────────────────────────────────

class _ChoreRow {
  final Chore chore;
  final String userId;
  final String userName;
  const _ChoreRow({required this.chore, required this.userId, required this.userName});
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                  Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

// ─── Chore Form Sheet ────────────────────────────────────────────────────────

class _ChoreFormSheet extends StatefulWidget {
  final Future<void> Function(Chore) onSave;
  final Chore? editChore;
  const _ChoreFormSheet({required this.onSave, this.editChore});

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
  bool _rotationEnabled = false;
  bool _isSaving = false;

  bool get _isEditing => widget.editChore != null;

  @override
  void initState() {
    super.initState();
    if (widget.editChore != null) {
      final c = widget.editChore!;
      _titleCtrl.text = c.title;
      _descCtrl.text = c.description ?? '';
      _selectedIconIndex = c.icon != null ? _choreIcons.indexOf(c.icon!) : 0;
      if (_selectedIconIndex < 0) _selectedIconIndex = 0;
      _points = c.points;
      _rewardAmount = c.reward ?? 0;
      _rewardCtrl.text = _rewardAmount > 0 ? _rewardAmount.toStringAsFixed(2) : '0.00';
      _frequency = c.frequency;
      _customDays = List.from(c.daysOfWeek);
      _assigneeIds = List.from(c.assigneeIds);
      _requiresApproval = c.requiresApproval;
      _rotationEnabled = c.rotationEnabled;
      if (c.color != null) {
        final parsed = Color(int.tryParse(c.color!.replaceFirst('#', '0xFF')) ?? 0xFF7C6BFF);
        final idx = _choreColors.indexWhere((cc) => cc.toARGB32() == parsed.toARGB32()); // FIXED: Color.value deprecated
        if (idx >= 0) _selectedColorIndex = idx;
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _rewardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a chore name'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final chore = Chore(
      id: widget.editChore?.id ?? const Uuid().v4(),
      familyId: provider.activeFamily?.id ?? '',
      creatorId: widget.editChore?.creatorId ?? (provider.activeUser?.id ?? ''),
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      icon: _choreIcons[_selectedIconIndex],
      points: _points,
      reward: _rewardAmount > 0 ? _rewardAmount : null,
      frequency: _frequency,
      daysOfWeek: _frequency == ChoreFrequency.CUSTOM ? _customDays : const [],
      assignees: _assigneeIds,
      color: '#${_choreColors[_selectedColorIndex].toARGB32().toRadixString(16).substring(2)}', // FIXED: Color.value deprecated
      requiresApproval: _requiresApproval,
      rotationEnabled: _assigneeIds.length > 1 && _rotationEnabled,
      rotationCursor: widget.editChore?.rotationCursor ?? 0,
      createdAt: widget.editChore?.createdAt ?? DateTime.now(),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isEditing ? Icons.edit_outlined : Icons.add_task_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Edit Chore' : 'New Chore',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.stone400),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // Chore Name
                  _sectionLabel('Chore Name'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleCtrl, autofocus: !_isEditing,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g., Wash the dishes',
                      hintStyle: const TextStyle(color: AppTheme.stone300),
                      filled: true, fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Description
                  _sectionLabel('Description (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl, maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Any extra details...',
                      hintStyle: const TextStyle(color: AppTheme.stone300),
                      filled: true, fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
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
                            _sectionLabel('Icon'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: List.generate(_choreIcons.length, (i) {
                                final selected = i == _selectedIconIndex;
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedIconIndex = i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 36, height: 36,
                                    decoration: BoxDecoration(
                                      color: selected ? AppTheme.primaryLight : AppTheme.stone50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: selected ? Border.all(color: AppTheme.primary, width: 2) : Border.all(color: AppTheme.stone200),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(_choreIcons[i], style: TextStyle(fontSize: 18)),
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
                            _sectionLabel('Points'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [5, 10, 15, 20].map((p) {
                                final selected = p == _points;
                                return GestureDetector(
                                  onTap: () => setState(() => _points = p),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 42, height: 36,
                                    decoration: BoxDecoration(
                                      color: selected ? const Color(0xFFFEF3C7) : AppTheme.stone50,
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
                  _sectionLabel('Color'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: List.generate(_choreColors.length, (i) {
                      final selected = i == _selectedColorIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColorIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: _choreColors[i],
                            shape: BoxShape.circle,
                            border: selected ? Border.all(color: Colors.white, width: 3) : null,
                            boxShadow: selected
                                ? [
                                    BoxShadow(color: _choreColors[i].withValues(alpha: 0.4), blurRadius: 6),
                                    BoxShadow(color: _choreColors[i], blurRadius: 0, spreadRadius: 1.5),
                                  ]
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                              : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Reward per completion
                  _sectionLabel('Reward per completion (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rewardCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => setState(() => _rewardAmount = double.tryParse(v) ?? 0),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone600),
                      filled: true, fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [0, 0.5, 1, 2, 5].map((amount) {
                        final label = amount == 0 ? 'None' : '\$$amount';
                        final selected = _rewardAmount == amount;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _rewardAmount = amount.toDouble();
                              _rewardCtrl.text = amount == 0 ? '0.00' : amount.toStringAsFixed(2);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? const Color(0xFFD1FAE5) : AppTheme.stone50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected ? const Color(0xFF10B981) : AppTheme.stone200,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(label, style: TextStyle(
                                fontFamily: 'Inter', fontSize: 13,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? const Color(0xFF10B981) : AppTheme.stone600,
                              )),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Frequency
                  _sectionLabel('Frequency'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _freqChip('Every Day', ChoreFrequency.DAILY),
                      const SizedBox(width: 8),
                      _freqChip('Weekdays', ChoreFrequency.WEEKLY),
                      const SizedBox(width: 8),
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 42, height: 36,
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.primaryLight : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? AppTheme.primary : AppTheme.stone200,
                                width: selected ? 1.5 : 1,
                              ),
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
                    _sectionLabel('Assign to'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: members.map((m) {
                        final isAssigned = _assigneeIds.contains(m.userId);
                        final name = provider.displayNameForUserId(
                          m.userId,
                          fallback: m.displayName ?? 'Member',
                        );
                        final isMe = m.userId == currentUser?.id;
                        return GestureDetector(
                          onTap: () => setState(() {
                            isAssigned ? _assigneeIds.remove(m.userId) : _assigneeIds.add(m.userId);
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isAssigned ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isAssigned ? AppTheme.primary : AppTheme.stone200,
                                width: isAssigned ? 1.5 : 1,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              AvatarInitials(name: name, size: 22),
                              const SizedBox(width: 6),
                              Text(isMe ? 'Me' : name.split(' ').first, style: TextStyle(
                                fontFamily: 'Inter', fontWeight: isAssigned ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 13, color: isAssigned ? AppTheme.primary : AppTheme.stone700,
                              )),
                              if (isAssigned) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.check_rounded, size: 14, color: AppTheme.primary),
                              ],
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (_assigneeIds.length > 1) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _rotationEnabled ? AppTheme.primary.withValues(alpha: 0.05) : AppTheme.stone50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _rotationEnabled ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.stone200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.rotate_right_rounded, size: 16, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rotate assignees', style: TextStyle(
                                  fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800,
                                )),
                                Text('After someone completes it, the next person is “up next”', style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                                )),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _rotationEnabled,
                            onChanged: (v) => setState(() => _rotationEnabled = v),
                            activeThumbColor: AppTheme.surface,
                            activeTrackColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Requires Parental Approval
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _requiresApproval ? AppTheme.primary.withValues(alpha: 0.05) : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _requiresApproval ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.stone200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.verified_user_outlined, size: 16, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Requires Approval', style: TextStyle(
                                fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800,
                              )),
                              Text('Parents must approve before points are awarded', style: TextStyle(
                                fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400,
                              )),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _requiresApproval,
                          onChanged: (v) => setState(() => _requiresApproval = v),
                          activeThumbColor: AppTheme.surface,
                          activeTrackColor: AppTheme.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Create/Save button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_isEditing ? 'Save Changes' : 'Create Chore', style: TextStyle(
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
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _frequency = freq),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryLight : AppTheme.stone50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.stone200,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontFamily: 'Inter', fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13, color: selected ? AppTheme.primary : AppTheme.stone600,
          )),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone700),
  );
}
