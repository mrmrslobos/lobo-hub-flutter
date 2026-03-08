import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
  /// Call the Supabase ai-proxy edge function.
  ///
  /// [feature] must match a key in the edge function's FEATURE_TIER_MAP
  /// (e.g. 'ai_tasks', 'ai_recipes', 'ai_fitness', 'ai_budget', 'ai_lists').
  /// [familyId] is the current family's ID for subscription-tier verification.
  static Future<String?> ask({
    required String prompt,
    required String feature,
    required String familyId,
    String? responseMimeType,
    Map<String, dynamic>? responseSchema,
  }) async {
    try {
      final restUrl = Supabase.instance.client.rest.url;
      final supabaseUrl = restUrl.replaceAll('/rest/v1', '');
      final anonKey = Supabase.instance.client.rest.headers['apikey'] ?? '';
      final uri = Uri.parse('$supabaseUrl/functions/v1/ai-proxy');

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

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $anonKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('text')) {
          return data['text'] as String?;
        }
        // Fallback: return raw body if it's not the expected JSON wrapper
        return response.body;
      } else if (response.statusCode == 402) {
        debugPrint('[AiService] Subscription required: ${response.body}');
        return null;
      } else {
        debugPrint(
            '[AiService] Non-200 response: ${response.statusCode} ${response.body}');
        return null;
      }
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
