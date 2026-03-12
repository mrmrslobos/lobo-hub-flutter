// lib/screens/period_tracker/period_tracker_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class PeriodTrackerScreen extends StatefulWidget {
  const PeriodTrackerScreen({super.key});

  @override
  State<PeriodTrackerScreen> createState() => _PeriodTrackerScreenState();
}

class _PeriodTrackerScreenState extends State<PeriodTrackerScreen> {
  int _selectedTab = 0;
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
  }

  void _showLogSheet({PeriodEntry? existing, DateTime? initialDate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeriodLogSheet(
        existing: existing,
        initialDate: initialDate,
        onSave: (entry) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          List<PeriodEntry> updated;
          if (existing != null) {
            updated = db.periodEntries.map((e) => e.id == entry.id ? entry : e).toList();
          } else {
            updated = [...db.periodEntries, entry];
          }
          await provider.saveAndSync(db.copyWith(periodEntries: updated));
        },
      ),
    );
  }

  void _showDayActionSheet(DateTime date) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayActionSheet(
        date: date,
        onPeriodStarted: () {
          Navigator.pop(context);
          _showLogSheet(initialDate: date);
        },
        onLogSymptoms: () {
          Navigator.pop(context);
          _showSymptomsSheet(date: date);
        },
        onLogIntimate: () {
          Navigator.pop(context);
          _logIntimate(date);
        },
      ),
    );
  }

  void _showSymptomsSheet({required DateTime date}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SymptomsSheet(
        date: date,
        onSave: (log) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(
            periodSymptoms: [...db.periodSymptoms, log],
          ));
        },
      ),
    );
  }

  Future<void> _logIntimate(DateTime date) async {
    final provider = context.read<AppProvider>();
    final user = provider.activeUser!;
    final family = provider.activeFamily!;
    final db = provider.db;
    final dateOnly = DateTime(date.year, date.month, date.day);

    // Check if a symptom log already exists for this day; if so, add to it
    final existing = db.periodSymptoms
        .where((s) => s.userId == user.id && _isSameDay(s.date, dateOnly))
        .toList();

    if (existing.isNotEmpty) {
      final log = existing.first;
      if (!log.symptoms.contains('Intimate 💕')) {
        final updated = log.symptoms.toList()..add('Intimate 💕');
        final updatedLog = PeriodSymptomLog(
          id: log.id,
          userId: log.userId,
          familyId: log.familyId,
          date: log.date,
          symptoms: updated,
          mood: log.mood,
          painLevel: log.painLevel,
          notes: log.notes,
          createdAt: log.createdAt,
        );
        await provider.saveAndSync(db.copyWith(
          periodSymptoms: db.periodSymptoms.map((s) => s.id == log.id ? updatedLog : s).toList(),
        ));
      }
    } else {
      final log = PeriodSymptomLog(
        id: const Uuid().v4(),
        userId: user.id,
        familyId: family.id,
        date: dateOnly,
        symptoms: const ['Intimate 💕'],
        createdAt: DateTime.now(),
      );
      await provider.saveAndSync(db.copyWith(
        periodSymptoms: [...db.periodSymptoms, log],
      ));
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged intimate activity for ${DateFormat('MMM d').format(date)}'),
          backgroundColor: const Color(0xFF9F1239),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showImportSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            const Text('Import Period Data', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
            const SizedBox(height: 8),
            const Text(
              'Paste your period dates below, one per line.\nFormat: start date - end date (YYYY-MM-DD)\n\nExample:\n2025-01-05 - 2025-01-10\n2025-02-03 - 2025-02-08',
              style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
              decoration: InputDecoration(
                hintText: '2025-01-05 - 2025-01-10\n2025-02-03 - 2025-02-08',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone300),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please paste period data to import'), behavior: SnackBarBehavior.floating),
                    );
                    return;
                  }
                  final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
                  final provider = context.read<AppProvider>();
                  final db = provider.db;
                  final uuid = const Uuid();
                  final familyId = provider.activeFamily!.id;
                  final userId = provider.activeUser!.id;
                  final newEntries = <PeriodEntry>[];
                  int failed = 0;

                  for (final line in lines) {
                    try {
                      final parts = line.split(RegExp(r'\s*[-–—]+\s*'));
                      final start = DateTime.parse(parts[0].trim());
                      final end = parts.length > 1 ? DateTime.parse(parts[1].trim()) : null;
                      newEntries.add(PeriodEntry(
                        id: uuid.v4(),
                        familyId: familyId,
                        userId: userId,
                        startDate: start,
                        endDate: end,
                        flowLevel: FlowLevel.MEDIUM,
                        symptoms: const [],
                      ));
                    } catch (_) {
                      failed++;
                    }
                  }

                  if (newEntries.isNotEmpty) {
                    await provider.saveAndSync(db.copyWith(
                      periodEntries: [...db.periodEntries, ...newEntries],
                    ));
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Imported ${newEntries.length} entries${failed > 0 ? ' ($failed failed)' : ''}'),
                      backgroundColor: newEntries.isNotEmpty ? AppTheme.success : AppTheme.error,
                    ));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Import', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      periodEntries: db.periodEntries.where((e) => e.id != id).toList(),
    ));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int? _cycleLengthDays(List<PeriodEntry> entries) {
    if (entries.length < 2) return null;
    final sorted = [...entries]..sort((a, b) => a.startDate.compareTo(b.startDate));
    int total = 0;
    for (int i = 1; i < sorted.length; i++) {
      total += sorted[i].startDate.difference(sorted[i - 1].startDate).inDays;
    }
    return total ~/ (sorted.length - 1);
  }

  int? _daysUntilNext(List<PeriodEntry> entries) {
    final avg = _cycleLengthDays(entries);
    if (avg == null) return null;
    final sorted = [...entries]..sort((a, b) => b.startDate.compareTo(a.startDate));
    final nextDate = sorted.first.startDate.add(Duration(days: avg));
    return nextDate.difference(DateTime.now()).inDays;
  }

  /// Collect all dates that fall within a period entry range
  Set<DateTime> _periodDates(List<PeriodEntry> entries) {
    final dates = <DateTime>{};
    for (final entry in entries) {
      final end = entry.endDate ?? entry.startDate;
      var d = entry.startDate;
      while (!d.isAfter(end)) {
        dates.add(DateTime(d.year, d.month, d.day));
        d = d.add(const Duration(days: 1));
      }
    }
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Only show current user's data - PRIVATE
    final entries = provider.db.periodEntries
        .where((e) => e.familyId == family.id && e.userId == user.id)
        .toList();
    entries.sort((a, b) => b.startDate.compareTo(a.startDate));

    final avgCycle = _cycleLengthDays(entries);
    final daysUntil = _daysUntilNext(entries);

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
            const Text(
              'FamilyHub',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: const [],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            PageHeader(
              title: 'Period Tracker',
              subtitle: 'Track your cycle, symptoms & fertility.',
              actions: [
                ActionChipButton(
                  icon: Icons.download_rounded,
                  label: 'Import',
                  onTap: _showImportSheet,
                  backgroundColor: AppTheme.stone100,
                  foregroundColor: AppTheme.stone700,
                ),
                ActionChipButton(
                  emoji: '😣',
                  label: 'Log Symptoms',
                  onTap: () => _showLogSheet(),
                  backgroundColor: const Color(0xFFFCE7F3),
                  foregroundColor: const Color(0xFFE11D48),
                ),
                ActionChipButton(
                  icon: Icons.loop_rounded,
                  label: 'Log Period',
                  onTap: () => _showLogSheet(),
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  isPrimary: true,
                ),
              ],
            ),

            // Tab Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppTabBar(
                tabs: const ['Calendar', 'History', 'Insights'],
                selectedIndex: _selectedTab,
                onSelected: (i) => setState(() => _selectedTab = i),
              ),
            ),

            const SizedBox(height: 16),

            // Tab content
            if (_selectedTab == 0) _buildCalendarTab(entries),
            if (_selectedTab == 1) _buildHistoryTab(entries),
            if (_selectedTab == 2) _buildInsightsTab(entries, avgCycle, daysUntil),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── Calendar Tab ─────────────────────────────────────────────────────────
  Widget _buildCalendarTab(List<PeriodEntry> entries) {
    final periodDates = _periodDates(entries);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;

    // Collect symptom log dates and intimate dates
    final symptomLogs = user != null
        ? provider.db.periodSymptoms.where((s) => s.userId == user.id).toList()
        : <PeriodSymptomLog>[];
    final symptomDates = symptomLogs.map((s) => DateTime(s.date.year, s.date.month, s.date.day)).toSet();
    final intimateDates = symptomLogs
        .where((s) => s.symptoms.contains('Intimate 💕'))
        .map((s) => DateTime(s.date.year, s.date.month, s.date.day))
        .toSet();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _PeriodCalendar(
            currentMonth: _currentMonth,
            today: today,
            periodDates: periodDates,
            symptomDates: symptomDates,
            intimateDates: intimateDates,
            onPrevMonth: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
            },
            onNextMonth: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
              });
            },
            onDayTap: (date) => _showDayActionSheet(date),
          ),
          const SizedBox(height: 16),
          // Legend
          _buildLegend(),
          const SizedBox(height: 12),
          // Tap instruction
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.stone50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.stone100),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 16, color: AppTheme.stone400),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tap any day to log period, symptoms, or intimate activity',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppTheme.stone500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Onboarding card
          OnboardingCard(
            emoji: '🌸',
            title: 'Track your cycle with ease',
            bullets: const [
              'Tap any day and choose "Log Period Start" to begin',
              'Log symptoms & mood daily for better insights',
              'After 2+ cycles the app predicts your next period',
              'All data is private to you — partners cannot see it',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _legendItem(const Color(0xFFDC2626), 'Period'),
        _legendItem(const Color(0xFF16A34A), 'Ovulation', isStar: true),
        _legendItem(const Color(0xFF86EFAC), 'Fertile'),
        _legendItem(const Color(0xFFD8B4FE), 'PMS'),
        _legendItem(const Color(0xFFFDA4AF), 'Predicted', isOutline: true),
        _legendItem(const Color(0xFF8B5CF6), 'Symptom log'),
        _legendItem(const Color(0xFF991B1B), 'Intimate'),
      ],
    );
  }

  Widget _legendItem(Color color, String label, {bool isOutline = false, bool isStar = false}) {
    Widget dot;
    if (isStar) {
      dot = Icon(Icons.star, size: 10, color: color);
    } else if (isOutline) {
      dot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      );
    } else {
      dot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            color: AppTheme.stone500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─── History Tab ──────────────────────────────────────────────────────────
  Widget _buildHistoryTab(List<PeriodEntry> entries) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: EmptyState(
          emoji: '🌸',
          title: 'No entries yet',
          subtitle: 'Track your period and symptoms privately.',
          actionLabel: 'Log Period',
          onAction: () => _showLogSheet(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: const [
              Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.stone400),
              SizedBox(width: 6),
              Text('Your data is private to you', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
            ]),
          ),
          ...entries.map((entry) {
            final duration = entry.endDate != null
                ? entry.endDate!.difference(entry.startDate).inDays + 1
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Dismissible(
                key: Key(entry.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Entry'),
                      content: const Text('Delete this period log entry? This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
                      ],
                    ),
                  ) ?? false;
                },
                onDismissed: (_) => _deleteEntry(entry.id),
                child: GestureDetector(
                  onTap: () => _showLogSheet(existing: entry),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.stone100),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Text('🌸', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            DateFormat('MMMM d, y').format(entry.startDate),
                            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900),
                          ),
                        ),
                        if (duration != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFFCE7F3), borderRadius: BorderRadius.circular(8)),
                            child: Text('$duration days', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEC4899))),
                          ),
                      ]),
                      if (entry.symptoms.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 4, children: entry.symptoms.map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFFDF4FF), borderRadius: BorderRadius.circular(8)),
                          child: Text(s, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFA855F7))),
                        )).toList()),
                      ],
                      if (entry.flowLevel != null) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Text('Flow: ', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                          ...List.generate(5, (j) => Icon(
                            j < (entry.flowLevel.index + 1) ? Icons.circle : Icons.circle_outlined,
                            size: 10,
                            color: const Color(0xFFEC4899),
                          )),
                        ]),
                      ],
                      if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(entry.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ]),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Insights Tab ─────────────────────────────────────────────────────────
  Widget _buildInsightsTab(List<PeriodEntry> entries, int? avgCycle, int? daysUntil) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: StatCard(
              label: 'Avg cycle length',
              value: avgCycle != null ? '$avgCycle days' : '—',
              emoji: '📅',
              color: const Color(0xFFEC4899),
            )),
            const SizedBox(width: 10),
            Expanded(child: StatCard(
              label: daysUntil != null && daysUntil >= 0 ? 'Days until next' : 'Days since due',
              value: daysUntil != null ? '${daysUntil.abs()}' : '—',
              emoji: '🌸',
              color: const Color(0xFFEC4899),
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: StatCard(
              label: 'Entries logged',
              value: '${entries.length}',
              emoji: '📊',
              color: const Color(0xFFA855F7),
            )),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox()),
          ]),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE7F3).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: const [
              Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFFEC4899)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your data is private to you',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFEC4899)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Calendar helper widget
// ─────────────────────────────────────────────

class _PeriodCalendar extends StatelessWidget {
  final DateTime currentMonth;
  final DateTime today;
  final Set<DateTime> periodDates;
  final Set<DateTime> symptomDates;
  final Set<DateTime> intimateDates;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDayTap;

  const _PeriodCalendar({
    required this.currentMonth,
    required this.today,
    required this.periodDates,
    this.symptomDates = const {},
    this.intimateDates = const {},
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDayTap,
  });

  Widget _dot(Color color) => Container(
    width: 4, height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    final year = currentMonth.year;
    final month = currentMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday

    const dayHeaders = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.stone100),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Month header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onPrevMonth,
                icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.stone600),
                splashRadius: 20,
              ),
              Text(
                DateFormat('MMMM yyyy').format(currentMonth),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.stone900,
                ),
              ),
              IconButton(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.stone600),
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day-of-week headers
          Row(
            children: dayHeaders.map((d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.stone400,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          // Day grid
          ...List.generate(
            ((startWeekday + daysInMonth + 6) ~/ 7), // number of rows
            (row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: List.generate(7, (col) {
                    final dayIndex = row * 7 + col - startWeekday + 1;
                    if (dayIndex < 1 || dayIndex > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 40));
                    }

                    final date = DateTime(year, month, dayIndex);
                    final isToday = date == today;
                    final isPeriod = periodDates.contains(date);
                    final hasSymptom = symptomDates.contains(date);
                    final hasIntimate = intimateDates.contains(date);

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onDayTap(date),
                        child: Container(
                          height: 44,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: isPeriod ? const Color(0xFFDC2626).withValues(alpha: 0.12) : null,
                            shape: BoxShape.circle,
                            border: isToday
                                ? Border.all(color: const Color(0xFFE11D48), width: 2)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dayIndex',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                                  color: isPeriod
                                      ? const Color(0xFFDC2626)
                                      : isToday
                                          ? const Color(0xFFE11D48)
                                          : AppTheme.stone700,
                                ),
                              ),
                              const SizedBox(height: 1),
                              // Indicator dots
                              if (isPeriod || hasSymptom || hasIntimate)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPeriod) _dot(const Color(0xFFDC2626)),
                                    if (hasSymptom) _dot(const Color(0xFF8B5CF6)),
                                    if (hasIntimate) _dot(const Color(0xFF991B1B)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Log period sheet
// ─────────────────────────────────────────────

class _PeriodLogSheet extends StatefulWidget {
  final PeriodEntry? existing;
  final DateTime? initialDate;
  final Future<void> Function(PeriodEntry) onSave;
  const _PeriodLogSheet({this.existing, this.initialDate, required this.onSave});

  @override
  State<_PeriodLogSheet> createState() => _PeriodLogSheetState();
}

class _PeriodLogSheetState extends State<_PeriodLogSheet> {
  late DateTime _startDate;
  DateTime? _endDate;
  List<String> _symptoms = [];
  FlowLevel? _flowLevel;
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;
  final _uuid = const Uuid();

  static const _symptomOptions = [
    'Cramps 😣',
    'Headache 🤕',
    'Bloating 🤰',
    'Fatigue 😴',
    'Mood Swings 🌪️',
    'Nausea 🤢',
    'Backache 🦴',
    'Spotting 🔴',
  ];
  static const _moodOptions = ['😊', '😐', '😢', '😤', '😴'];
  String _mood = '😊';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _startDate = e?.startDate ?? widget.initialDate ?? DateTime.now();
    _endDate = e?.endDate;
    _symptoms = List.from(e?.symptoms ?? []);
    _flowLevel = e?.flowLevel;
    _notesCtrl.text = e?.notes ?? '';
    // mood stored in notes with prefix if present
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? _startDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() {
        if (isStart) _startDate = d;
        else _endDate = d;
      });
    }
  }

  Future<void> _save() async {
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be before start date'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final entry = PeriodEntry(
      id: widget.existing?.id ?? _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      startDate: _startDate,
      endDate: _endDate,
      flowLevel: _flowLevel ?? FlowLevel.MEDIUM,
      symptoms: _symptoms,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.existing != null ? 'Edit Entry' : 'Log Period', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
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
              // Dates
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('START DATE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(DateFormat('MMM d').format(_startDate), style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFFEC4899))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('END DATE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(
                          _endDate != null ? DateFormat('MMM d').format(_endDate!) : 'Ongoing',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: _endDate != null ? const Color(0xFFEC4899) : AppTheme.stone400),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),
              if (_endDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => setState(() => _endDate = null), child: const Text('Clear end date')),
                ),
              const SizedBox(height: 20),
              // Flow level
              const Text('Flow Level', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              Row(children: FlowLevel.values.map((level) {
                final isSelected = _flowLevel == level;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _flowLevel = isSelected ? null : level),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEC4899).withValues(alpha: 0.15) : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone200, width: isSelected ? 2 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(level.name, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone500)),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),
              // Symptoms
              const Text('Symptoms', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _symptomOptions.map((s) {
                final isSelected = _symptoms.contains(s);
                return GestureDetector(
                  onTap: () => setState(() { isSelected ? _symptoms.remove(s) : _symptoms.add(s); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFCE7F3) : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone200, width: isSelected ? 1.5 : 1),
                    ),
                    child: Text(s, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? const Color(0xFFEC4899) : AppTheme.stone600)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),
              // Mood
              const Text('Mood', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.stone600)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _moodOptions.map((emoji) {
                  final selected = _mood == emoji;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFCE7F3) : AppTheme.stone50,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? const Color(0xFFEC4899) : AppTheme.stone200),
                      ),
                      child: Text(emoji, style: TextStyle(fontSize: selected ? 28 : 22)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              // Privacy note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE7F3).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFFEC4899)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Only you can see this data', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFFEC4899)))),
                ]),
              ),
              const SizedBox(height: 16),
              TextField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Day action sheet (tap a calendar date)
// ─────────────────────────────────────────────

class _DayActionSheet extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPeriodStarted;
  final VoidCallback onLogSymptoms;
  final VoidCallback onLogIntimate;

  const _DayActionSheet({
    required this.date,
    required this.onPeriodStarted,
    required this.onLogSymptoms,
    required this.onLogIntimate,
  });

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('EEEE, MMMM d').format(date);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Header row
          Row(children: [
            Expanded(
              child: Text(
                dayLabel,
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF111827)),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.close, size: 20, color: Color(0xFF9CA3AF)),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Period Started button (red)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Text('\u{1F525}', style: TextStyle(fontSize: 18)),
              label: const Text('Period Started', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
              onPressed: onPeriodStarted,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Log Symptoms button (pink/light)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Text('\u{1F615}', style: TextStyle(fontSize: 18)),
              label: const Text('Log Symptoms', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
              onPressed: onLogSymptoms,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFCE7F3),
                foregroundColor: const Color(0xFFE11D48),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Log Intimate button (light/white)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.favorite_border_rounded, size: 20),
              label: const Text('Log Intimate', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
              onPressed: onLogIntimate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF9FAFB),
                foregroundColor: const Color(0xFF374151),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Quick symptoms sheet
// ─────────────────────────────────────────────

class _SymptomsSheet extends StatefulWidget {
  final DateTime date;
  final Future<void> Function(PeriodSymptomLog) onSave;

  const _SymptomsSheet({required this.date, required this.onSave});

  @override
  State<_SymptomsSheet> createState() => _SymptomsSheetState();
}

class _SymptomsSheetState extends State<_SymptomsSheet> {
  final List<String> _selected = [];
  CycleMood? _mood;
  int? _painLevel;
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  static const _symptomOptions = [
    'Cramps 😣', 'Headache 🤕', 'Bloating 🤰', 'Fatigue 😴',
    'Mood Swings 🌪️', 'Nausea 🤢', 'Backache 🦴', 'Spotting 🔴',
    'Breast tenderness', 'Insomnia 😰', 'Cravings 🍫', 'Anxiety 😟',
  ];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected.isEmpty && _mood == null && _painLevel == null && _notesCtrl.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final log = PeriodSymptomLog(
      id: const Uuid().v4(),
      userId: provider.activeUser!.id,
      familyId: provider.activeFamily!.id,
      date: DateTime(widget.date.year, widget.date.month, widget.date.day),
      symptoms: _selected,
      mood: _mood,
      painLevel: _painLevel,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: DateTime.now(),
    );
    await widget.onSave(log);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dayLabel = DateFormat('MMMM d').format(widget.date);
    return DraggableScrollableSheet(
      initialChildSize: 0.75, maxChildSize: 0.92, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Log Symptoms', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF1F2937))),
                  Text(dayLabel, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Color(0xFFEC4899))),
                ]),
              ),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
              // Symptoms
              const Text('Symptoms', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _symptomOptions.map((s) {
                final isSelected = _selected.contains(s);
                return GestureDetector(
                  onTap: () => setState(() { isSelected ? _selected.remove(s) : _selected.add(s); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFCE7F3) : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? const Color(0xFFEC4899) : const Color(0xFFE5E7EB), width: isSelected ? 1.5 : 1),
                    ),
                    child: Text(s, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? const Color(0xFFEC4899) : const Color(0xFF6B7280))),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),
              // Mood
              const Text('Mood', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: CycleMood.values.map((mood) {
                  final emojis = {'GREAT': '😄', 'GOOD': '🙂', 'OKAY': '😐', 'LOW': '😔', 'ROUGH': '😢'};
                  final emoji = emojis[mood.name] ?? '😐';
                  final selected = _mood == mood;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = selected ? null : mood),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFCE7F3) : const Color(0xFFF9FAFB),
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? const Color(0xFFEC4899) : const Color(0xFFE5E7EB)),
                      ),
                      child: Text(emoji, style: TextStyle(fontSize: selected ? 26 : 20)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              // Pain level
              const Text('Pain Level (1–10)', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 10),
              Row(
                children: List.generate(10, (i) {
                  final level = i + 1;
                  final selected = _painLevel == level;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _painLevel = selected ? null : level),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        height: 32,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFEC4899) : (level <= (_painLevel ?? 0) ? const Color(0xFFFCE7F3) : const Color(0xFFF3F4F6)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text('$level', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: selected ? Colors.white : const Color(0xFF9CA3AF))),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 16),
              // Privacy note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE7F3).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFFEC4899)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Only you can see this data', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFFEC4899)))),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
