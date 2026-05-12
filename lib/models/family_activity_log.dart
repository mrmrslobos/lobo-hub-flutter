// lib/models/family_activity_log.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class FamilyActivityLog {
  final String id;
  final String familyId;
  final String actorUserId;
  final String action;
  final String? detail;
  final String? relatedUserId;
  final DateTime createdAt;

  const FamilyActivityLog({
    required this.id,
    required this.familyId,
    required this.actorUserId,
    required this.action,
    this.detail,
    this.relatedUserId,
    required this.createdAt,
  });

  String get mergeKey => id;

  factory FamilyActivityLog.fromJson(Map<String, dynamic> j) =>
      FamilyActivityLog(
        id: j['id'] as String? ?? '',
        familyId: j['family_id'] as String? ?? '',
        actorUserId: j['actor_user_id'] as String? ?? '',
        action: j['action'] as String? ?? '',
        detail: j['detail'] as String?,
        relatedUserId: j['related_user_id'] as String?,
        createdAt: parseDate(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'actor_user_id': actorUserId,
        'action': action,
        'detail': detail,
        'related_user_id': relatedUserId,
        'created_at': createdAt.toIso8601String(),
      };
}
