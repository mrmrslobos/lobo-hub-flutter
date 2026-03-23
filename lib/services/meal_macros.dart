import '../models/models.dart';

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
