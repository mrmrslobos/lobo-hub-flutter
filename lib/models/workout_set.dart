// lib/models/workout_set.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import 'model_json_helpers.dart';

class WorkoutSet {
  final String id;
  final String familyId;
  final String userId;
  final String exerciseId;
  final int setNumber;
  final String reps; // stored as encrypted text in DB
  final String? weight; // stored as encrypted text in DB
  final bool completed;
  final String? notes;
  final DateTime createdAt;

  const WorkoutSet({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    this.weight,
    this.completed = false,
    this.notes,
    required this.createdAt,
  });

  factory WorkoutSet.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return WorkoutSet(
      id: j['id'] as String? ?? '',
      familyId: fid,
      userId: j['user_id'] as String? ?? '',
      exerciseId: j['exercise_id'] as String? ?? '',
      setNumber: ((j['set_number'] as num?) ?? 0).toInt(),
      reps: FieldEncryption.decryptField(j['reps'] as String?, fid) ?? '',
      weight: FieldEncryption.decryptField(j['weight'] as String?, fid),
      completed: coerceBool(j['completed']),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'user_id': userId,
        'exercise_id': exerciseId,
        'set_number': setNumber,
        'reps': FieldEncryption.encryptField(reps, familyId) ?? reps,
        'weight': FieldEncryption.encryptField(weight, familyId),
        'completed': completed,
        'notes': FieldEncryption.encryptField(notes, familyId),
        'created_at': createdAt.toIso8601String(),
      };

  WorkoutSet copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? exerciseId,
    int? setNumber,
    String? reps,
    String? weight,
    bool? completed,
    String? notes,
    DateTime? createdAt,
  }) =>
      WorkoutSet(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        userId: userId ?? this.userId,
        exerciseId: exerciseId ?? this.exerciseId,
        setNumber: setNumber ?? this.setNumber,
        reps: reps ?? this.reps,
        weight: weight ?? this.weight,
        completed: completed ?? this.completed,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
      );
}
