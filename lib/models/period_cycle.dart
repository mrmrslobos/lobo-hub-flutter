// lib/models/period_cycle.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';
import 'model_json_helpers.dart';

class PeriodCycle {
  final String id;
  final String userId;
  final String familyId;
  final DateTime startDate;
  final DateTime? endDate;
  final FlowLevel flowLevel;
  final String? notes;
  final DateTime createdAt;

  PeriodCycle({
    required this.id,
    required this.userId,
    required this.familyId,
    required this.startDate,
    this.endDate,
    this.flowLevel = FlowLevel.MEDIUM,
    this.notes,
    DateTime? createdAt,
    // Accept but ignore symptoms (stored separately in PeriodSymptomLog)
    List<String>? symptoms,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PeriodCycle.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return PeriodCycle(
      id: j['id'] as String? ?? '',
      userId: j['user_id'] as String? ?? '',
      familyId: fid,
      startDate: parseDate(j['start_date']),
      endDate: parseDateOpt(j['end_date']),
      flowLevel: flowLevelFromString(FieldEncryption.decryptField(j['flow_level'] as String?, fid)),
      notes: FieldEncryption.decryptField(j['notes'] as String?, fid),
      createdAt: parseDate(j['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'family_id': familyId,
    'start_date': startDate.toIso8601String(),
    'end_date': endDate?.toIso8601String(),
    'flow_level': FieldEncryption.encryptField(flowLevel.name, familyId),
    'notes': FieldEncryption.encryptField(notes, familyId),
    'created_at': createdAt.toIso8601String(),
  };

  // Convenience getter - symptoms come from PeriodSymptomLog but screens may access directly
  List<String> get symptoms => const [];

  PeriodCycle copyWith({
    String? id, String? userId, String? familyId,
    DateTime? startDate, DateTime? endDate, FlowLevel? flowLevel,
    String? notes, DateTime? createdAt,
  }) => PeriodCycle(
    id: id ?? this.id, userId: userId ?? this.userId,
    familyId: familyId ?? this.familyId,
    startDate: startDate ?? this.startDate, endDate: endDate ?? this.endDate,
    flowLevel: flowLevel ?? this.flowLevel, notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
}
