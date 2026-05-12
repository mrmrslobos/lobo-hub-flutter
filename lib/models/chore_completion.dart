// lib/models/chore_completion.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class ChoreCompletion {
  final String id;
  final String choreId;
  final String userId;
  final String familyId;
  final DateTime date;
  final DateTime completedAt;
  final ApprovalStatus approvalStatus;
  final String? approvedBy;
  final DateTime? approvedAt;

  const ChoreCompletion({
    required this.id,
    required this.choreId,
    required this.userId,
    required this.familyId,
    required this.date,
    required this.completedAt,
    this.approvalStatus = ApprovalStatus.PENDING,
    this.approvedBy,
    this.approvedAt,
  });

  factory ChoreCompletion.fromJson(Map<String, dynamic> j) => ChoreCompletion(
    id: j['id'] as String? ?? '',
    choreId: j['chore_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    date: parseDate(j['date']),
    completedAt: parseDate(j['completed_at']),
    approvalStatus: approvalStatusFromString(j['approval_status'] as String?),
    approvedBy: j['approved_by'] as String?,
    approvedAt: parseDateOpt(j['approved_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'chore_id': choreId,
    'user_id': userId,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
    'approval_status': approvalStatus.name,
    'approved_by': approvedBy,
    'approved_at': approvedAt?.toIso8601String(),
  };
}
