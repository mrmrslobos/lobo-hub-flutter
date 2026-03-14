import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when AI is used on a plan that doesn't include AI features.
class AINotAvailableException implements Exception {
  const AINotAvailableException();
  @override
  String toString() => 'AI features require an AI or AI Family subscription.';
}

class AiService {
  /// Whether AI is currently blocked. Set by the provider so the service
  /// can check without needing a BuildContext.
  static bool _aiBlocked = false;
  static void setAIBlocked(bool blocked) => _aiBlocked = blocked;
  static bool get isAIBlocked => _aiBlocked;

  /// Call the Supabase ai-proxy edge function.
  ///
  /// [feature] must match a key in the edge function's FEATURE_TIER_MAP
  /// (e.g. 'ai_tasks', 'ai_recipes', 'ai_fitness', 'ai_budget', 'ai_lists').
  /// [familyId] is the current family's ID for subscription-tier verification.
  ///
  /// Throws [AINotAvailableException] if the family's plan doesn't include AI.
  static Future<String?> ask({
    required String prompt,
    required String feature,
    required String familyId,
    String? responseMimeType,
    Map<String, dynamic>? responseSchema,
  }) async {
    if (_aiBlocked) throw const AINotAvailableException();
    try {
      final body = <String, dynamic>{
        'familyId': familyId,
        'feature': feature,
        'prompt': prompt,
      };
      if (responseMimeType != null) {
        body['responseMimeType'] = responseMimeType;
      }
      if (responseSchema != null) {
        body['responseSchema'] = responseSchema;
      }

      // Use the SDK's functions.invoke which handles auth headers automatically
      final response = await Supabase.instance.client.functions.invoke(
        'ai-proxy',
        body: body,
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('text')) {
        return data['text'] as String?;
      }
      if (data is String) return data;
      return jsonEncode(data);
    } catch (e, st) {
      debugPrint('[AiService] ask() error: $e\n$st');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> askJson({
    required String prompt,
    required String feature,
    required String familyId,
  }) async {
    try {
      final raw = await ask(
        prompt: prompt,
        feature: feature,
        familyId: familyId,
        responseMimeType: 'application/json',
      );
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e, st) {
      debugPrint('[AiService] askJson() decode error: $e\n$st');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> scrapeRecipe(
    String url, {
    required String familyId,
  }) async {
    final prompt = '''
Extract the recipe from this URL and return a JSON object with exactly these fields:
- title (string)
- description (string)
- ingredients (array of objects with fields: name, amount, unit)
- steps (array of strings)
- prepMinutes (integer)
- cookMinutes (integer)
- servings (integer)

URL: $url
''';
    return askJson(
      prompt: prompt,
      feature: 'ai_recipes',
      familyId: familyId,
    );
  }

  static Future<List<String>> breakdownTask(
    String goal, {
    required String familyId,
  }) async {
    final prompt =
        'Break the following goal into 3 to 7 concrete, actionable sub-tasks. '
        'Return a JSON array of strings.\n\nGoal: $goal';

    try {
      final raw = await ask(
        prompt: prompt,
        feature: 'ai_tasks',
        familyId: familyId,
        responseMimeType: 'application/json',
      );
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e, st) {
      debugPrint('[AiService] breakdownTask() error: $e\n$st');
      return [];
    }
  }

  static Future<String?> generateFitnessPlan({
    required String goals,
    required int daysPerWeek,
    required String fitnessLevel,
    required String familyId,
  }) async {
    final prompt = '''
Create a detailed weekly workout plan with the following parameters:
- Fitness goals: $goals
- Days per week available: $daysPerWeek
- Current fitness level: $fitnessLevel

Format the plan clearly with day-by-day workouts, sets, reps, and rest periods.
''';
    return ask(
      prompt: prompt,
      feature: 'ai_fitness',
      familyId: familyId,
    );
  }

  static Future<Map<String, String>> categorizeItems(
    List<String> items, {
    required String familyId,
  }) async {
    final prompt = '''
Categorize each of the following shopping list items into one of these categories:
Produce, Dairy, Meat, Bakery, Frozen, Pantry, Beverages, Other.

Return a JSON object where each key is an item name and each value is the category.

Items: ${items.join(', ')}
''';

    try {
      final result = await askJson(
        prompt: prompt,
        feature: 'ai_lists',
        familyId: familyId,
      );
      if (result == null) return {};
      return result.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e, st) {
      debugPrint('[AiService] categorizeItems() error: $e\n$st');
      return {};
    }
  }

  static Future<Map<String, dynamic>?> generateEventItinerary(
    String description, {
    required String familyId,
  }) async {
    final prompt = '''
Create an event itinerary for the following:
$description

Return a JSON object with:
- "itinerary": a detailed itinerary as a string with timeline and activities
- "checklist": an array of strings for things to prepare/do

Keep it practical and family-friendly.
''';
    return askJson(prompt: prompt, feature: 'ai_tasks', familyId: familyId);
  }

  static Future<Map<String, dynamic>?> planFullEvent({
    required String template,
    required String eventName,
    required String date,
    String? guestCount,
    String? budget,
    String? notes,
    required String familyId,
  }) async {
    final prompt = '''
Plan a complete "$eventName" event (type: $template) on $date.
${guestCount != null && guestCount.isNotEmpty ? 'Expected guests: $guestCount' : ''}
${budget != null && budget.isNotEmpty ? 'Budget: \$$budget' : ''}
${notes != null && notes.isNotEmpty ? 'Additional notes: $notes' : ''}

Return a JSON object with exactly these fields:
- "description": string, a short event description
- "location_suggestion": string, a suggested venue/location
- "tasks": array of objects with "title" (string), "priority" (HIGH/MEDIUM/LOW), "daysBefore" (integer, days before the event to complete this)
- "lists": array of objects with "title" (string), "category" (GROCERY/OTHER), "items" (array of objects with "text" and optional "quantity")
- "tips": array of helpful tip strings (3-5 tips)
''';
    return askJson(prompt: prompt, feature: 'ai_tasks', familyId: familyId);
  }

  static Future<String?> refineWeeklyMealPlan({
    required String currentPlanJson,
    required String refinementRequest,
    required String familyId,
  }) async {
    final prompt = '''
Here is the current weekly meal plan:
$currentPlanJson

The user wants to refine it: "$refinementRequest"

Return an updated JSON array of 7 day objects with the same structure (dayName, meals array with type/name/prepMinutes/cookMinutes/ingredients/steps/servings), applying the requested changes.
Return valid JSON only, no markdown fences.
''';
    return ask(prompt: prompt, feature: 'ai_recipes', familyId: familyId);
  }

  static Future<String?> analyzeBudget({
    required double totalIncome,
    required double totalExpenses,
    required Map<String, double> byCategory,
    required String familyId,
  }) async {
    final categoryLines = byCategory.entries
        .map((e) => '  - ${e.key}: \$${e.value.toStringAsFixed(2)}')
        .join('\n');
    final prompt = '''
Analyze the following monthly budget and provide spending insights and suggestions:

Total Income: \$${totalIncome.toStringAsFixed(2)}
Total Expenses: \$${totalExpenses.toStringAsFixed(2)}
Net: \$${(totalIncome - totalExpenses).toStringAsFixed(2)}

Spending by category:
$categoryLines

Please provide:
1. An overview of the spending situation
2. Categories where spending seems high
3. Practical suggestions for saving money
4. Positive observations if any
''';
    return ask(
      prompt: prompt,
      feature: 'ai_budget',
      familyId: familyId,
    );
  }
}
