// Helpers: turn planned meals + recipes into consolidated shopping lines.

import '../models/models.dart';

class MealShoppingLine {
  final String name;
  final String? quantity;
  final String? unit;
  const MealShoppingLine({required this.name, this.quantity, this.unit});
}

/// Merge duplicate ingredient names (case-insensitive), summing numeric quantities when possible.
List<MealShoppingLine> consolidateShoppingLines(List<MealShoppingLine> raw) {
  final byKey = <String, MealShoppingLine>{};
  for (final line in raw) {
    final key = line.name.toLowerCase().trim();
    if (key.isEmpty) continue;
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = line;
      continue;
    }
    final q1 = double.tryParse(existing.quantity ?? '');
    final q2 = double.tryParse(line.quantity ?? '');
    if (q1 != null && q2 != null && existing.unit == line.unit) {
      byKey[key] = MealShoppingLine(
        name: existing.name,
        quantity: (q1 + q2).toString(),
        unit: existing.unit,
      );
    } else {
      byKey[key] = MealShoppingLine(
        name: existing.name,
        quantity: null,
        unit: null,
      );
    }
  }
  final out = byKey.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

List<MealShoppingLine> linesFromMealPlans({
  required String familyId,
  required List<MealPlanEntry> meals,
  required List<Recipe> recipes,
  required List<DateTime> weekDays,
}) {
  final recipeById = {for (final r in recipes) r.id: r};
  final lines = <MealShoppingLine>[];

  bool inWeek(DateTime mealDate) {
    final d = DateTime(mealDate.year, mealDate.month, mealDate.day);
    return weekDays.any((w) =>
        w.year == d.year && w.month == d.month && w.day == d.day);
  }

  for (final m in meals) {
    if (m.familyId != familyId) continue;
    if (!inWeek(m.date)) continue;
    final rid = m.recipeId;
    if (rid == null || rid.isEmpty) continue;
    final recipe = recipeById[rid];
    if (recipe == null) continue;
    final mult = (m.servings != null && m.servings! > 0 && recipe.servings > 0)
        ? m.servings! / recipe.servings
        : 1.0;
    for (final ing in recipe.ingredients) {
      final q = double.tryParse(ing.quantity ?? '');
      final scaled = (q != null) ? (q * mult).toString() : ing.quantity;
      lines.add(MealShoppingLine(
        name: ing.name,
        quantity: scaled,
        unit: ing.unit,
      ));
    }
  }
  return consolidateShoppingLines(lines);
}

/// Ingredients for one planned meal (recipe-linked), scaled by servings.
List<MealShoppingLine> linesForSingleMeal({
  required MealPlanEntry meal,
  required List<Recipe> recipes,
}) {
  final rid = meal.recipeId;
  if (rid == null || rid.isEmpty) return const [];
  Recipe? recipe;
  for (final r in recipes) {
    if (r.id == rid) {
      recipe = r;
      break;
    }
  }
  if (recipe == null) return const [];
  final mult = (meal.servings != null && meal.servings! > 0 && recipe.servings > 0)
      ? meal.servings! / recipe.servings
      : 1.0;
  final lines = <MealShoppingLine>[];
  for (final ing in recipe.ingredients) {
    final q = double.tryParse(ing.quantity ?? '');
    final scaled = (q != null) ? (q * mult).toString() : ing.quantity;
    lines.add(MealShoppingLine(
      name: ing.name,
      quantity: scaled,
      unit: ing.unit,
    ));
  }
  return consolidateShoppingLines(lines);
}
