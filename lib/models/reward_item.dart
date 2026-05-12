// lib/models/reward_item.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class RewardItem {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String? description;
  final int cost;
  final String? icon;
  final bool active;
  final DateTime createdAt;

  const RewardItem({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    this.description,
    this.cost = 0,
    this.icon,
    this.active = true,
    required this.createdAt,
  });

  factory RewardItem.fromJson(Map<String, dynamic> j) => RewardItem(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    description: j['description'] as String?,
    cost: ((j['cost'] as num?) ?? 0).toInt(),
    icon: j['icon'] as String?,
    active: (j['active'] ?? true) as bool,
    createdAt: parseDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'cost': cost,
    'icon': icon,
    'active': active,
    'created_at': createdAt.toIso8601String(),
  };
}
