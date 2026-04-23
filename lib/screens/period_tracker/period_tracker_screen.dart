// lib/screens/period_tracker/period_tracker_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/module_disclaimer.dart';

import '../../config/cloud_sync_scope.dart';
import '../../config/module_config.dart';
import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../services/notification_service.dart';
import '../../utils/debounce.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _uuid = Uuid();

// Theme colors for period tracker (pink palette)
const _pink = Color(0xFFEC4899);
const _pinkDark = Color(0xFFE11D48);
const _pinkLight = Color(0xFFFCE7F3);

const _symptomOptions = [
  'Cramps 😣',
  'Headache 🤕',
  'Bloating 🤰',
  'Fatigue 😴',
  'Mood Swings 🌪️',
  'Nausea 🤢',
  'Backache 🦴',
  'Spotting 🔴',
  'Breast tenderness',
  'Insomnia 😰',
  'Cravings 🍫',
  'Anxiety 😟',
];

const _periodLogSymptoms = [
  'Cramps 😣',
  'Headache 🤕',
  'Bloating 🤰',
  'Fatigue 😴',
  'Mood Swings 🌪️',
  'Nausea 🤢',
  'Backache 🦴',
  'Spotting 🔴',
];

const _moodEmojis = {
  CycleMood.GREAT: '😄',
  CycleMood.GOOD: '🙂',
  CycleMood.OKAY: '😐',
  CycleMood.LOW: '😔',
  CycleMood.ROUGH: '😢',
};

const _periodMoodOptions = ['😊', '😐', '😢', '😤', '😴'];

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

Future<bool> _confirmRemove(BuildContext context, String title, String message) async {
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
        Expanded(child: Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800))),
      ]),
      content: Text(message, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

InputDecoration _styledInput(String hint, {IconData? icon}) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: AppTheme.stone300, fontFamily: 'Inter', fontSize: 13),
  prefixIcon: icon != null ? Icon(icon, size: 20, color: AppTheme.stone400) : null,
  filled: true,
  fillColor: Colors.white,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: AppTheme.stone200),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: AppTheme.stone200),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _pink, width: 1.5),
  ),
);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Widget _sectionLabel(String text) => Text(
  text,
  style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppTheme.stone400),
);

Widget _privacyNote() => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
    color: _pinkLight.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(10),
  ),
  child: const Row(children: [
    Icon(Icons.lock_outline_rounded, size: 14, color: _pink),
    SizedBox(width: 8),
    Expanded(child: Text('Only you can see this data', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, color: _pink))),
  ]),
);

// ─── Period Tracker Screen ────────────────────────────────────────────────────

class PeriodTrackerScreen extends StatefulWidget {
  const PeriodTrackerScreen({super.key});

  @override
  State<PeriodTrackerScreen> createState() => _PeriodTrackerScreenState();
}

class _PeriodTrackerScreenState extends State<PeriodTrackerScreen> {
  int _selectedTab = 0;
  late DateTime _currentMonth;
  final _historySearchCtrl = TextEditingController();
  final _historySearchDebounce = Debouncer();
  String _historySearchQuery = '';

  bool _fertilityRemindersEnabled = false;
  String? _fertilityRemindersLastScheduleKey;

  DateTime? _lastFertileStartDate;
  DateTime? _lastOvulationDate;

  bool _fertilityScheduleInFlight = false;
  String? _lastPredictionTriggerKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<AppProvider>()
          .scheduleModuleEnterCloudPull(CloudSyncScope.periodBundle);
      final uid = context.read<AppProvider>().activeUser?.id;
      if (uid == null) return;
      showModuleDisclaimer(
        context: context,
        userId: uid,
        moduleKey: 'period_tracker',
        title: 'Period Tracker',
        icon: Icons.spa_rounded,
        body: 'The Period Tracker provides cycle tracking and fertility predictions based on your logged data.\n\n'
            'Predictions are estimates only and should not be relied upon for medical decisions, family planning, or contraception.\n\n'
            'Always consult a healthcare professional for medical advice regarding your reproductive health.',
      );
    });

    _historySearchCtrl.addListener(() {
      final t = _historySearchCtrl.text;
      _historySearchDebounce.run(() {
        if (mounted) setState(() => _historySearchQuery = t);
      });
    });

    // Load reminder toggle after providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFertilityReminderPrefs();
    });
  }

  @override
  void dispose() {
    _historySearchCtrl.dispose();
    _historySearchDebounce.dispose();
    super.dispose();
  }

  String _prefsKeyFor(String userId, String suffix) =>
      'fertility_reminders_${suffix}_$userId';

  String _dateOnlyKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _fertilityNotifId({
    required String userId,
    required String kind,
    required DateTime dateOnly,
  }) {
    final dateKey = _dateOnlyKey(dateOnly);
    final s = '${kind}_${userId}_$dateKey';
    return s.hashCode.abs() % 2147483647;
  }

  String _scheduleKey({
    required String userId,
    required DateTime fertileStartDateOnly,
    required DateTime ovulationDateOnly,
  }) {
    return 'fertility_${userId}_${_dateOnlyKey(fertileStartDateOnly)}_${_dateOnlyKey(ovulationDateOnly)}';
  }

  Future<void> _loadFertilityReminderPrefs() async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKeyFor(userId, 'enabled')) ?? false;
    final lastKey = prefs.getString(_prefsKeyFor(userId, 'last_schedule_key'));
    final lastFertileStr =
        prefs.getString(_prefsKeyFor(userId, 'last_fertile_start'));
    final lastOvulationStr =
        prefs.getString(_prefsKeyFor(userId, 'last_ovulation_date'));

    DateTime? parseDateOnly(String? s) {
      if (s == null || s.isEmpty) return null;
      // We store as ISO date; parsing is safe.
      return DateTime.tryParse(s);
    }

    if (!mounted) return;
    setState(() {
      _fertilityRemindersEnabled = enabled;
      _fertilityRemindersLastScheduleKey = lastKey;
      _lastFertileStartDate = parseDateOnly(lastFertileStr);
      _lastOvulationDate = parseDateOnly(lastOvulationStr);
    });
  }

  List<DateTime?> _predictFertilityDates(List<PeriodEntry> entries, int? avgCycle) {
    if (avgCycle == null || entries.isEmpty) return [null, null];
    final sorted = [...entries]..sort((a, b) => b.startDate.compareTo(a.startDate));
    final lastStart = DateTime(sorted.first.startDate.year, sorted.first.startDate.month, sorted.first.startDate.day);
    final nextPeriodStart = lastStart.add(Duration(days: avgCycle));
    final nextPeriodStartDateOnly = DateTime(nextPeriodStart.year, nextPeriodStart.month, nextPeriodStart.day);
    final ovulationDateOnly = nextPeriodStartDateOnly.subtract(const Duration(days: 14));
    final fertileStartDateOnly = ovulationDateOnly.subtract(const Duration(days: 5));
    return [fertileStartDateOnly, ovulationDateOnly];
  }

  Future<void> _cancelFertilityRemindersForLastDates() async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;
    final fertile = _lastFertileStartDate;
    final ovulation = _lastOvulationDate;
    if (fertile == null && ovulation == null) return;

    if (fertile != null) {
      final fertileId = _fertilityNotifId(userId: userId, kind: 'fertile', dateOnly: fertile);
      await NotificationService.cancel(fertileId);
    }
    if (ovulation != null) {
      final ovulationId = _fertilityNotifId(userId: userId, kind: 'ovulation', dateOnly: ovulation);
      await NotificationService.cancel(ovulationId);
    }
  }

  Future<void> _setFertilityRemindersEnabled(bool enabled) async {
    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyFor(userId, 'enabled'), enabled);

    if (!enabled) {
      await _cancelFertilityRemindersForLastDates();
      await prefs.remove(_prefsKeyFor(userId, 'last_schedule_key'));
      await prefs.remove(_prefsKeyFor(userId, 'last_fertile_start'));
      await prefs.remove(_prefsKeyFor(userId, 'last_ovulation_date'));

      if (!mounted) return;
      setState(() {
        _fertilityRemindersEnabled = false;
        _fertilityRemindersLastScheduleKey = null;
        _lastFertileStartDate = null;
        _lastOvulationDate = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _fertilityRemindersEnabled = true);
  }

  Future<void> _maybeScheduleFertilityReminders({
    required DateTime? fertileStartDateOnly,
    required DateTime? ovulationDateOnly,
  }) async {
    if (!_fertilityRemindersEnabled) return;
    if (fertileStartDateOnly == null || ovulationDateOnly == null) return;

    final provider = context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    if (userId == null) return;
    if (_fertilityScheduleInFlight) return;

    final now = DateTime.now();
    final nowDateOnly = DateTime(now.year, now.month, now.day);
    const maxDaysAhead = 45;
    if (fertileStartDateOnly.isBefore(nowDateOnly) ||
        ovulationDateOnly.isBefore(nowDateOnly)) return;
    final daysToFertile = fertileStartDateOnly.difference(nowDateOnly).inDays;
    final daysToOvulation = ovulationDateOnly.difference(nowDateOnly).inDays;
    if (daysToFertile > maxDaysAhead || daysToOvulation > maxDaysAhead) return;

    final scheduleKey = _scheduleKey(
      userId: userId,
      fertileStartDateOnly: fertileStartDateOnly,
      ovulationDateOnly: ovulationDateOnly,
    );

    if (_fertilityRemindersLastScheduleKey == scheduleKey) return;

    setState(() {
      _fertilityScheduleInFlight = true;
    });

    try {
      // Cancel old notifications if we had a previous schedule.
      if (_lastFertileStartDate != null || _lastOvulationDate != null) {
        await _cancelFertilityRemindersForLastDates();
      }

      final fertileWhen = DateTime(
        fertileStartDateOnly.year,
        fertileStartDateOnly.month,
        fertileStartDateOnly.day,
        9,
        0,
        0,
      );
      final ovulationWhen = DateTime(
        ovulationDateOnly.year,
        ovulationDateOnly.month,
        ovulationDateOnly.day,
        9,
        0,
        0,
      );

      await NotificationService.scheduleOnce(
        id: _fertilityNotifId(
          userId: userId,
          kind: 'fertile',
          dateOnly: fertileStartDateOnly,
        ),
        title: 'Fertile window starts',
        body:
            'Predicted fertile window starts on ${DateFormat('MMM d').format(fertileStartDateOnly)}.',
        when: fertileWhen,
        payload: '/period_tracker',
      );

      await NotificationService.scheduleOnce(
        id: _fertilityNotifId(
          userId: userId,
          kind: 'ovulation',
          dateOnly: ovulationDateOnly,
        ),
        title: 'Ovulation predicted',
        body:
            'Predicted ovulation day is ${DateFormat('MMM d').format(ovulationDateOnly)}.',
        when: ovulationWhen,
        payload: '/period_tracker',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyFor(userId, 'last_schedule_key'), scheduleKey);
      await prefs.setString(_prefsKeyFor(userId, 'last_fertile_start'), fertileStartDateOnly.toIso8601String());
      await prefs.setString(_prefsKeyFor(userId, 'last_ovulation_date'), ovulationDateOnly.toIso8601String());

      if (!mounted) return;
      setState(() {
        _fertilityRemindersLastScheduleKey = scheduleKey;
        _lastFertileStartDate = fertileStartDateOnly;
        _lastOvulationDate = ovulationDateOnly;
      });
    } finally {
      if (mounted) {
        setState(() => _fertilityScheduleInFlight = false);
      }
    }
  }

  void _showLogSheet({PeriodEntry? existing, DateTime? initialDate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeriodLogSheet(
        existing: existing,
        initialDate: initialDate,
        onSave: (entry, moodEmoji) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          List<PeriodEntry> updated;
          if (existing != null) {
            updated = db.periodEntries.map((e) => e.id == entry.id ? entry : e).toList();
          } else {
            updated = [...db.periodEntries, entry];
          }
          final logDate = DateTime(entry.startDate.year, entry.startDate.month, entry.startDate.day);
          final existingMoodLog = db.periodSymptoms.cast<PeriodSymptomLog?>().firstWhere(
            (s) =>
                s?.userId == entry.userId &&
                s?.familyId == entry.familyId &&
                _isSameDay(s!.date, logDate),
            orElse: () => null,
          );
          final mood = switch (moodEmoji) {
            '😄' => CycleMood.GREAT,
            '🙂' => CycleMood.GOOD,
            '😐' => CycleMood.OKAY,
            '😔' => CycleMood.LOW,
            '😢' => CycleMood.ROUGH,
            _ => null,
          };
          final withMoodLogs = mood == null
              ? db.periodSymptoms
              : existingMoodLog == null
                  ? [
                      ...db.periodSymptoms,
                      PeriodSymptomLog(
                        id: _uuid.v4(),
                        userId: entry.userId,
                        familyId: entry.familyId,
                        date: logDate,
                        symptoms: const [],
                        mood: mood,
                        createdAt: DateTime.now(),
                      ),
                    ]
                  : db.periodSymptoms
                      .map((s) => s.id == existingMoodLog.id
                          ? PeriodSymptomLog(
                              id: s.id,
                              userId: s.userId,
                              familyId: s.familyId,
                              date: s.date,
                              symptoms: s.symptoms,
                              mood: mood,
                              painLevel: s.painLevel,
                              notes: s.notes,
                              createdAt: s.createdAt,
                            )
                          : s)
                      .toList();

          await provider.saveAndSync(
            db.copyWith(periodEntries: updated, periodSymptoms: withMoodLogs),
            pushTableScope: CloudSyncScope.periodBundle,
          );
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
          final existing = db.periodSymptoms.cast<PeriodSymptomLog?>().firstWhere(
            (s) =>
                s?.userId == log.userId &&
                s?.familyId == log.familyId &&
                _isSameDay(s!.date, log.date),
            orElse: () => null,
          );
          final updatedSymptoms = existing == null
              ? [...db.periodSymptoms, log]
              : db.periodSymptoms
                  .map((s) => s.id == existing.id
                      ? PeriodSymptomLog(
                          id: existing.id,
                          userId: log.userId,
                          familyId: log.familyId,
                          date: log.date,
                          symptoms: log.symptoms,
                          mood: log.mood,
                          painLevel: log.painLevel,
                          notes: log.notes,
                          createdAt: existing.createdAt,
                        )
                      : s)
                  .toList();
          await provider.saveAndSync(
            db.copyWith(periodSymptoms: updatedSymptoms),
            pushTableScope: CloudSyncScope.periodBundle,
          );
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
        await provider.saveAndSync(
          db.copyWith(
            periodSymptoms: db.periodSymptoms.map((s) => s.id == log.id ? updatedLog : s).toList(),
          ),
          pushTableScope: CloudSyncScope.periodBundle,
        );
      }
    } else {
      final log = PeriodSymptomLog(
        id: _uuid.v4(),
        userId: user.id,
        familyId: family.id,
        date: dateOnly,
        symptoms: const ['Intimate 💕'],
        createdAt: DateTime.now(),
      );
      await provider.saveAndSync(
        db.copyWith(periodSymptoms: [...db.periodSymptoms, log]),
        pushTableScope: CloudSyncScope.periodBundle,
      );
    }

    if (mounted) {
      _showSnack(context, 'Logged intimate activity for ${DateFormat('MMM d').format(date)}');
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
              decoration: _styledInput('2025-01-05 - 2025-01-10\n2025-02-03 - 2025-02-08'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) {
                    _showSnack(context, 'Please paste period data to import');
                    return;
                  }
                  final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
                  final provider = context.read<AppProvider>();
                  final db = provider.db;
                  final familyId = provider.activeFamily!.id;
                  final userId = provider.activeUser!.id;
                  final newEntries = <PeriodEntry>[];
                  int failed = 0;

                  for (final line in lines) {
                    try {
                      final normalized = line.replaceAll('–', '-').replaceAll('—', '-');
                      final parts = normalized.split(RegExp(r'\s+-\s+'));
                      final start = DateTime.parse(parts[0].trim());
                      final end = parts.length > 1 ? DateTime.parse(parts[1].trim()) : null;
                      newEntries.add(PeriodEntry(
                        id: _uuid.v4(),
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
                    await provider.saveAndSync(
                      db.copyWith(periodEntries: [...db.periodEntries, ...newEntries]),
                      pushTableScope: CloudSyncScope.periodBundle,
                    );
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    _showSnack(context, 'Imported ${newEntries.length} entries${failed > 0 ? ' ($failed failed)' : ''}');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pinkDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Import', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteEntry(BuildContext context, String id) async {
    final provider = this.context.read<AppProvider>();
    final userId = provider.activeUser?.id;
    final entry = provider.db.periodEntries.cast<PeriodEntry?>().firstWhere(
      (e) => e?.id == id,
      orElse: () => null,
    );
    if (entry == null || userId == null || entry.userId != userId) {
      if (mounted) _showSnack(context, 'You can only delete your own period entries.');
      return;
    }
    final ok = await _confirmRemove(context, 'Delete Entry', 'Delete this period log entry? This cannot be undone.');
    if (!ok) return;
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(periodEntries: db.periodEntries.where((e) => e.id != id).toList()),
      pushTableScope: CloudSyncScope.periodBundle,
    );
  }

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

    // Private data — only current user
    final entries = provider.db.periodEntries
        .where((e) => e.familyId == family.id && e.userId == user.id)
        .toList();
    entries.sort((a, b) => b.startDate.compareTo(a.startDate));

    final avgCycle = _cycleLengthDays(entries);
    final daysUntil = _daysUntilNext(entries);

    final prediction = _predictFertilityDates(entries, avgCycle);
    final predictedFertileStart = prediction[0];
    final predictedOvulationDate = prediction[1];

    final predictionKey = predictedFertileStart != null && predictedOvulationDate != null
        ? '${_selectedTab}_${_dateOnlyKey(predictedFertileStart)}_${_dateOnlyKey(predictedOvulationDate)}'
        : null;
    if ((_selectedTab == 0 || _selectedTab == 2) &&
        predictionKey != null &&
        predictionKey != _lastPredictionTriggerKey) {
      _lastPredictionTriggerKey = predictionKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _maybeScheduleFertilityReminders(
            fertileStartDateOnly: predictedFertileStart,
            ovulationDateOnly: predictedOvulationDate,
          ),
        );
      });
    }

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const MainAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: screenTitleForModulePath('/period-tracker'),
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
                  onTap: () => _showSymptomsSheet(date: DateTime.now()),
                  backgroundColor: _pinkLight,
                  foregroundColor: _pinkDark,
                ),
                ActionChipButton(
                  icon: Icons.loop_rounded,
                  label: 'Log Period',
                  onTap: () => _showLogSheet(),
                  backgroundColor: _pinkDark,
                  foregroundColor: Colors.white,
                  isPrimary: true,
                ),
                ActionChipButton(
                  icon: Icons.notifications_active_rounded,
                  label: _fertilityRemindersEnabled
                      ? 'Fertility reminders: On'
                      : 'Fertility reminders',
                  onTap: () {
                    unawaited(
                      _setFertilityRemindersEnabled(!_fertilityRemindersEnabled),
                    );
                  },
                  backgroundColor: AppTheme.stone100,
                  foregroundColor: AppTheme.stone700,
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFFA8A29E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Predictions are estimates only and should not be used as medical advice. Consult a healthcare provider for medical decisions.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFFA8A29E),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Stats Row ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.calendar_today_rounded,
                  iconColor: _pink,
                  value: avgCycle != null ? '$avgCycle d' : '—',
                  label: 'Avg Cycle',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.schedule_rounded,
                  iconColor: const Color(0xFFA855F7),
                  value: daysUntil != null ? '${daysUntil.abs()}' : '—',
                  label: daysUntil != null && daysUntil >= 0 ? 'Days Left' : 'Days Late',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.auto_graph_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  value: '${entries.length}',
                  label: 'Entries',
                ),
              ]),
            ),

            // ── Tab Bar ──
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
            if (_selectedTab == 1) _buildHistoryTab(entries, _historySearchQuery),
            if (_selectedTab == 2) _buildInsightsTab(entries, avgCycle, daysUntil),
          ],
        ),
      ),
    );
  }

  // ─── Calendar Tab ───────────────────────────────────────────────────────────
  Widget _buildCalendarTab(List<PeriodEntry> entries) {
    final periodDates = _periodDates(entries);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;

    // Flo F1: predicted fertile window + ovulation date.
    final fertileDates = <DateTime>{};
    final ovulationDates = <DateTime>{};
    final avgCycle = _cycleLengthDays(entries);
    if (avgCycle != null && entries.isNotEmpty) {
      final sorted = [...entries]..sort((a, b) => b.startDate.compareTo(a.startDate));
      final lastStartDate = DateTime(
        sorted.first.startDate.year,
        sorted.first.startDate.month,
        sorted.first.startDate.day,
      );
      final nextPeriodStart = lastStartDate.add(Duration(days: avgCycle));
      final nextPeriodStartDateOnly = DateTime(nextPeriodStart.year, nextPeriodStart.month, nextPeriodStart.day);
      final ovulationDate = nextPeriodStartDateOnly.subtract(const Duration(days: 14));
      final fertileStart = ovulationDate.subtract(const Duration(days: 5));

      for (int i = 0; i <= 6; i++) {
        final d = fertileStart.add(Duration(days: i));
        fertileDates.add(DateTime(d.year, d.month, d.day));
      }
      ovulationDates.add(DateTime(ovulationDate.year, ovulationDate.month, ovulationDate.day));
    }

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
      child: Column(children: [
        _PeriodCalendar(
          currentMonth: _currentMonth,
          today: today,
          periodDates: periodDates,
          symptomDates: symptomDates,
          intimateDates: intimateDates,
          fertileDates: fertileDates,
          ovulationDates: ovulationDates,
          onPrevMonth: () => setState(() {
            _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
          }),
          onNextMonth: () => setState(() {
            _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
          }),
          onDayTap: (date) => _showDayActionSheet(date),
        ),
        const SizedBox(height: 16),
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
          child: const Row(children: [
            Icon(Icons.touch_app_rounded, size: 16, color: AppTheme.stone400),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap any day to log period, symptoms, or intimate activity',
                style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const OnboardingCard(
          emoji: '🌸',
          title: 'Track your cycle with ease',
          bullets: [
            'Tap any day and choose "Log Period Start" to begin',
            'Log symptoms & mood daily for better insights',
            'After 2+ cycles the app predicts your next period',
            'All data is private to you — partners cannot see it',
          ],
        ),
      ]),
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
        width: 10, height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
      );
    } else {
      dot = Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ─── History Tab ────────────────────────────────────────────────────────────
  Widget _buildHistoryTab(List<PeriodEntry> entries, String rawQ) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: EmptyState(
          emoji: '🌸',
          title: 'No entries yet',
          subtitle: 'Track your period and symptoms privately.',
        ),
      );
    }

    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final allSymptomLogs = user != null
        ? provider.db.periodSymptoms.where((s) => s.userId == user.id).toList()
        : <PeriodSymptomLog>[];
    final q = rawQ.trim().toLowerCase();
    bool entryMatches(PeriodEntry entry) {
      if (q.isEmpty) return true;
      if (DateFormat('MMMM d, y').format(entry.startDate).toLowerCase().contains(q)) return true;
      if (entry.endDate != null &&
          DateFormat('MMM d').format(entry.endDate!).toLowerCase().contains(q)) {
        return true;
      }
      if (entry.notes != null && entry.notes!.toLowerCase().contains(q)) return true;
      if (entry.flowLevel.name.toLowerCase().contains(q)) return true;
      final endDate = entry.endDate ?? entry.startDate;
      final syms = allSymptomLogs
          .where((s) => !s.date.isBefore(entry.startDate) && !s.date.isAfter(endDate))
          .expand((s) => s.symptoms)
          .any((s) => s.toLowerCase().contains(q));
      return syms;
    }
    final filtered = q.isEmpty ? entries : entries.where(entryMatches).toList();

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
          TextField(
            controller: _historySearchCtrl,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search history…',
              hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
              prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
              suffixIcon: _historySearchQuery.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                      onPressed: () {
                        _historySearchCtrl.clear();
                        setState(() => _historySearchQuery = '');
                      },
                    ),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _pink, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty && q.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No matches — try another word or date.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)),
            ),
          ...filtered.map((entry) {
            final duration = entry.endDate != null
                ? entry.endDate!.difference(entry.startDate).inDays + 1
                : null;

            // Look up symptoms from PeriodSymptomLog for this entry's date range
            final endDate = entry.endDate ?? entry.startDate;
            final entrySymptoms = allSymptomLogs
                .where((s) => !s.date.isBefore(entry.startDate) && !s.date.isAfter(endDate))
                .expand((s) => s.symptoms)
                .toSet()
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _showLogSheet(existing: entry),
                onLongPress: () => _deleteEntry(context, entry.id),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _pinkLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Text('🌸', style: TextStyle(fontSize: 18))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            DateFormat('MMMM d, y').format(entry.startDate),
                            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.stone900),
                          ),
                          if (entry.endDate != null)
                            Text(
                              'to ${DateFormat('MMM d').format(entry.endDate!)}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                            ),
                        ]),
                      ),
                      if (duration != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _pinkLight, borderRadius: BorderRadius.circular(8)),
                          child: Text('$duration days', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: _pink)),
                        ),
                    ]),
                    if (entrySymptoms.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, children: entrySymptoms.map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFDF4FF), borderRadius: BorderRadius.circular(8)),
                        child: Text(s, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFA855F7))),
                      )).toList()),
                    ],
                    // Flow level indicator
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Flow: ', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                      ...List.generate(3, (j) => Icon(
                        j < (entry.flowLevel.index + 1) ? Icons.circle : Icons.circle_outlined,
                        size: 10,
                        color: _pink,
                      )),
                      const SizedBox(width: 4),
                      Text(entry.flowLevel.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                    ]),
                    if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(entry.notes!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ]),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Insights Tab ───────────────────────────────────────────────────────────
  Widget _buildInsightsTab(List<PeriodEntry> entries, int? avgCycle, int? daysUntil) {
    // Average period duration
    final withEnd = entries.where((e) => e.endDate != null).toList();
    final avgDuration = withEnd.isNotEmpty
        ? (withEnd.fold<int>(0, (sum, e) => sum + e.endDate!.difference(e.startDate).inDays + 1) / withEnd.length).round()
        : null;

    // Flo F3: fertility timing predictions.
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    DateTime? fertileStart;
    DateTime? ovulationDate;
    if (avgCycle != null && entries.isNotEmpty) {
      final sorted = [...entries]..sort((a, b) => b.startDate.compareTo(a.startDate));
      final lastStart = DateTime(
        sorted.first.startDate.year,
        sorted.first.startDate.month,
        sorted.first.startDate.day,
      );
      final nextPeriodStart = lastStart.add(Duration(days: avgCycle));
      final nextPeriodStartDateOnly = DateTime(nextPeriodStart.year, nextPeriodStart.month, nextPeriodStart.day);
      ovulationDate = nextPeriodStartDateOnly.subtract(const Duration(days: 14));
      fertileStart = ovulationDate.subtract(const Duration(days: 5));
    }

    final daysUntilFertileStart = fertileStart?.difference(todayDateOnly).inDays;
    final daysUntilOvulation = ovulationDate?.difference(todayDateOnly).inDays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Row(children: [
          Expanded(child: StatCard(
            label: 'Avg cycle length',
            value: avgCycle != null ? '$avgCycle days' : '—',
            emoji: '📅',
            color: _pink,
          )),
          const SizedBox(width: 10),
          Expanded(child: StatCard(
            label: daysUntil != null && daysUntil >= 0 ? 'Days until next' : 'Days since due',
            value: daysUntil != null ? '${daysUntil.abs()}' : '—',
            emoji: '🌸',
            color: _pink,
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
          Expanded(child: StatCard(
            label: 'Avg period',
            value: avgDuration != null ? '$avgDuration days' : '—',
            emoji: '🩸',
            color: const Color(0xFFEF4444),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: StatCard(
            label: 'Fertile window starts',
            value: daysUntilFertileStart != null && daysUntilFertileStart >= 0 ? '${daysUntilFertileStart} days' : '—',
            emoji: '🌿',
            color: const Color(0xFF86EFAC),
          )),
          const SizedBox(width: 10),
          Expanded(child: StatCard(
            label: 'Ovulation',
            value: daysUntilOvulation != null && daysUntilOvulation >= 0 ? '${daysUntilOvulation} days' : '—',
            emoji: '⭐',
            color: const Color(0xFF16A34A),
          )),
        ]),
        const SizedBox(height: 16),
        _privacyNote(),
      ]),
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
                ), overflow: TextOverflow.ellipsis),
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

// ─── Calendar Widget ──────────────────────────────────────────────────────────

class _PeriodCalendar extends StatelessWidget {
  final DateTime currentMonth;
  final DateTime today;
  final Set<DateTime> periodDates;
  final Set<DateTime> symptomDates;
  final Set<DateTime> intimateDates;
  final Set<DateTime> fertileDates;
  final Set<DateTime> ovulationDates;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDayTap;

  const _PeriodCalendar({
    required this.currentMonth,
    required this.today,
    required this.periodDates,
    this.symptomDates = const {},
    this.intimateDates = const {},
    this.fertileDates = const {},
    this.ovulationDates = const {},
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
    final startWeekday = firstDayOfMonth.weekday % 7;

    const dayHeaders = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.stone100),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
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
              style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900),
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
              child: Text(d, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.5)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 8),
        // Day grid
        ...List.generate(
          ((startWeekday + daysInMonth + 6) ~/ 7),
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
                  final isFertile = fertileDates.contains(date);
                  final isOvulation = ovulationDates.contains(date);

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onDayTap(date),
                      child: Container(
                        height: 44,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isPeriod ? const Color(0xFFDC2626).withValues(alpha: 0.12) : null,
                          shape: BoxShape.circle,
                          border: isToday ? Border.all(color: _pinkDark, width: 2) : null,
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
                                    : isToday ? _pinkDark : AppTheme.stone700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            if (isPeriod || hasSymptom || hasIntimate || isFertile || isOvulation)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isPeriod) _dot(const Color(0xFFDC2626)),
                                  if (hasSymptom) _dot(const Color(0xFF8B5CF6)),
                                  if (hasIntimate) _dot(const Color(0xFF991B1B)),
                                  if (isFertile) _dot(const Color(0xFF86EFAC)),
                                  if (isOvulation)
                                    Icon(Icons.star, size: 10, color: const Color(0xFF16A34A)),
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
      ]),
    );
  }
}

// ─── Period Log Sheet ─────────────────────────────────────────────────────────

class _PeriodLogSheet extends StatefulWidget {
  final PeriodEntry? existing;
  final DateTime? initialDate;
  final Future<void> Function(PeriodEntry, String) onSave;
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
      _showSnack(context, 'End date cannot be before start date');
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
    await widget.onSave(entry, _mood);
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
                Expanded(child: _dateCard('START DATE', _startDate, () => _pickDate(true))),
                const SizedBox(width: 10),
                Expanded(child: _dateCard('END DATE', _endDate, () => _pickDate(false))),
              ]),
              if (_endDate != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => setState(() => _endDate = null), child: const Text('Clear end date', style: TextStyle(fontSize: 12))),
                ),
              const SizedBox(height: 20),

              // Flow level
              _sectionLabel('FLOW LEVEL'),
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
                          color: isSelected ? _pink.withValues(alpha: 0.15) : AppTheme.stone50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSelected ? _pink : AppTheme.stone200, width: isSelected ? 2 : 1),
                        ),
                        child: Center(child: Text(
                          level.name,
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: isSelected ? _pink : AppTheme.stone500),
                        )),
                      ),
                    ),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),

              // Symptoms
              _sectionLabel('SYMPTOMS'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _periodLogSymptoms.map((s) {
                final isSelected = _symptoms.contains(s);
                return GestureDetector(
                  onTap: () => setState(() { isSelected ? _symptoms.remove(s) : _symptoms.add(s); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? _pinkLight : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? _pink : AppTheme.stone200, width: isSelected ? 1.5 : 1),
                    ),
                    child: Text(s, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? _pink : AppTheme.stone600)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),

              // Mood
              _sectionLabel('MOOD'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _periodMoodOptions.map((emoji) {
                  final selected = _mood == emoji;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? _pinkLight : AppTheme.stone50,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? _pink : AppTheme.stone200),
                      ),
                      child: Text(emoji, style: TextStyle(fontSize: selected ? 28 : 22)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Privacy note
              _privacyNote(),
              const SizedBox(height: 16),

              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: _styledInput('Notes (optional)'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dateCard(String label, DateTime? date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.stone50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(
            date != null ? DateFormat('MMM d').format(date) : 'Ongoing',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: date != null ? _pink : AppTheme.stone400),
          ),
        ]),
      ),
    );
  }
}

// ─── Day Action Sheet ─────────────────────────────────────────────────────────

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
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 4),
          // Header row
          Row(children: [
            Expanded(
              child: Text(dayLabel, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.stone900)),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, size: 20, color: AppTheme.stone400),
            ),
          ]),
          const SizedBox(height: 20),

          // Period Started
          _actionButton(
            emoji: '🔥',
            label: 'Period Started',
            bgColor: _pinkDark,
            fgColor: Colors.white,
            onTap: onPeriodStarted,
          ),
          const SizedBox(height: 10),

          // Log Symptoms
          _actionButton(
            emoji: '😣',
            label: 'Log Symptoms',
            bgColor: _pinkLight,
            fgColor: _pinkDark,
            onTap: onLogSymptoms,
          ),
          const SizedBox(height: 10),

          // Log Intimate
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.favorite_border_rounded, size: 20),
              label: const Text('Log Intimate', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16)),
              onPressed: onLogIntimate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.stone50,
                foregroundColor: AppTheme.stone700,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppTheme.stone200),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required String emoji, required String label, required Color bgColor, required Color fgColor, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Text(emoji, style: const TextStyle(fontSize: 18)),
        label: Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: fgColor)),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// ─── Symptoms Sheet ───────────────────────────────────────────────────────────

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
      id: _uuid.v4(),
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Log Symptoms', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.stone900)),
                  Text(dayLabel, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: _pink)),
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
              _sectionLabel('SYMPTOMS'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _symptomOptions.map((s) {
                final isSelected = _selected.contains(s);
                return GestureDetector(
                  onTap: () => setState(() { isSelected ? _selected.remove(s) : _selected.add(s); }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? _pinkLight : AppTheme.stone50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? _pink : AppTheme.stone200, width: isSelected ? 1.5 : 1),
                    ),
                    child: Text(s, style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? _pink : AppTheme.stone600)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 20),

              // Mood
              _sectionLabel('MOOD'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: CycleMood.values.map((mood) {
                  final emoji = _moodEmojis[mood] ?? '😐';
                  final selected = _mood == mood;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = selected ? null : mood),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? _pinkLight : AppTheme.stone50,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? _pink : AppTheme.stone200),
                      ),
                      child: Text(emoji, style: TextStyle(fontSize: selected ? 26 : 20)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Pain level
              _sectionLabel('PAIN LEVEL (1–10)'),
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
                          color: selected ? _pink : (level <= (_painLevel ?? 0) ? _pinkLight : AppTheme.stone100),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text('$level', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppTheme.stone400)),
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
                decoration: _styledInput('Notes (optional)'),
              ),
              const SizedBox(height: 16),

              // Privacy note
              _privacyNote(),
            ]),
          ),
        ]),
      ),
    );
  }
}
