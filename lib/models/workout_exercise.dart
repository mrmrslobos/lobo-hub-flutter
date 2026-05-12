// lib/models/workout_exercise.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import 'model_json_helpers.dart';

class WorkoutExercise {
  final String id;
  final String familyId;
  final String userId;
  final String sessionId;
  final String exerciseName;
  final int order;
  final int restSeconds;
  final String? notes;
  /// Step-by-step how-to (AI or user). Prefer text over video for cost.
  final String? techniqueNotes;
  /// Optional link to a free demo (e.g. YouTube / ExRx).
  final String? referenceUrl;
  /// Illustration URL (e.g. wger.de) — not encrypted (public CDN).
  final String? techniqueImageUrl;
  /// ExerciseDB exercise id when [techniqueImageUrl] is their GIF URL.
  final String? exerciseDbId;
  final DateTime createdAt;

  const WorkoutExercise({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.sessionId,
    required this.exerciseName,
    this.order = 0,
    this.restSeconds = 60,
    this.notes,
    this.techniqueNotes,
    this.referenceUrl,
    this.techniqueImageUrl,
    this.exerciseDbId,
    required this.createdAt,
  });

  factory WorkoutExercise.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return WorkoutExercise(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      sessionId: j['session_id'] as String? ?? '',
      exerciseName:
          FieldEncryption.decryptField(j['exercise_name'] as String?, fid) ??
              '',
      order: ((j['order'] as num?) ?? 0).toInt(),
      restSeconds: ((j['rest_seconds'] as num?) ?? 60).toInt(),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      techniqueNotes:
          FieldEncryption.decryptField(j['technique_notes'] as String?, fid),
      referenceUrl:
          FieldEncryption.decryptField(j['reference_url'] as String?, fid),
      techniqueImageUrl: j['technique_image_url'] as String?,
      exerciseDbId: j['exercise_db_id'] as String?,
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'session_id': sessionId,
        'exercise_name': FieldEncryption.encryptField(exerciseName, familyId) ??
            exerciseName,
        'order': order,
        'rest_seconds': restSeconds,
        'notes': FieldEncryption.encryptField(notes, familyId),
        'technique_notes':
            FieldEncryption.encryptField(techniqueNotes, familyId),
        'reference_url': FieldEncryption.encryptField(referenceUrl, familyId),
        if (techniqueImageUrl != null) 'technique_image_url': techniqueImageUrl,
        if (exerciseDbId != null) 'exercise_db_id': exerciseDbId,
        'created_at': createdAt.toIso8601String(),
      };

  WorkoutExercise copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? sessionId,
    String? exerciseName,
    int? order,
    int? restSeconds,
    String? notes,
    String? techniqueNotes,
    String? referenceUrl,
    String? techniqueImageUrl,
    String? exerciseDbId,
    DateTime? createdAt,
  }) =>
      WorkoutExercise(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        sessionId: sessionId ?? this.sessionId,
        exerciseName: exerciseName ?? this.exerciseName,
        order: order ?? this.order,
        restSeconds: restSeconds ?? this.restSeconds,
        notes: notes ?? this.notes,
        techniqueNotes: techniqueNotes ?? this.techniqueNotes,
        referenceUrl: referenceUrl ?? this.referenceUrl,
        techniqueImageUrl: techniqueImageUrl ?? this.techniqueImageUrl,
        exerciseDbId: exerciseDbId ?? this.exerciseDbId,
        createdAt: createdAt ?? this.createdAt,
      );
}
