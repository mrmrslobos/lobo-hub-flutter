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

        // Enabled modules
        final enabledModules = moduleGroups
            .expand((g) => g.modules)
            .where((m) =>
                family.enabledModules
                    .contains(m.path.replaceFirst('/', '')))
            .toList();

        // Additional stats
        final monthStart = DateTime(now.year, now.month, 1);
        final eventsThisMonth = db.events
            .where((e) =>
                e.familyId == familyId &&
                !e.startDate.isBefore(monthStart))
            .length;
        final choresTotalToday = db.chores
            .where((c) => c.familyId == familyId)
            .length;
        final spentThisMonth = db.budgetEntries
            .where((e) =>
                e.familyId == familyId &&
                e.type == TransactionType.EXPENSE &&
                !e.date.isBefore(monthStart))
            .fold<double>(0, (sum, e) => sum + e.amount);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primary,
            child: CustomScrollView(
              slivers: [
                // ─── White top nav ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildTopNav(context),
                ),

                // ─── Hero section ──────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildHeroSection(family),
                ),

                // ─── Action buttons ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildActionButtons(context),
                ),

                // ─── Announcement section ──────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildAnnouncementSection(context, provider, family),
                ),

                // ─── AI suggestions ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildAISuggestionsCard(),
                ),

                // ─── 2×2 Stats grid ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _buildStatsGrid(
                    tasksDueToday: tasksDueToday.length,
                    tasksDone: db.tasks
                        .where((t) =>
                            t.familyId == familyId &&
                            t.completed &&
                            t.dueDate != null &&
                            _isSameDay(t.dueDate!, today))
                        .length,
                    choresCompleted: choresToday,
                    choresTotal: choresTotalToday,
                    eventsThisMonth: eventsThisMonth,
                    spentThisMonth: spentThisMonth,
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

                // ─── Bottom padding ────────────────────────────────────────
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopNav(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.stone100)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              const Text(
                'FamilyHub',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.menu, color: AppTheme.stone700, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(Family family) {
    final now = DateTime.now();
    final dayName = DateFormat('EEEE').format(now);
    final monthDay = DateFormat('MMMM d').format(now);
    final day = now.day;
    String suffix = 'th';
    if (day % 100 < 11 || day % 100 > 13) {
      switch (day % 10) {
        case 1: suffix = 'st'; break;
        case 2: suffix = 'nd'; break;
        case 3: suffix = 'rd'; break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hey ${family.name}!',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: AppTheme.stone900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "It's $dayName, $monthDay$suffix. Here's your family at a glance.",
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppTheme.stone500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _circleIconButton(Icons.refresh_rounded, onTap: () => _onRefresh()),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Task'),
            onPressed: () => context.go('/tasks'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _circleIconButton(Icons.trending_up_rounded, onTap: () => context.go('/budget')),
        ],
      ),
    );
  }

  Widget _circleIconButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.stone200),
        ),
        child: Icon(icon, size: 18, color: AppTheme.stone600),
      ),
    );
  }

  Widget _buildAnnouncementSection(
      BuildContext context, AppProvider provider, Family family) {
    final hasAnnouncement = family.announcement != null && !_announcementDismissed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasAnnouncement ? AppTheme.stone200 : AppTheme.primary.withOpacity(0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.campaign_outlined,
              color: hasAnnouncement ? AppTheme.stone500 : AppTheme.stone400,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasAnnouncement ? family.announcement! : 'Pin a family announcement here...',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: hasAnnouncement ? AppTheme.stone700 : AppTheme.stone400,
                ),
              ),
            ),
            if (hasAnnouncement)
              GestureDetector(
                onTap: () => setState(() => _announcementDismissed = true),
                child: const Icon(Icons.close, size: 16, color: AppTheme.stone400),
              )
            else
              Icon(Icons.edit_outlined,
                  size: 16, color: AppTheme.primary.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildAISuggestionsCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.psychology_outlined,
                      color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Suggestions',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                      Text(
                        'Personalised for your day',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primary.withOpacity(0.5)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Thinking...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppTheme.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.stone300),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Analysing your schedule...',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppTheme.stone400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid({
    required int tasksDueToday,
    required int tasksDone,
    required int choresCompleted,
    required int choresTotal,
    required int eventsThisMonth,
    required double spentThisMonth,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          _dashStatCard(
            icon: Icons.check_box_outlined,
            iconColor: const Color(0xFF0D9488),
            value: tasksDueToday.toString(),
            label: 'Tasks Due',
            badge: '$tasksDone done',
            badgeColor: const Color(0xFF0D9488),
          ),
          _dashStatCard(
            icon: Icons.assignment_outlined,
            iconColor: const Color(0xFFF59E0B),
            value: '$choresCompleted/$choresTotal',
            label: 'Chores Today',
            badge: '--',
            badgeColor: AppTheme.stone400,
          ),
          _dashStatCard(
            icon: Icons.calendar_today_outlined,
            iconColor: AppTheme.primary,
            value: eventsThisMonth.toString(),
            label: 'Events This Month',
            badge: 'upcoming',
            badgeColor: AppTheme.primary,
          ),
          _dashStatCard(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: const Color(0xFFEC4899),
            value: '\$${spentThisMonth.toStringAsFixed(0)}',
            label: 'Spent This Month',
            badge: '+\$0',
            badgeColor: AppTheme.success,
          ),
        ],
      ),
    );
  }

  Widget _dashStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required String badge,
    required Color badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.stone100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: badgeColor,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppTheme.stone900,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppTheme.stone500,
            ),
          ),
        ],
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
