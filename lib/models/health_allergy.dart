// lib/models/health_allergy.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';

class HealthAllergy {
  final String id;
  final String name;
  final AllergySeverity severity;
  final String? reaction;

  const HealthAllergy({
    required this.id,
    required this.name,
    this.severity = AllergySeverity.MILD,
    this.reaction,
  });

  factory HealthAllergy.fromJson(Map<String, dynamic> j) => HealthAllergy(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    severity: allergySeverityFromString(j['severity'] as String?),
    reaction: j['reaction'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'severity': severity.name,
    'reaction': reaction,
  };
}
