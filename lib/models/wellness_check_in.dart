// lib/models/wellness_check_in.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class WellnessCheckIn {
  final String id;
  final String familyId;
  final String userId;
  /// One of: great, good, ok, low, rough
  final String mood;
  final String? note;
  final DateTime day;
  final DateTime createdAt;

  const WellnessCheckIn({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.mood,
    this.note,
    required this.day,
    required this.createdAt,
  });

  String get mergeKey => id;

  factory WellnessCheckIn.fromJson(Map<String, dynamic> j) => WellnessCheckIn(
        id: j['id'] as String? ?? '',
        familyId: j['family_id'] as String? ?? '',
        userId: j['user_id'] as String? ?? '',
        mood: j['mood'] as String? ?? 'ok',
        note: j['note'] as String?,
        day: parseDateOpt(j['day']) ?? DateTime.now(),
        createdAt: parseDate(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'mood': mood,
        'note': note,
        'day': DateTime(day.year, day.month, day.day).toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
