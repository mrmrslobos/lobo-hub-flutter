// lib/models/daily_habit.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class DailyHabit {
  final String id;
  final String userId;
  final String? familyId;
  final String label;
  final String? icon;
  final String? color;
  final String? description;
  final bool isShared;
  final String? frequency;
  final num? targetValue;
  final String? targetUnit;
  final DateTime createdAt;
  final int order;

  DailyHabit({
    required this.id,
    required this.userId,
    this.familyId,
    String? label,
    String? title,
    String? icon,
    String? emoji,
    this.color,
    this.description,
    this.isShared = false,
    this.frequency,
    this.targetValue,
    this.targetUnit,
    DateTime? createdAt,
    this.order = 0,
  }) : label = label ?? title ?? '',
       icon = icon ?? emoji,
       createdAt = createdAt ?? DateTime.now();

  // Convenience aliases
  String get title => label;
  String get emoji => icon ?? '';

  DailyHabit copyWith({
    String? id, String? userId, String? familyId, String? label, String? icon,
    String? color, String? description, bool? isShared, String? frequency,
    num? targetValue, String? targetUnit, DateTime? createdAt, int? order,
  }) => DailyHabit(
    id: id ?? this.id, userId: userId ?? this.userId, familyId: familyId ?? this.familyId,
    label: label ?? this.label, icon: icon ?? this.icon, color: color ?? this.color,
    description: description ?? this.description, isShared: isShared ?? this.isShared,
    frequency: frequency ?? this.frequency, targetValue: targetValue ?? this.targetValue,
    targetUnit: targetUnit ?? this.targetUnit, createdAt: createdAt ?? this.createdAt,
    order: order ?? this.order,
  );

  factory DailyHabit.fromJson(Map<String, dynamic> j) => DailyHabit(
    id: j['id'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    familyId: j['family_id'] as String?,
    label: j['label'] as String? ?? '',
    icon: j['icon'] as String?,
    color: j['color'] as String?,
    description: j['description'] as String?,
    isShared: (j['is_shared'] ?? false) as bool,
    frequency: j['frequency'] as String?,
    targetValue: j['target_value'] as num?,
    targetUnit: j['target_unit'] as String?,
    createdAt: parseDate(j['created_at']),
    order: (j['order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'user_id': userId, 'family_id': familyId,
    'label': label, 'icon': icon ?? '', 'color': color ?? '#6366f1',
    'description': description, 'is_shared': isShared,
    'frequency': frequency, 'target_value': targetValue, 'target_unit': targetUnit,
    'created_at': createdAt.toIso8601String(), 'order': order,
  };
}
