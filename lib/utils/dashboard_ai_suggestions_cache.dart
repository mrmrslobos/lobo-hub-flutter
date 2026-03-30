// Cached dashboard AI suggestions: context hash, daily quota, persistence.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Max Gemini calls per user per family per calendar day (local date).
const int kDashboardAiSuggestionsMaxGenerationsPerDay = 3;

String _todayKeyLocal() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Metrics that drive the AI prompt — keep in sync with dashboard_screen context string.
String dashboardSuggestionsContextFingerprint({
  required AppDB db,
  required String familyId,
  required String userId,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final tasksDue = db.tasks
      .where((t) =>
          t.familyId == familyId &&
          !t.completed &&
          t.dueDate != null &&
          _isSameDay(t.dueDate!, today))
      .length;
  final overdue = db.tasks
      .where((t) =>
          t.familyId == familyId &&
          !t.completed &&
          t.dueDate != null &&
          t.dueDate!.isBefore(today))
      .length;
  final chores = db.chores.where((c) => c.familyId == familyId).length;
  final meals = db.mealPlans
      .where((m) => m.familyId == familyId && _isSameDay(m.date, today))
      .toList();
  final mealsPlanned = meals.map((m) => m.mealType).toSet();
  final upcomingEvents = db.events
      .where((e) =>
          e.familyId == familyId &&
          !e.startDate.isBefore(today) &&
          e.startDate.isBefore(today.add(const Duration(days: 3))))
      .toList();
  final memberIds = db.familyMembers
      .where((m) => m.familyId == familyId)
      .map((m) => m.userId)
      .toSet();
  bool habitInHome(DailyHabit h) {
    if (h.familyId == familyId) return true;
    if (h.familyId == null && memberIds.contains(h.userId)) return true;
    return false;
  }

  final familyHabits =
      db.dailyHabits.where(habitInHome).map((h) => h.id).toSet();
  final habits = familyHabits.length;
  final habitsCompleted = db.dailyHabitCompletions
      .where((c) =>
          c.userId == userId &&
          familyHabits.contains(c.habitId) &&
          _isSameDay(c.date, today))
      .length;
  final prayer = db.prayerWall.where((p) => p.familyId == familyId).length;
  final lists = db.lists.where((l) => l.familyId == familyId).length;

  return [
    familyId,
    userId,
    tasksDue,
    overdue,
    chores,
    mealsPlanned.join('|'),
    upcomingEvents.map((e) => e.id).join(','),
    habits,
    habitsCompleted,
    prayer,
    lists,
  ].join('::');
}

String hashDashboardContext(String fingerprint) {
  final bytes = utf8.encode(fingerprint);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

String _prefsKeyCache(String userId, String familyId) =>
    'lobohub_dash_ai_sug_v1_${userId}_$familyId';

String _prefsKeyQuota(String userId, String familyId) =>
    'lobohub_dash_ai_quota_v1_${userId}_$familyId';

class DashboardAiSuggestionRecord {
  final String icon;
  final String title;
  final String description;
  final String? reasoning;
  final String? timeEstimate;
  final String? route;

  const DashboardAiSuggestionRecord({
    required this.icon,
    required this.title,
    required this.description,
    this.reasoning,
    this.timeEstimate,
    this.route,
  });

  Map<String, dynamic> toJson() => {
        'icon': icon,
        'title': title,
        'description': description,
        'reasoning': reasoning,
        'timeEstimate': timeEstimate,
        'route': route,
      };

  factory DashboardAiSuggestionRecord.fromJson(Map<String, dynamic> j) =>
      DashboardAiSuggestionRecord(
        icon: j['icon'] as String? ?? 'task',
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        reasoning: j['reasoning'] as String?,
        timeEstimate: j['timeEstimate'] as String?,
        route: j['route'] as String?,
      );
}

class DashboardAiSuggestionsCachePayload {
  final List<DashboardAiSuggestionRecord> suggestions;
  final String contextHash;
  final String generatedAtIso;
  /// Bits 0..2 set when user marks suggestion 0..2 as done.
  final int completedMask;

  const DashboardAiSuggestionsCachePayload({
    required this.suggestions,
    required this.contextHash,
    required this.generatedAtIso,
    this.completedMask = 0,
  });

  bool get allCompleted {
    if (suggestions.isEmpty) return false;
    final need = (1 << suggestions.length) - 1;
    return completedMask == need;
  }

  Map<String, dynamic> toJson() => {
        'suggestions': suggestions.map((e) => e.toJson()).toList(),
        'contextHash': contextHash,
        'generatedAt': generatedAtIso,
        'completedMask': completedMask,
      };

  factory DashboardAiSuggestionsCachePayload.fromJson(Map<String, dynamic> j) {
    final raw = j['suggestions'];
    final list = raw is List
        ? raw
            .map((e) => DashboardAiSuggestionRecord.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList()
        : <DashboardAiSuggestionRecord>[];
    return DashboardAiSuggestionsCachePayload(
      suggestions: list,
      contextHash: j['contextHash'] as String? ?? '',
      generatedAtIso: j['generatedAt'] as String? ?? '',
      completedMask: (j['completedMask'] as num?)?.toInt() ?? 0,
    );
  }

  DashboardAiSuggestionsCachePayload copyWith({
    List<DashboardAiSuggestionRecord>? suggestions,
    String? contextHash,
    String? generatedAtIso,
    int? completedMask,
  }) =>
      DashboardAiSuggestionsCachePayload(
        suggestions: suggestions ?? this.suggestions,
        contextHash: contextHash ?? this.contextHash,
        generatedAtIso: generatedAtIso ?? this.generatedAtIso,
        completedMask: completedMask ?? this.completedMask,
      );
}

Future<DashboardAiSuggestionsCachePayload?> loadDashboardAiCache(
  String userId,
  String familyId,
) async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_prefsKeyCache(userId, familyId));
  if (s == null || s.isEmpty) return null;
  try {
    return DashboardAiSuggestionsCachePayload.fromJson(
      Map<String, dynamic>.from(jsonDecode(s) as Map),
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveDashboardAiCache(
  String userId,
  String familyId,
  DashboardAiSuggestionsCachePayload payload,
) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(
    _prefsKeyCache(userId, familyId),
    jsonEncode(payload.toJson()),
  );
}

Future<void> clearDashboardAiCache(String userId, String familyId) async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_prefsKeyCache(userId, familyId));
}

Future<({int count, String dateKey})> _readQuota(
    String userId, String familyId) async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_prefsKeyQuota(userId, familyId));
  final today = _todayKeyLocal();
  if (s == null || s.isEmpty) return (count: 0, dateKey: today);
  try {
    final m = Map<String, dynamic>.from(jsonDecode(s) as Map);
    final d = m['date'] as String? ?? '';
    final c = (m['count'] as num?)?.toInt() ?? 0;
    if (d != today) return (count: 0, dateKey: today);
    return (count: c, dateKey: d);
  } catch (_) {
    return (count: 0, dateKey: today);
  }
}

/// Whether another Gemini call is allowed today for this user/family.
Future<bool> canGenerateDashboardAiSuggestions(
  String userId,
  String familyId,
) async {
  final q = await _readQuota(userId, familyId);
  return q.count < kDashboardAiSuggestionsMaxGenerationsPerDay;
}

Future<void> recordDashboardAiGeneration(
  String userId,
  String familyId,
) async {
  final p = await SharedPreferences.getInstance();
  final today = _todayKeyLocal();
  final q = await _readQuota(userId, familyId);
  final next = q.dateKey == today ? q.count + 1 : 1;
  await p.setString(
    _prefsKeyQuota(userId, familyId),
    jsonEncode({'date': today, 'count': next}),
  );
}
