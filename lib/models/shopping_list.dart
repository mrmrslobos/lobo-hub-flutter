// lib/models/shopping_list.dart
// ignore_for_file: constant_identifier_names
import '_enums.dart';
import 'model_json_helpers.dart';
import 'list_item.dart';

class ShoppingList {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final List<ListItem> items;
  final ListCategory category;
  final Visibility visibility;
  final List<String> sharedWith;
  final DateTime updatedAt;

  ShoppingList({
    required this.id,
    required this.familyId,
    String? creatorId,
    String? createdBy,
    String? title,
    String? name,
    this.items = const [],
    this.category = ListCategory.GROCERY,
    this.visibility = Visibility.FAMILY,
    this.sharedWith = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : updatedAt = updatedAt ?? DateTime.now(),
        creatorId = creatorId ?? createdBy ?? '',
       title = title ?? name ?? '';

  factory ShoppingList.fromJson(Map<String, dynamic> j) => ShoppingList(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    creatorId: j['creator_id'] as String? ?? '',
    title: j['title'] as String? ?? '',
    items: parseList(j['items'], ListItem.fromJson),
    category: listCategoryFromString(j['category'] as String?),
    visibility: visibilityFromString(j['visibility'] as String?),
    sharedWith: strList(j['shared_with']),
    updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'creator_id': creatorId,
    'title': title,
    'items': items.map((e) => e.toJson()).toList(),
    'category': category.name,
    'visibility': visibility.name,
    'updated_at': updatedAt.toIso8601String(),
  };

  // Convenience getters
  String get name => title;

  ShoppingList copyWith({
    String? id, String? familyId, String? creatorId, String? title,
    List<ListItem>? items, ListCategory? category, Visibility? visibility,
    List<String>? sharedWith, DateTime? updatedAt,
  }) {
    final anyField = id != null ||
        familyId != null ||
        creatorId != null ||
        title != null ||
        items != null ||
        category != null ||
        visibility != null ||
        sharedWith != null;
    return ShoppingList(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      creatorId: creatorId ?? this.creatorId,
      title: title ?? this.title,
      items: items ?? this.items,
      category: category ?? this.category,
      visibility: visibility ?? this.visibility,
      sharedWith: sharedWith ?? this.sharedWith,
      updatedAt: updatedAt ?? (anyField ? DateTime.now() : this.updatedAt),
    );
  }
}
