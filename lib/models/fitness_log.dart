// lib/models/fitness_log.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import 'model_json_helpers.dart';

class FitnessLog {
  final String id;
  final String familyId;
  final String userId;
  final String activity;
  final int durationMinutes;
  final int? caloriesBurned;
  final String? notes;
  final DateTime date;

  const FitnessLog({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.activity,
    this.durationMinutes = 0,
    this.caloriesBurned,
    this.notes,
    required this.date,
  });

  factory FitnessLog.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return FitnessLog(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      activity: FieldEncryption.decryptField(j['activity'] as String?, fid) ?? '',
      durationMinutes: FieldEncryption.decryptInt(j['duration_minutes'], fid) ?? 0,
      caloriesBurned: FieldEncryption.decryptInt(j['calories_burned'], fid),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      date: parseDate(j['date']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'activity': FieldEncryption.encryptField(activity, familyId) ?? activity,
    'duration_minutes': FieldEncryption.encryptNum(durationMinutes, familyId) ?? durationMinutes.toString(),
    'calories_burned': FieldEncryption.encryptNum(caloriesBurned, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'date': date.toIso8601String(),
  };

  FitnessLog copyWith({
    String? id, String? familyId, String? userId, String? activity,
    int? durationMinutes, int? caloriesBurned, String? notes, DateTime? date,
  }) => FitnessLog(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId, activity: activity ?? this.activity,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    caloriesBurned: caloriesBurned ?? this.caloriesBurned,
    notes: notes ?? this.notes, date: date ?? this.date,
  );
}
