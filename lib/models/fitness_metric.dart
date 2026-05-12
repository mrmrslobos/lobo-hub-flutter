// lib/models/fitness_metric.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class FitnessMetric {
  final String id;
  final String userId;
  final String type;
  final double value;
  final DateTime date;
  final String? notes;

  const FitnessMetric({
    required this.id,
    required this.userId,
    required this.type,
    required this.value,
    required this.date,
    this.notes,
  });

  factory FitnessMetric.fromJson(Map<String, dynamic> j) => FitnessMetric(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    type: j['type'] as String? ?? '',
    value: ((j['value'] as num?) ?? 0).toDouble(),
    date: parseDate(j['date']),
    notes: j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'value': value,
    'date': date.toIso8601String(),
    'notes': notes,
  };
}
