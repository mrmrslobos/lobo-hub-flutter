// lib/models/recipe.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';
import 'recipe_ingredient.dart';

class Recipe {
  final String id;
  final String familyId;
  final String title;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final int servings;
  final List<String> tags;
  final String? image;
  final int? prepMinutes;
  final int? cookMinutes;
  /// Per full recipe (not per serving) unless noted in UI.
  final int? kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final DateTime updatedAt;
  /// Supabase `created_by` — used for RLS; empty means legacy / unknown.
  final String createdBy;

  Recipe({
    required this.id,
    required this.familyId,
    required this.title,
    List<RecipeIngredient>? ingredients,
    this.steps = const [],
    int? servings,
    this.tags = const [],
    this.image,
    this.prepMinutes,
    this.cookMinutes,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    String? description,
    String? sourceUrl,
    String? createdBy,
    String? creatorId,
    DateTime? updatedAt,
  })  : createdBy = creatorId ?? createdBy ?? '',
        updatedAt = updatedAt ?? DateTime.now(),
        servings = servings ?? 4,
       ingredients = ingredients ?? const [];

  factory Recipe.fromJson(Map<String, dynamic> j) {
    final rawIngs = j['ingredients'];
    final List<RecipeIngredient> ingredients;
    if (rawIngs is List) {
      ingredients = rawIngs.map((e) {
        if (e is String) return RecipeIngredient.fromString(e);
        if (e is Map<String, dynamic>) return RecipeIngredient.fromJson(e);
        return RecipeIngredient.fromString(e.toString());
      }).toList();
    } else {
      ingredients = const [];
    }
    return Recipe(
      id: j['id'] as String? ?? '',
      familyId: j['family_id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      ingredients: ingredients,
      steps: strList(j['steps']),
      servings: (j['servings'] as num?)?.toInt() ?? 4,
      tags: strList(j['tags']),
      image: j['image'] as String?,
      prepMinutes: (j['prep_minutes'] ?? j['prepMinutes']) as int?,
      cookMinutes: (j['cook_minutes'] ?? j['cookMinutes']) as int?,
      kcal: (j['kcal'] as num?)?.toInt(),
      proteinG: (j['protein_g'] as num?)?.toDouble() ?? (j['proteinG'] as num?)?.toDouble(),
      carbsG: (j['carbs_g'] as num?)?.toDouble() ?? (j['carbsG'] as num?)?.toDouble(),
      fatG: (j['fat_g'] as num?)?.toDouble() ?? (j['fatG'] as num?)?.toDouble(),
      fiberG: (j['fiber_g'] as num?)?.toDouble() ?? (j['fiberG'] as num?)?.toDouble(),
      updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: j['created_by'] as String? ?? j['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'title': title,
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
    'steps': steps,
    'servings': servings,
    'tags': tags,
    'image': image,
    if (prepMinutes != null) 'prepMinutes': prepMinutes,
    if (cookMinutes != null) 'cookMinutes': cookMinutes,
    'kcal': kcal,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'fiber_g': fiberG,
    'updated_at': updatedAt.toIso8601String(),
    if (createdBy.isNotEmpty) 'created_by': createdBy,
  };

  // Convenience getters
  String? get imageUrl => image;
  String? get description => null;

  Recipe copyWith({
    String? id, String? familyId, String? title, List<RecipeIngredient>? ingredients,
    List<String>? steps, int? servings, List<String>? tags, String? image,
    int? prepMinutes, int? cookMinutes, int? kcal, double? proteinG,
    double? carbsG, double? fatG, double? fiberG, DateTime? updatedAt,
    String? createdBy,
  }) => Recipe(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    title: title ?? this.title, ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps, servings: servings ?? this.servings,
    tags: tags ?? this.tags, image: image ?? this.image,
    prepMinutes: prepMinutes ?? this.prepMinutes,
    cookMinutes: cookMinutes ?? this.cookMinutes,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    fiberG: fiberG ?? this.fiberG,
    createdBy: createdBy ?? this.createdBy,
    updatedAt: updatedAt ??
        ((title != null || ingredients != null || steps != null || servings != null ||
                tags != null || image != null || prepMinutes != null || cookMinutes != null ||
                kcal != null || proteinG != null || carbsG != null || fatG != null || fiberG != null ||
                createdBy != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}
