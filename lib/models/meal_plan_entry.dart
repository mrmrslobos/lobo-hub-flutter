// lib/models/meal_plan_entry.dart
// ignore_for_file: constant_identifier_names
import 'model_json_helpers.dart';

class MealPlanEntry {
  final String id;
  final String familyId;
  final DateTime date;
  final String mealType; // stored as lowercase string ('breakfast','lunch','dinner','snack')
  final String? recipeId;
  final String? customMeal;
  final String? notes;
  final int? servings;
  final String? prepNotes;
  /// `weekly_same_slot` | `daily` | null
  final String? repeatRule;
  final String? sourceMealPlanId;
  final String? leftoverMealPlanId;
  final DateTime updatedAt;
  /// Supabase `created_by`; empty means legacy (RLS allows any member to update/delete).
  final String createdBy;

  MealPlanEntry({
    required this.id,
    required this.familyId,
    required this.date,
    required this.mealType,
    this.recipeId,
    this.customMeal,
    this.notes,
    this.servings,
    this.prepNotes,
    this.repeatRule,
    this.sourceMealPlanId,
    this.leftoverMealPlanId,
    String? title,
    String? createdBy,
    String? creatorId,
    DateTime? updatedAt,
  })  : createdBy = creatorId ?? createdBy ?? '',
        updatedAt = updatedAt ?? DateTime.now();

  factory MealPlanEntry.fromJson(Map<String, dynamic> j) => MealPlanEntry(
    id: j['id'] as String? ?? '',
    familyId: j['family_id'] as String? ?? '',
    date: parseDate(j['date']),
    mealType: (j['meal_type'] as String? ?? 'breakfast').toLowerCase(),
    recipeId: j['recipe_id'] as String?,
    customMeal: j['custom_meal'] as String?,
    notes: j['notes'] as String?,
    servings: (j['servings'] as num?)?.toInt(),
    prepNotes: j['prep_notes'] as String?,
    repeatRule: j['repeat_rule'] as String?,
    sourceMealPlanId: j['source_meal_plan_id'] as String?,
    leftoverMealPlanId: j['leftover_meal_plan_id'] as String?,
    updatedAt: parseDateOpt(j['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    createdBy: j['created_by'] as String? ?? j['createdBy'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'family_id': familyId,
    'date': date.toIso8601String(),
    'meal_type': mealType,
    'recipe_id': recipeId,
    'custom_meal': customMeal,
    'notes': notes,
    'servings': servings,
    'prep_notes': prepNotes,
    'repeat_rule': repeatRule,
    'source_meal_plan_id': sourceMealPlanId,
    'leftover_meal_plan_id': leftoverMealPlanId,
    'updated_at': updatedAt.toIso8601String(),
    if (createdBy.isNotEmpty) 'created_by': createdBy,
  };

  // Convenience getters
  String get title => customMeal ?? '';

  MealPlanEntry copyWith({
    String? id, String? familyId, DateTime? date, String? mealType,
    String? recipeId, String? customMeal, String? notes, int? servings,
    String? prepNotes, String? repeatRule, String? sourceMealPlanId,
    String? leftoverMealPlanId, DateTime? updatedAt,
    String? createdBy,
  }) => MealPlanEntry(
    id: id ?? this.id, familyId: familyId ?? this.familyId,
    date: date ?? this.date, mealType: mealType ?? this.mealType,
    recipeId: recipeId ?? this.recipeId, customMeal: customMeal ?? this.customMeal,
    notes: notes ?? this.notes,
    servings: servings ?? this.servings,
    prepNotes: prepNotes ?? this.prepNotes,
    repeatRule: repeatRule ?? this.repeatRule,
    sourceMealPlanId: sourceMealPlanId ?? this.sourceMealPlanId,
    leftoverMealPlanId: leftoverMealPlanId ?? this.leftoverMealPlanId,
    createdBy: createdBy ?? this.createdBy,
    updatedAt: updatedAt ??
        ((date != null || mealType != null || recipeId != null || customMeal != null || notes != null || servings != null || prepNotes != null || repeatRule != null || sourceMealPlanId != null || leftoverMealPlanId != null || createdBy != null)
            ? DateTime.now()
            : this.updatedAt),
  );
}
