// lib/models/health_immunization.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class HealthImmunization {
  final String id;
  final String name;
  final DateTime? date;
  final DateTime? nextDue;

  const HealthImmunization({
    required this.id,
    required this.name,
    this.date,
    this.nextDue,
  });

  factory HealthImmunization.fromJson(Map<String, dynamic> j) => HealthImmunization(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    date: parseDateOpt(j['date']),
    nextDue: parseDateOpt(j['next_due']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'date': date?.toIso8601String(),
    'next_due': nextDue?.toIso8601String(),
  };
}
