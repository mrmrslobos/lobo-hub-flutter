// lib/models/pantry_item.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class PantryItem {
  final String id;
  final String familyId;
  final String name;
  final String? quantity;
  final String? unit;
  final DateTime updatedAt;

  const PantryItem({
    required this.id,
    required this.familyId,
    required this.name,
    this.quantity,
    this.unit,
    required this.updatedAt,
  });

  String get mergeKey => id;

  factory PantryItem.fromJson(Map<String, dynamic> j) => PantryItem(
        id: j['id'] as String? ?? '',
        familyId: j['family_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        quantity: j['quantity'] as String?,
        unit: j['unit'] as String?,
        updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'updated_at': updatedAt.toIso8601String(),
      };

  PantryItem copyWith({
    String? id,
    String? familyId,
    String? name,
    String? quantity,
    String? unit,
    DateTime? updatedAt,
  }) =>
      PantryItem(
        id: id ?? this.id,
        familyId: familyId ?? this.familyId,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
