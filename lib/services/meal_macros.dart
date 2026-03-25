import '../models/models.dart';

/// Sum macro maps (null if no values for that nutrient).
Map<String, double?> aggregateMacros(Iterable<Map<String, double?>> parts) {
  double? kcal, protein, carbs, fat, fiber;
  for (final m in parts) {
    final a = m['kcal'];
    if (a != null) kcal = (kcal ?? 0) + a;
    final p = m['protein'];
    if (p != null) protein = (protein ?? 0) + p;
    final c = m['carbs'];
    if (c != null) carbs = (carbs ?? 0) + c;
    final f = m['fat'];
    if (f != null) fat = (fat ?? 0) + f;
    final fb = m['fiber'];
    if (fb != null) fiber = (fiber ?? 0) + fb;
  }
  return {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
  };
}

/// Optional family targets from [Family.settings] key `meal_macro_targets`.
Map<String, double?> mealMacroTargetsFromSettings(Map<String, dynamic> settings) {
  final raw = settings['meal_macro_targets'];
  if (raw is! Map) return {};
  double? d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
  return {
    'kcal': d(raw['kcal']),
    'protein': d(raw['protein']),
    'carbs': d(raw['carbs']),
    'fat': d(raw['fat']),
  };
}

/// Scale recipe macros (stored per full recipe) to [servings] portions.
Map<String, double?> scaledMacrosForMeal(Recipe? recipe, int? servings) {
  if (recipe == null || servings == null || servings <= 0 || recipe.servings <= 0) {
    return {
      'kcal': recipe?.kcal?.toDouble(),
      'protein': recipe?.proteinG,
      'carbs': recipe?.carbsG,
      'fat': recipe?.fatG,
      'fiber': recipe?.fiberG,
    };
  }
  final m = servings / recipe.servings;
  return {
    'kcal': recipe.kcal != null ? recipe.kcal! * m : null,
    'protein': recipe.proteinG != null ? recipe.proteinG! * m : null,
    'carbs': recipe.carbsG != null ? recipe.carbsG! * m : null,
    'fat': recipe.fatG != null ? recipe.fatG! * m : null,
    'fiber': recipe.fiberG != null ? recipe.fiberG! * m : null,
  };
}
