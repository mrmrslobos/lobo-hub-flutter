import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/module_ui_kit.dart';

/// Minimal wall dashboard: local DB snapshot refreshed periodically (no realtime).
class PhotoframeScreen extends StatefulWidget {
  const PhotoframeScreen({super.key});

  /// Matches typical wall-mount cadence; adjust via code if needed.
  static const Duration syncInterval = Duration(minutes: 30);

  @override
  State<PhotoframeScreen> createState() => _PhotoframeScreenState();
}

class _PhotoframeScreenState extends State<PhotoframeScreen> {
  Timer? _syncTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<AppProvider>();
      unawaited(p.refreshFromCloud());
    });
    _syncTimer = Timer.periodic(PhotoframeScreen.syncInterval, (_) {
      final p = context.read<AppProvider>();
      unawaited(p.refreshFromCloud());
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _mealSlotLabel(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return 'Breakfast';
      case 'lunch':
        return 'Lunch';
      case 'dinner':
        return 'Dinner';
      case 'snack':
        return 'Snack';
      default:
        return mealType;
    }
  }

  int _mealOrder(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return 0;
      case 'lunch':
        return 1;
      case 'dinner':
        return 2;
      case 'snack':
        return 3;
      default:
        return 9;
    }
  }

  String _mealDescription(MealPlanEntry m, AppDB db) {
    final cm = m.customMeal?.trim();
    if (cm != null && cm.isNotEmpty) return cm;
    final rid = m.recipeId;
    if (rid != null && rid.isNotEmpty) {
      final r = db.recipes.firstWhereOrNull((x) => x.id == rid);
      if (r != null && r.title.trim().isNotEmpty) return r.title.trim();
    }
    final n = m.notes?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '—';
  }

  String _eventTime(CalendarEvent e) {
    if (e.allDay) return 'All day';
    return DateFormat.jm().format(e.startDate);
  }

  List<String> _birthdayLines(AppDB db, String familyId, DateTime today) {
    final specialDates =
        db.specialDates.where((d) => d.familyId == familyId).toList();
    if (specialDates.isEmpty) return [];

    final upcoming = <Map<String, dynamic>>[];
    for (final sd in specialDates) {
      var next = DateTime(today.year, sd.month, sd.day);
      if (next.isBefore(today)) {
        next = DateTime(today.year + 1, sd.month, sd.day);
      }
      final daysUntil = next.difference(today).inDays;
      if (daysUntil <= 7) {
        upcoming.add({'sd': sd, 'daysUntil': daysUntil, 'next': next});
      }
    }
    if (upcoming.isEmpty) return [];
    upcoming.sort(
      (a, b) => (a['daysUntil'] as int).compareTo(b['daysUntil'] as int),
    );

    final lines = <String>[];
    for (final item in upcoming.take(4)) {
      final sd = item['sd'] as SpecialDate;
      final daysUntil = item['daysUntil'] as int;
      final suffix = daysUntil == 0
          ? 'today'
          : daysUntil == 1
              ? 'tomorrow'
              : 'in $daysUntil days';
      lines.add('${sd.name} · $suffix');
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final user = provider.activeUser;
        final family = provider.activeFamily;

        if (user == null || family == null) {
          return const ModuleFamilyLoadingScaffold();
        }

        final db = provider.db;
        final familyId = family.id;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final tasksDueToday = db.tasks
            .where((t) =>
                t.familyId == familyId &&
                !t.completed &&
                t.dueDate != null &&
                _sameDay(t.dueDate!, today))
            .length;

        final overdueTasks = db.tasks
            .where((t) =>
                t.familyId == familyId &&
                !t.completed &&
                t.dueDate != null &&
                t.dueDate!.isBefore(today))
            .length;

        final focusTitles = db.tasks
            .where((t) =>
                t.familyId == familyId &&
                !t.completed &&
                t.dueDate != null &&
                (_sameDay(t.dueDate!, today) || t.dueDate!.isBefore(today)))
            .toList()
          ..sort((a, b) {
            final da = a.dueDate!;
            final db_ = b.dueDate!;
            if (_sameDay(da, today) != _sameDay(db_, today)) {
              return _sameDay(da, today) ? -1 : 1;
            }
            return da.compareTo(db_);
          });

        final weekEnd = today.add(const Duration(days: 7));
        final upcomingEvents = db.events
            .where((e) =>
                e.familyId == familyId &&
                !e.startDate.isBefore(today) &&
                e.startDate.isBefore(weekEnd))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));

        final todayMeals = db.mealPlans
            .where((m) => m.familyId == familyId && _sameDay(m.date, today))
            .toList()
          ..sort((a, b) =>
              _mealOrder(a.mealType).compareTo(_mealOrder(b.mealType)));

        final choresAll =
            db.chores.where((c) => c.familyId == familyId).toList();
        final choreCheckoffsToday = db.choreCompletions
            .where((c) =>
                c.familyId == familyId &&
                _sameDay(c.date, today) &&
                c.approvalStatus != ApprovalStatus.REJECTED)
            .length;

        final birthdays = _birthdayLines(db, familyId, today);

        final lastSync = provider.lastSuccessfulSyncAt;
        final syncErr = provider.lastSyncError;
        final syncing = provider.isSyncing;

        final dateStr = DateFormat('EEEE, MMMM d').format(now);
        final timeStr = DateFormat.jm().format(now);

        Widget panel({
          required IconData icon,
          required String title,
          required Widget body,
        }) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 22, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: body),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              family.name,
                              style: tt.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              dateStr,
                              style: tt.titleMedium?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        timeStr,
                        style: tt.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (syncing)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          syncErr != null && syncErr.isNotEmpty
                              ? 'Sync issue — retrying on schedule'
                              : lastSync == null
                                  ? 'Waiting for first sync…'
                                  : 'Updated ${DateFormat('MMM d, h:mm a').format(lastSync)}',
                          style: tt.labelMedium?.copyWith(
                            color: syncErr != null && syncErr.isNotEmpty
                                ? cs.error
                                : cs.onSurface.withValues(alpha: 0.45),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: panel(
                            icon: Icons.task_alt_rounded,
                            title: 'Tasks',
                            body: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Due today $tasksDueToday · Overdue $overdueTasks',
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...focusTitles.take(5).map(
                                      (t) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          '· ${t.title}',
                                          style: tt.bodyMedium?.copyWith(
                                            height: 1.25,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                if (focusTitles.isEmpty)
                                  Text(
                                    'Nothing urgent in view.',
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: panel(
                            icon: Icons.calendar_month_rounded,
                            title: 'This week',
                            body: upcomingEvents.isEmpty
                                ? Text(
                                    'No events in the next 7 days.',
                                    style: tt.bodyMedium?.copyWith(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.5),
                                    ),
                                  )
                                : ListView(
                                    padding: EdgeInsets.zero,
                                    children: upcomingEvents.take(6).map((e) {
                                      final day = _sameDay(e.startDate, today)
                                          ? 'Today'
                                          : DateFormat('EEE')
                                              .format(e.startDate);
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SizedBox(
                                              width: 56,
                                              child: Text(
                                                day,
                                                style: tt.labelLarge?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.primary,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.title,
                                                    style: tt.bodyLarge
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.2,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    _eventTime(e),
                                                    style: tt.labelMedium
                                                        ?.copyWith(
                                                      color: cs.onSurface
                                                          .withValues(
                                                              alpha: 0.45),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: panel(
                                  icon: Icons.restaurant_rounded,
                                  title: 'Today’s meals',
                                  body: todayMeals.isEmpty
                                      ? Text(
                                          'Nothing planned for today.',
                                          style: tt.bodyMedium?.copyWith(
                                            color: cs.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                        )
                                      : ListView(
                                          padding: EdgeInsets.zero,
                                          children: todayMeals.map((m) {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Text(
                                                '${_mealSlotLabel(m.mealType)} · ${_mealDescription(m, db)}',
                                                style: tt.bodyLarge?.copyWith(
                                                  height: 1.25,
                                                ),
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                flex: 2,
                                child: panel(
                                  icon: Icons.celebration_rounded,
                                  title: 'Home snapshot',
                                  body: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Check-offs today $choreCheckoffsToday · ${choresAll.length} active chores',
                                        style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (birthdays.isEmpty)
                                        Text(
                                          'No celebrations in the next week.',
                                          style: tt.bodyMedium?.copyWith(
                                            color: cs.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                        )
                                      else
                                        ...birthdays.map(
                                          (line) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 6),
                                            child: Text(
                                              line,
                                              style: tt.bodyMedium?.copyWith(
                                                height: 1.25,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
