// lib/models/exercise_pr.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import 'model_json_helpers.dart';

class ExercisePR {
  final String id;
  final String userId;
  final String familyId;
  final String exerciseKey;
  final double? bestVolume;
  final String? bestWeight;
  final int? bestReps;
  final String? sessionId;
  final String? exerciseId;
  final DateTime achievedAt;
  final DateTime createdAt;

  const ExercisePR({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.exerciseKey,
    this.bestVolume,
    this.bestWeight,
    this.bestReps,
    this.sessionId,
    this.exerciseId,
    required this.achievedAt,
    required this.createdAt,
  });

  String get mergeKey => id;

  factory ExercisePR.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return ExercisePR(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: fid,
      exerciseKey: j['exercise_key'] as String? ?? '',
      bestVolume: (j['best_volume'] as num?)?.toDouble(),
      bestWeight: FieldEncryption.decryptField(j['best_weight'] as String?, fid),
      bestReps: (j['best_reps'] as num?)?.toInt(),
      sessionId: j['session_id'] as String?,
      exerciseId: j['exercise_id'] as String?,
      achievedAt: parseDate(j['achieved_at']),
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'family_id': familyId,
        'exercise_key': exerciseKey,
        'best_volume': bestVolume,
        'best_weight': FieldEncryption.encryptField(bestWeight, familyId),
        'best_reps': bestReps,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'achieved_at': achievedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  ExercisePR copyWith({
    String? id,
    String? userId,
    String? familyId,
    String? exerciseKey,
    double? bestVolume,
    String? bestWeight,
    int? bestReps,
    String? sessionId,
    String? exerciseId,
    DateTime? achievedAt,
    DateTime? createdAt,
  }) =>
      ExercisePR(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        familyId: familyId ?? this.familyId,
        exerciseKey: exerciseKey ?? this.exerciseKey,
        bestVolume: bestVolume ?? this.bestVolume,
        bestWeight: bestWeight ?? this.bestWeight,
        bestReps: bestReps ?? this.bestReps,
        sessionId: sessionId ?? this.sessionId,
        exerciseId: exerciseId ?? this.exerciseId,
        achievedAt: achievedAt ?? this.achievedAt,
        createdAt: createdAt ?? this.createdAt,
      );
}
