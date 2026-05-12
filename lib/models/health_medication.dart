// lib/models/health_medication.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class HealthMedication {
  final String id;
  final String name;
  final String? dose;
  final String? frequency;
  final DateTime? startDate;

  const HealthMedication({
    required this.id,
    required this.name,
    this.dose,
    this.frequency,
    this.startDate,
  });

  factory HealthMedication.fromJson(Map<String, dynamic> j) => HealthMedication(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    dose: j['dose'] as String?,
    frequency: j['frequency'] as String?,
    startDate: parseDateOpt(j['start_date']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dose': dose,
    'frequency': frequency,
    'start_date': startDate?.toIso8601String(),
  };
}
