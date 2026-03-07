import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
  static Future<String?> ask({
    required String prompt,
    required String module,
    String? systemPrompt,
  }) async {
    try {
      final supabaseUrl = Supabase.instance.client.supabaseUrl;
      final token =
          Supabase.instance.client.auth.currentSession?.accessToken ?? '';
      final uri = Uri.parse('$supabaseUrl/functions/v1/ai-proxy');

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'prompt': prompt,
          'module': module,
          if (systemPrompt != null) 'systemPrompt': systemPrompt,
        }),
      );

      if (response.statusCode == 200) {
        return response.body;
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
    required String module,
    String? systemPrompt,
  }) async {
    try {
      final raw = await ask(
        prompt: prompt,
        module: module,
        systemPrompt: systemPrompt,
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

  static Future<Map<String, dynamic>?> scrapeRecipe(String url) async {
    const systemPrompt =
        'You are a recipe extraction assistant. Always respond with valid JSON only, no markdown.';
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
      module: 'meals',
      systemPrompt: systemPrompt,
    );
  }

  static Future<List<String>> breakdownTask(String goal) async {
    const systemPrompt =
        'You are a productivity assistant. Respond with a JSON array of strings only, no markdown.';
    final prompt =
        'Break the following goal into 3 to 7 concrete, actionable sub-tasks. '
        'Return a JSON array of strings.\n\nGoal: $goal';

    try {
      final raw = await ask(
        prompt: prompt,
        module: 'tasks',
        systemPrompt: systemPrompt,
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
  }) async {
    const systemPrompt =
        'You are a certified personal trainer. Provide clear, safe, and effective workout plans.';
    final prompt = '''
Create a detailed weekly workout plan with the following parameters:
- Fitness goals: $goals
- Days per week available: $daysPerWeek
- Current fitness level: $fitnessLevel

Format the plan clearly with day-by-day workouts, sets, reps, and rest periods.
''';
    return ask(
      prompt: prompt,
      module: 'fitness',
      systemPrompt: systemPrompt,
    );
  }

  static Future<Map<String, String>> categorizeItems(
      List<String> items) async {
    const systemPrompt =
        'You are a grocery categorization assistant. Respond with valid JSON only, no markdown.';
    final prompt = '''
Categorize each of the following shopping list items into one of these categories:
Produce, Dairy, Meat, Bakery, Frozen, Pantry, Beverages, Other.

Return a JSON object where each key is an item name and each value is the category.

Items: ${items.join(', ')}
''';

    try {
      final result = await askJson(
        prompt: prompt,
        module: 'shopping',
        systemPrompt: systemPrompt,
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
  }) async {
    const systemPrompt =
        'You are a personal finance advisor. Provide actionable and encouraging budget feedback.';
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
      module: 'budget',
      systemPrompt: systemPrompt,
    );
  }
}
