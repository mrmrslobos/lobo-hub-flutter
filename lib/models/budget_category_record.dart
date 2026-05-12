// lib/models/budget_category_record.dart
// ignore_for_file: constant_identifier_names
import '../services/field_encryption_service.dart';
import '_enums.dart';

class BudgetCategoryRecord {
  final String id;
  final String familyId;
  final String creatorId;
  final String name;
  final double limit;
  final String color;
  final Visibility visibility;
  /// Whether unused budget from prior periods carries into this month.
  final bool rolloverEnabled;
  /// Monthly vs weekly bucket interpretation for [limit].
  final BudgetLimitPeriod limitPeriod;

  const BudgetCategoryRecord({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.name,
    this.limit = 0,
    this.color = '#6366f1',
    this.visibility = Visibility.FAMILY,
    this.rolloverEnabled = false,
    this.limitPeriod = BudgetLimitPeriod.monthly,
  });

  factory BudgetCategoryRecord.fromJson(Map<String, dynamic> j) {
    final fid = j['family_id'] as String? ?? '';
    return BudgetCategoryRecord(
      id: j['id'] as String? ?? '',
      familyId: fid,
      creatorId: j['creator_id'] as String? ?? '',
      name: FieldEncryption.decryptField(j['name'] as String?, fid) ?? '',
      limit: FieldEncryption.decryptDouble(j['limit'], fid) ?? 0,
      color: j['color'] as String? ?? '#6366f1',
      visibility: visibilityFromString(j['visibility'] as String?),
      rolloverEnabled: (j['rollover_enabled'] ?? j['rolloverEnabled'] ?? false) as bool,
      limitPeriod: budgetLimitPeriodFromString(
        j['limit_period']?.toString() ?? j['limitPeriod']?.toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'name': FieldEncryption.encryptField(name, familyId),
    'limit': FieldEncryption.encryptNum(limit, familyId),
    'color': color,
    'visibility': visibility.name,
    'rollover_enabled': rolloverEnabled,
    'limit_period': limitPeriod.name,
  };

  BudgetCategoryRecord copyWith({
    String? id,
    String? familyId,
    String? creatorId,
    String? name,
    double? limit,
    String? color,
    Visibility? visibility,
    bool? rolloverEnabled,
    BudgetLimitPeriod? limitPeriod,
  }) =>
      BudgetCategoryRecord(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        creatorId: creatorId ?? this.creatorId,
        name: name ?? this.name,
        limit: limit ?? this.limit,
        color: color ?? this.color,
        visibility: visibility ?? this.visibility,
        rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
        limitPeriod: limitPeriod ?? this.limitPeriod,
      );
}
