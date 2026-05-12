// lib/models/daily_habit_completion.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class DailyHabitCompletion {
  final String id;
  final String habitId;
  final String userId;
  final DateTime date;
  final DateTime completedAt;

  DailyHabitCompletion({
    required this.id,
    required this.habitId,
    required this.userId,
    required this.date,
    DateTime? completedAt,
    DateTime? createdAt,
  }) : completedAt = completedAt ?? createdAt ?? DateTime.now();

  factory DailyHabitCompletion.fromJson(Map<String, dynamic> j) =>
      DailyHabitCompletion(
    id: j['id'] as String? ?? '',
    habitId: j['habit_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    date: parseDate(j['date']),
    completedAt: parseDate(j['completed_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'habit_id': habitId,
    'user_id': userId,
    'date': date.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
  };

  // Convenience alias - screens use createdAt
  DateTime get createdAt => completedAt;
}
