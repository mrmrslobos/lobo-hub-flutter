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
  /// Strips common ```json … ``` wrappers from LLM output.
  static String _stripLlmJsonWrappers(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      final firstLineEnd = t.indexOf('\n');
      if (firstLineEnd != -1) {
        t = t.substring(firstLineEnd + 1);
      } else {
        t = t.substring(3);
      }
      final close = t.indexOf('```');
      if (close >= 0) t = t.substring(0, close);
      t = t.trim();
    }
    return t;
  }

  /// Parses flyer-vision responses: root object, or a bare JSON array of events.
  static Map<String, dynamic>? tryParseFlyerVisionJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final asObj = tryParseJsonObject(raw);
    if (asObj != null) return asObj;
    try {
      var s = raw.trim();
      s = _stripLlmJsonWrappers(s);
      final decoded = jsonDecode(s);
      if (decoded is List) return {'events': decoded};
    } catch (_) {}
    return null;
  }

  /// Parses a JSON object from LLM text that may include markdown fences
  /// or short preamble/epilogue. Returns null on failure.
  static Map<String, dynamic>? tryParseJsonObject(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = _stripLlmJsonWrappers(s);
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(s.substring(start, end + 1));
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

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
    String? imageBase64,
    String? imageMimeType,
  }) async {
    if (_aiBlocked) throw const AINotAvailableException();
    try {
      final body = <String, dynamic>{
        'family_id': familyId,
        'feature': feature,
        'prompt': prompt,
      };
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        body['image_base64'] = imageBase64;
        body['image_mime_type'] = imageMimeType ?? 'image/jpeg';
      }
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
      if (data is Map<String, dynamic>) {
        if (data['error'] == 'subscription_required') {
          throw const AINotAvailableException();
        }
        if (data.containsKey('text')) {
          return data['text'] as String?;
        }
      }
      if (data is String) return data;
      if (data is Map<String, dynamic>) return jsonEncode(data);
      return data != null ? jsonEncode(data) : null;
    } on AINotAvailableException {
      rethrow;
    } on FunctionException catch (e) {
      if (e.status == 402) {
        final d = e.details;
        if (d is Map && d['error'] == 'subscription_required') {
          throw const AINotAvailableException();
        }
      }
      debugPrint('[AiService] ask() FunctionException status=${e.status} details=${e.details}');
      return null;
    } catch (e, st) {
      final msg = e.toString();
      if (msg.contains('402') || msg.contains('subscription_required')) {
        throw const AINotAvailableException();
      }
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
      return tryParseJsonObject(raw);
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

  /// Family copilot: returns decoded `{ "reply", "actions" }` or null.
  static Future<Map<String, dynamic>?> askCopilot({
    required String userMessage,
    required String familyId,
    required String contextBlock,
  }) async {
    final prompt = '''
You are the Family copilot for the Huddle app. The user describes what they need; you propose concrete actions the app can perform.

Return ONLY valid JSON (no markdown) with this shape:
{"reply":"short friendly message to the user","actions":[]}

Each action is: {"type":"<type>","payload":{...}}

Allowed types and payloads:
- create_task: title (string), notes?, due_date (ISO date yyyy-MM-DD), due_time (HH:mm), priority LOW|MEDIUM|HIGH, reminder_minutes?
- create_event: title, start (ISO datetime), end (ISO datetime), location?, description?
- create_shopping_list: title, items optional array of {text, quantity?}
- add_list_items: list_id OR list_title_substring, items array of {text, quantity?}
- create_meal_plan_entry: date (yyyy-MM-DD), meal_type breakfast|lunch|dinner|snack, custom_meal (string)
- create_chore: title, description?, points (int), frequency DAILY|WEEKLY

If the user asks for restaurant reservations, put a helpful reply and optionally create_event for date night; you may mention they can open a reservation link from the calendar after the event is saved.

If nothing applies, use empty actions.

Context (read-only):
$contextBlock

User message:
$userMessage
''';
    try {
      final raw = await ask(
        prompt: prompt,
        feature: 'ai_copilot',
        familyId: familyId,
        responseMimeType: 'application/json',
      );
      if (raw == null) return null;
      final decoded = tryParseJsonObject(raw);
      if (decoded == null) return null;
      return decoded;
    } catch (e, st) {
      debugPrint('[AiService] askCopilot error: $e\n$st');
      return null;
    }
  }

  /// Vision: extract events from a flyer image. Returns JSON with "events" array.
  static Future<Map<String, dynamic>?> extractEventsFromImage({
    required String familyId,
    required String imageBase64,
    String mimeType = 'image/jpeg',
  }) async {
    final y = DateTime.now().year;
    final prompt = '''
You are transcribing a photo of a flyer, invitation, school handout, sports schedule, or church bulletin.

Rules:
- Extract EVERY event that has a date or date+time, even if text is small, angled, or busy in the background.
- Do NOT refuse or apologize for "blur" or quality—do your best with whatever is visible.
- If the year is missing, assume the NEXT occurrence of that month/day is in the current calendar year ($y); if that date is already past this year, use ${y + 1}.
- If only a date is given (no time), use 09:00 local as start and 10:00 as end unless the flyer states otherwise.
- If only "doors at 6 / show at 7", use those times.
- Put venue/address/room in "location", extra notes in "description".

Return ONLY valid JSON (no markdown, no commentary):
{"events":[{"title":"string","start":"ISO 8601 datetime","end":"ISO 8601 datetime","location":"string or empty","description":"string or empty"}]}

If there are truly no schedulable events, return {"events":[]}.
''';
    try {
      String? raw = await ask(
        prompt: prompt,
        feature: 'ai_events_vision',
        familyId: familyId,
        responseMimeType: 'application/json',
        imageBase64: imageBase64,
        imageMimeType: mimeType,
      );
      var parsed = tryParseFlyerVisionJson(raw);
      if (parsed != null) return parsed;

      // JSON mode + vision occasionally returns empty or non-JSON; retry plain text.
      debugPrint('[AiService] extractEventsFromImage: JSON mode parse failed, retrying without responseMimeType');
      raw = await ask(
        prompt: '$prompt\n\nReturn the JSON object only, nothing else.',
        feature: 'ai_events_vision',
        familyId: familyId,
        imageBase64: imageBase64,
        imageMimeType: mimeType,
      );
      parsed = tryParseFlyerVisionJson(raw);
      if (parsed == null && raw != null && raw.length > 2) {
        debugPrint('[AiService] extractEventsFromImage raw sample: ${raw.substring(0, raw.length > 400 ? 400 : raw.length)}');
      }
      return parsed;
    } catch (e, st) {
      debugPrint('[AiService] extractEventsFromImage error: $e\n$st');
      return null;
    }
  }

  /// Vision: identify food items visible in a fridge / pantry / shelf photo.
  /// Returns `{"items":[{"name","quantity?","unit?"},...]}` or null.
  static Future<Map<String, dynamic>?> extractPantryItemsFromImage({
    required String familyId,
    required String imageBase64,
    String mimeType = 'image/jpeg',
  }) async {
    final prompt = '''
You are helping a family meal-planning app. Look at this photo of a refrigerator, pantry shelf, or food storage.

Identify edible ingredients you can reasonably see or infer (produce, dairy, proteins, jars, packages with readable labels, eggs, etc.).
- Use clear generic names (e.g. "Greek yogurt", "cheddar cheese", "baby carrots").
- If quantity is unclear, omit quantity and unit or use a rough guess (e.g. "1" "bunch" for herbs).
- Skip non-food items (containers without identifiable food, empty shelves).
- Limit to at most 40 items; prefer the most useful for cooking.

Return ONLY valid JSON (no markdown):
{"items":[{"name":"string","quantity":"string optional","unit":"string optional"}]}

If nothing usable is visible, return {"items":[]}.
''';
    try {
      String? raw = await ask(
        prompt: prompt,
        feature: 'ai_recipes',
        familyId: familyId,
        responseMimeType: 'application/json',
        imageBase64: imageBase64,
        imageMimeType: mimeType,
      );
      var parsed = raw != null ? tryParseJsonObject(raw) : null;
      if (parsed != null && parsed['items'] is List) return parsed;

      debugPrint('[AiService] extractPantryItemsFromImage: JSON mode parse failed, retrying without responseMimeType');
      raw = await ask(
        prompt: '$prompt\n\nReturn the JSON object only, nothing else.',
        feature: 'ai_recipes',
        familyId: familyId,
        imageBase64: imageBase64,
        imageMimeType: mimeType,
      );
      parsed = raw != null ? tryParseJsonObject(raw) : null;
      if (parsed != null && parsed['items'] is List) return parsed;
      return null;
    } catch (e, st) {
      debugPrint('[AiService] extractPantryItemsFromImage error: $e\n$st');
      return null;
    }
  }
}
