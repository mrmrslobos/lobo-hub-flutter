// lib/models/recipe_ingredient.dart
// ignore_for_file: constant_identifier_names
class RecipeIngredient {
  final String name;
  final String? quantity;
  final String? unit;

  RecipeIngredient({required this.name, String? quantity, String? amount, this.unit})
      : quantity = quantity ?? amount;

  // Convenience alias used by screens
  String? get amount => quantity;

  factory RecipeIngredient.fromString(String s) => RecipeIngredient(name: s);

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) => RecipeIngredient(
    name: j['name'] as String? ?? '',
    quantity: j['quantity'] as String?,
    unit: j['unit'] as String?,
  );

  Map<String, dynamic> toJson() => {'name': name, 'quantity': quantity, 'unit': unit};

  @override
  String toString() => quantity != null ? '$quantity${unit != null ? ' $unit' : ''} $name' : name;
}
