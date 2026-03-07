// lib/screens/dashboard/dashboard_screen.dart
// Home dashboard screen for FamilyHub

import 'package:flutter/material.dart' hide Visibility;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../config/module_config.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/common_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _announcementDismissed = false;

  Future<void> _onRefresh() async {
    // Trigger a re-read from provider / sync
    final provider = context.read<AppProvider>();
    await provider.saveAndSync(provider.db);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final user = provider.activeUser;
        final family = provider.activeFamily;

        if (user == null || family == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final db = provider.db;
        final familyId = family.id;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        // Tasks due today (incomplete)
        final tasksDueToday = db.tasks
            .where((t) =>
                t.familyId == familyId &&
                !t.completed &&
                t.dueDate != null &&
                _isSameDay(t.dueDate!, today))
            .toList();

        // Events today
        final eventsToday = db.events
            .where((e) =>
                e.familyId == familyId && _isSameDay(e.startDate, today))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        // Events this week (next 7 days, excluding today)
        final weekEnd = today.add(const Duration(days: 7));
        final eventsThisWeek = db.events
            .where((e) =>
                e.familyId == familyId &&
                e.startDate.isAfter(today) &&
                e.startDate.isBefore(weekEnd))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        // Chores completed today
        final choresToday = db.chores
            .where((c) =>
                c.familyId == familyId &&
                c.lastCompletedAt != null &&
                _isSameDay(c.lastCompletedAt!, today))
            .length;

        // Reward points for current user
        final myPoints = provider.chorePointsForUser(user.id);

        // Enabled modules
        final enabledModules = moduleGroups
            .expand((g) => g.modules)
            .where((m) =>
                family.enabledModules
                    .contains(m.path.replaceFirst('/', '')))
            .toList();

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primary,
            child: CustomScrollView(
              slivers: [
                // ─── App bar / header ──────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildHeader(context, user, family),
                ),

                // ─── Announcement banner ───────────────────────────────────
                if (family.announcement != null &&
                    !_announcementDismissed)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: _AnnouncementBanner(
                        message: family.announcement!,
                        onDismiss: () => setState(
                            () => _announcementDismissed = true),
                      ),
                    ),
                  ),

                // ─── Stats row ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            emoji: '✅',
                            label: 'Tasks today',
                            value: tasksDueToday.length.toString(),
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            emoji: '📅',
                            label: 'Events today',
                            value: eventsToday.length.toString(),
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            emoji: '⭐',
                            label: 'My points',
                            value: myPoints.toString(),
                            color: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── Today's tasks ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Today'),
                        const SizedBox(height: 8),
                        if (tasksDueToday.isEmpty)
                          SectionCard(
                            child: Row(
                              children: [
                                const Text('🎉',
                                    style: TextStyle(fontSize: 24)),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'All done! No tasks due today.',
                                    style: TextStyle(
                                      color: AppTheme.stone600,
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          SectionCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (int i = 0;
                                    i < tasksDueToday.length;
                                    i++) ...[
                                  if (i > 0)
                                    const Divider(height: 1),
                                  _TaskTile(
                                    task: tasksDueToday[i],
                                    provider: provider,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ─── This week events ──────────────────────────────────────
                if (eventsThisWeek.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader(title: 'This Week'),
                          const SizedBox(height: 8),
                          SectionCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (int i = 0;
                                    i < eventsThisWeek.length;
                                    i++) ...[
                                  if (i > 0)
                                    const Divider(height: 1),
                                  _EventTile(
                                      event: eventsThisWeek[i]),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ─── Module grid ───────────────────────────────────────────
                if (enabledModules.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader(title: 'Modules'),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),

                if (enabledModules.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final mod = enabledModules[i];
                          return ModuleCard(
                            emoji: mod.emoji,
                            name: mod.name,
                            onTap: () => context.go(mod.path),
                          );
                        },
                        childCount: enabledModules.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.1,
                      ),
                    ),
                  ),

                // ─── Chores summary ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            emoji: '🧹',
                            label: 'Chores done today',
                            value: choresToday.toString(),
                            color: AppTheme.success,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            emoji: '👨‍👩‍👧',
                            label: 'Family members',
                            value: provider.familyMembers.length
                                .toString(),
                            color: const Color(0xFFEC4899),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, User user, Family family) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, Color(0xFF8B5CF6)],
        ),
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_greeting()},',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        user.name.split(' ').first + '!',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Family name chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.home_outlined,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        family.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE, MMMM d').format(DateTime.now()),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─── Announcement banner ──────────────────────────────────────────────────────

class _AnnouncementBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _AnnouncementBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Text('📢', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                size: 18, color: Color(0xFF92400E)),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ─── Task tile ────────────────────────────────────────────────────────────────

class _TaskTile extends StatelessWidget {
  final Task task;
  final AppProvider provider;

  const _TaskTile({required this.task, required this.provider});

  Future<void> _toggleComplete(BuildContext context) async {
    final db = provider.db;
    final updated = task.copyWith(completed: !task.completed);
    final tasks = db.tasks.map((t) => t.id == task.id ? updated : t).toList();
    await provider.saveAndSync(db.copyWith(tasks: tasks));
  }

  @override
  Widget build(BuildContext context) {
    final assignee = task.assigneeIds.isNotEmpty
        ? provider.userById(task.assigneeIds.first)
        : null;

    return InkWell(
      onTap: () => _toggleComplete(context),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Checkbox
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: task.completed
                      ? AppTheme.success
                      : AppTheme.stone300,
                  width: 2,
                ),
                color: task.completed
                    ? AppTheme.success
                    : Colors.transparent,
              ),
              child: task.completed
                  ? const Icon(Icons.check,
                      size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // Title
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: task.completed
                      ? AppTheme.stone400
                      : AppTheme.stone800,
                  decoration: task.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PriorityBadge(
                priority: task.priority.name.toUpperCase()),
            if (assignee != null) ...[
              const SizedBox(width: 8),
              AvatarInitials(name: assignee.name, size: 26),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Event tile ───────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final CalendarEvent event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final timeStr = event.allDay
        ? 'All day'
        : DateFormat('h:mm a').format(event.startDate);
    final isPersonal = event.visibility == Visibility.PRIVATE;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color:
                  isPersonal ? AppTheme.primary : const Color(0xFF8B5CF6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.stone800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.stone500,
                      ),
                    ),
                    if (event.location != null) ...[
                      const Text(' · ',
                          style: TextStyle(color: AppTheme.stone400)),
                      Expanded(
                        child: Text(
                          event.location!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.stone500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            DateFormat('EEE d').format(event.startDate),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppTheme.stone400,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
