// lib/models/health_condition.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class HealthCondition {
  final String id;
  final String name;
  final DateTime? diagnosedDate;
  final String? notes;

  const HealthCondition({
    required this.id,
    required this.name,
    this.diagnosedDate,
    this.notes,
  });

  factory HealthCondition.fromJson(Map<String, dynamic> j) => HealthCondition(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    diagnosedDate: parseDateOpt(j['diagnosed_date']),
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'diagnosed_date': diagnosedDate?.toIso8601String(),
    'notes': notes,
  };
}
