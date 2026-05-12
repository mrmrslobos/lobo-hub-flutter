// lib/models/reward.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class Reward {
  final String id;
  final String familyId;
  final String title;
  final int pointCost;
  final String? description;
  final List<String> redeemedBy;

  const Reward({
    required this.id,
    required this.familyId,
    required this.title,
    this.pointCost = 0,
    this.description,
    this.redeemedBy = const [],
  });

  factory Reward.fromJson(Map<String, dynamic> j) => Reward(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    pointCost: ((j['point_cost'] ?? j['cost']) as int?) ?? 0,
    description: j['description'] as String?,
    redeemedBy: strList(j['redeemed_by']),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'family_id': familyId, 'title': title,
    'point_cost': pointCost, 'description': description, 'redeemed_by': redeemedBy,
  };

  Reward copyWith({
    String? id, String? familyId, String? title, int? pointCost,
    String? description, List<String>? redeemedBy,
  }) => Reward(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    title: title ?? this.title, pointCost: pointCost ?? this.pointCost,
    description: description ?? this.description, redeemedBy: redeemedBy ?? this.redeemedBy,
  );
}
