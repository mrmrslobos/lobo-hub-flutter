// lib/models/list_item.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class ListItem {
  final String id;
  final String text;
  final String? quantity;
  final bool checked;
  final String? notes;
  final String? aiCategory;

  ListItem({
    required this.id,
    String? text,
    String? name,
    String? quantity,
    dynamic rawQuantity,
    this.checked = false,
    this.notes,
    this.aiCategory,
  }) : text = text ?? name ?? '',
       quantity = quantity ?? rawQuantity?.toString();

  factory ListItem.fromJson(Map<String, dynamic> j) => ListItem(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    quantity: j['quantity'] as String?,
    checked: coerceBool(j['checked']),
    notes: j['notes'] as String?,
    aiCategory: j['ai_category'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'quantity': quantity,
    'checked': checked,
    'notes': notes,
    'ai_category': aiCategory,
  };

  ListItem copyWith({
    String? id, String? text, String? quantity, bool? checked,
    String? notes, String? aiCategory,
  }) => ListItem(
    id: id ?? this.id,
    text: text ?? this.text,
    quantity: quantity ?? this.quantity,
    checked: checked ?? this.checked,
    notes: notes ?? this.notes,
    aiCategory: aiCategory ?? this.aiCategory,
  );

  // Convenience alias
  String get name => text;
}
