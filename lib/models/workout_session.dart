// lib/models/workout_session.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import 'model_json_helpers.dart';

class WorkoutSession {
  final String id;
  final String familyId;
  final String userId;
  final String title;
  final DateTime date;
  final int durationMinutes;
  final String? notes;
  /// When this session was written to Apple Health / Health Connect (if enabled).
  final DateTime? healthSyncedAt;
  final DateTime createdAt;

  const WorkoutSession({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.title,
    required this.date,
    this.durationMinutes = 0,
    this.notes,
    this.healthSyncedAt,
    required this.createdAt,
  });

  factory WorkoutSession.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return WorkoutSession(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      title: FieldEncryption.decryptField(j['title'] as String?, fid) ?? '',
      date: parseDate(j['date']),
      durationMinutes: ((j['duration_minutes'] as num?) ?? 0).toInt(),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      healthSyncedAt: parseDateOpt(j['health_synced_at']),
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'title': FieldEncryption.encryptField(title, familyId) ?? title,
        'date': date.toIso8601String(),
        'duration_minutes': durationMinutes,
        'notes': FieldEncryption.encryptField(notes, familyId),
        if (healthSyncedAt != null)
          'health_synced_at': healthSyncedAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  WorkoutSession copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? title,
    DateTime? date,
    int? durationMinutes,
    String? notes,
    DateTime? healthSyncedAt,
    DateTime? createdAt,
  }) =>
      WorkoutSession(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        date: date ?? this.date,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        notes: notes ?? this.notes,
        healthSyncedAt: healthSyncedAt ?? this.healthSyncedAt,
        createdAt: createdAt ?? this.createdAt,
      );
}
