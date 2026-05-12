// lib/models/reading_plan_progress.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class ReadingPlanProgress {
  final String id;
  final String planId;
  final String userId;
  final String familyId;
  final List<int> completedDayNumbers;
  final int currentStreak;
  final int longestStreak;
  final DateTime startedAt;
  final DateTime? lastCompletedAt;

  const ReadingPlanProgress({
    required this.id,
    required this.planId,
    required this.userId,
    required this.familyId,
    this.completedDayNumbers = const [],
    this.currentStreak = 0,
    this.longestStreak = 0,
    required this.startedAt,
    this.lastCompletedAt,
  });

  static String stableId(String planId, String userId) => '${planId}_$userId';

  factory ReadingPlanProgress.fromJson(Map<String, dynamic> j) {
    final raw = j['completed_days'] ?? j['completedDays'];
    final days = <int>{};
    if (raw is List) {
      for (final x in raw) {
        if (x is int) days.add(x);
        else if (x is num) days.add(x.toInt());
      }
    }
    final sorted = days.toList()..sort();

    return ReadingPlanProgress(
      id: j['id'] as String? ?? '',
      planId: j['plan_id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: j['family_id'] as String? ?? '',
      completedDayNumbers: sorted,
      currentStreak: (j['current_streak'] as num?)?.toInt() ??
          (j['currentStreak'] as num?)?.toInt() ??
          0,
      longestStreak: (j['longest_streak'] as num?)?.toInt() ??
          (j['longestStreak'] as num?)?.toInt() ??
          0,
      startedAt:
          parseDateOpt(j['started_at']) ?? parseDateOpt(j['startedAt']) ?? DateTime.now(),
      lastCompletedAt: parseDateOpt(j['last_completed_at']) ??
          parseDateOpt(j['lastCompletedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'plan_id': planId,
        'user_id': userId,
        'family_id': familyId,
        'completed_days': completedDayNumbers,
        'current_streak': currentStreak,
        'longest_streak': longestStreak,
        'started_at': startedAt.toIso8601String(),
        if (lastCompletedAt != null)
          'last_completed_at': lastCompletedAt!.toIso8601String(),
      };

  ReadingPlanProgress copyWith({
    String? id,
    String? planId,
    String? userId,
    String? familyId,
    List<int>? completedDayNumbers,
    int? currentStreak,
    int? longestStreak,
    DateTime? startedAt,
    DateTime? lastCompletedAt,
  }) =>
      ReadingPlanProgress(
        id: id ?? this.id,
        planId: planId ?? this.planId,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        completedDayNumbers: completedDayNumbers ?? this.completedDayNumbers,
        currentStreak: currentStreak ?? this.currentStreak,
        longestStreak: longestStreak ?? this.longestStreak,
        startedAt: startedAt ?? this.startedAt,
        lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      );
}
