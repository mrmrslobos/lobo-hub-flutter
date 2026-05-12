// lib/models/reward_redemption.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';

class RewardRedemption {
  final String id;
  final String familyId;
  final String userId;
  final String rewardId;
  final String rewardTitle;
  final int amount;
  final RedemptionStatus status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolvedNote;

  const RewardRedemption({
    required this.id,
    required this.familyId,
    required this.userId,
    required this.rewardId,
    required this.rewardTitle,
    this.amount = 0,
    this.status = RedemptionStatus.PENDING,
    required this.requestedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolvedNote,
  });

  factory RewardRedemption.fromJson(Map<String, dynamic> j) => RewardRedemption(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    rewardId: j['reward_id'] as String? ?? '',
    rewardTitle: j['reward_title'] as String? ?? '',
    amount: ((j['amount'] as num?) ?? 0).toInt(),
    status: redemptionStatusFromString(j['status'] as String?),
    requestedAt: parseDate(j['requested_at']),
    resolvedAt: parseDateOpt(j['resolved_at']),
    resolvedBy: j['resolved_by'] as String?,
    resolvedNote: j['resolved_note'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'user_id': userId,
    'reward_id': rewardId,
    'reward_title': rewardTitle,
    'amount': amount,
    'status': status.name,
    'requested_at': requestedAt.toIso8601String(),
    'resolved_at': resolvedAt?.toIso8601String(),
    'resolved_by': resolvedBy,
    'resolved_note': resolvedNote,
  };

  RewardRedemption copyWith({
    String? id,
    String? familyId,
    String? userId,
    String? rewardId,
    String? rewardTitle,
    int? amount,
    RedemptionStatus? status,
    DateTime? requestedAt,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolvedNote,
  }) => RewardRedemption(
    id: id ?? this.id,
    familyId: familyId ?? this.familyId,
    userId: userId ?? this.userId,
    rewardId: rewardId ?? this.rewardId,
    rewardTitle: rewardTitle ?? this.rewardTitle,
    amount: amount ?? this.amount,
    status: status ?? this.status,
    requestedAt: requestedAt ?? this.requestedAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    resolvedBy: resolvedBy ?? this.resolvedBy,
    resolvedNote: resolvedNote ?? this.resolvedNote,
  );
}
