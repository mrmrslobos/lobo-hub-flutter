// lib/screens/meals/meals_screen.dart
// Meal planning + recipe library screen for FamilyHub

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/meal_plan_shopping.dart';
import '../../services/meal_macros.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../services/ai_service.dart';
import '../../services/locale_service.dart';
import '../../config/theme.dart';
import '../../widgets/subscription_modal.dart';
import '../../utils/debounce.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

/// Normalize recipe titles so AI duplicates ("Taco Night" vs "taco night") match.
String _recipeTitleNormKey(String title) =>
    title.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

Recipe? _findRecipeByNormTitle(List<Recipe> recipes, String familyId, String title) {
  final key = _recipeTitleNormKey(title);
  if (key.isEmpty) return null;
  for (final r in recipes) {
    if (r.familyId != familyId) continue;
    if (_recipeTitleNormKey(r.title) == key) return r;
  }
  return null;
}

// ─── Constants ───────────────────────────────────────────────────────────────

const _mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

/// Helper for consolidating duplicate ingredients across recipes.
class _IngredientAccum {
  final String name;
  final String? unit;
  double? numQty;
  final String? rawQty;
  _IngredientAccum({required this.name, this.unit, this.numQty, this.rawQty});
}

const _mealTypeLabels = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'dinner': 'Dinner',
  'snack': 'Snack',
};

const _mealTypeEmojis = {
  'breakfast': '🍳',
  'lunch': '🥗',
  'dinner': '🍽️',
  'snack': '🍎',
};

const _tagEmojis = {
  'vegetarian': '🥦',
  'vegan': '🌱',
  'chicken': '🍗',
  'beef': '🥩',
  'seafood': '🐟',
  'pasta': '🍝',
  'soup': '🍲',
  'salad': '🥗',
  'dessert': '🍰',
  'breakfast': '🍳',
  'snack': '🍎',
  'baking': '🍞',
};

const _availableTags = [
  'vegetarian',
  'vegan',
  'gluten-free',
  'dairy-free',
  'chicken',
  'beef',
  'seafood',
  'pasta',
  'soup',
  'salad',
  'dessert',
  'breakfast',
  'quick',
  'slow-cooker',
  'baking',
  'snack',
  'family-favorite',
];

// ─── Main Screen ─────────────────────────────────────────────────────────────

class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key});

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // AI Chef Suggestion
  final _chefController = TextEditingController();
  bool _chefLoading = false;
  List<Map<String, dynamic>>? _chefSuggestions;

  // AI Week Planner
  final _weekPlannerController = TextEditingController();
  bool _weekPlannerLoading = false;
  bool _pantryFirstWeek = true;
  final _kcalTargetCtrl = TextEditingController();
  final _proteinTargetCtrl = TextEditingController();
  final _carbsTargetCtrl = TextEditingController();
  final _fatTargetCtrl = TextEditingController();

  // Refinement input
  final _refineController = TextEditingController();
  bool _refineLoading = false;
  String? _lastPlanJson; // Stores raw plan JSON for refinement
  final List<Map<String, dynamic>> _refineHistory = []; // {request, status, error?}

  // Import from URL
  final _importUrlController = TextEditingController();
  bool _importLoading = false;

  void _openCookMode(Recipe recipe) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _CookModeScreen(recipe: recipe),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chefController.dispose();
    _weekPlannerController.dispose();
    _kcalTargetCtrl.dispose();
    _proteinTargetCtrl.dispose();
    _carbsTargetCtrl.dispose();
    _fatTargetCtrl.dispose();
    _refineController.dispose();
    _importUrlController.dispose();
    super.dispose();
  }

  Future<void> _showMacroTargetsDialog() async {
    final provider = context.read<AppProvider>();
    final fam = provider.activeFamily;
    if (fam == null) return;
    final t = mealMacroTargetsFromSettings(fam.settings);
    _kcalTargetCtrl.text = t['kcal']?.toStringAsFixed(0) ?? '';
    _proteinTargetCtrl.text = t['protein']?.toStringAsFixed(0) ?? '';
    _carbsTargetCtrl.text = t['carbs']?.toStringAsFixed(0) ?? '';
    _fatTargetCtrl.text = t['fat']?.toStringAsFixed(0) ?? '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Meal macro targets', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Optional daily targets for the household. The week planner uses them to shape meals.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kcalTargetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Calories (kcal / day)'),
              ),
              TextField(
                controller: _proteinTargetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Protein (g / day)'),
              ),
              TextField(
                controller: _carbsTargetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Carbs (g / day)'),
              ),
              TextField(
                controller: _fatTargetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fat (g / day)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    double? p(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final nextTargets = <String, dynamic>{};
    final k = p(_kcalTargetCtrl.text);
    final pr = p(_proteinTargetCtrl.text);
    final c = p(_carbsTargetCtrl.text);
    final f = p(_fatTargetCtrl.text);
    if (k != null) nextTargets['kcal'] = k;
    if (pr != null) nextTargets['protein'] = pr;
    if (c != null) nextTargets['carbs'] = c;
    if (f != null) nextTargets['fat'] = f;

    final settings = Map<String, dynamic>.from(fam.settings);
    if (nextTargets.isEmpty) {
      settings.remove('meal_macro_targets');
    } else {
      settings['meal_macro_targets'] = nextTargets;
    }
    final nextFam = fam.copyWith(settings: settings);
    await provider.saveAndSync(
      provider.db.copyWith(
        families: provider.db.families.map((x) => x.id == fam.id ? nextFam : x).toList(),
      ),
    );
    if (mounted) _showSnack(context, 'Macro targets saved');
  }

  /// Strip markdown code fences from AI response
  String _stripFences(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.substring(s.indexOf('\n') + 1);
    }
    if (s.endsWith('```')) {
      s = s.substring(0, s.lastIndexOf('```'));
    }
    return s.trim();
  }

  // ── AI Chef Suggestion ──
  Future<void> _generateChefSuggestion() async {
    if (SubscriptionModal.guardAI(context)) return;
    final prefs = _chefController.text.trim();
    if (prefs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your meal preferences'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() { _chefLoading = true; _chefSuggestions = null; });

    final localeService = context.read<LocaleService>();
    final useMetric = localeService.config.useMetric;
    final unitInstruction = useMetric
        ? 'IMPORTANT: Use metric units (grams, kilograms, millilitres, litres). Never use ounces, pounds, cups, or other imperial units.'
        : 'Use standard US units (cups, tablespoons, ounces, pounds).';

    const systemPrompt =
        'You are a creative family chef AI. Always respond with valid JSON only, no markdown fences.';
    final prompt = '''
Suggest 3 meal recipes based on the following preferences:
"$prefs"

$unitInstruction

Return a JSON array of exactly 3 objects, each with these fields:
- "title" (string): recipe name
- "summary" (string): 1-2 sentence description
- "prepMinutes" (integer): estimated prep time in minutes
- "cookMinutes" (integer): estimated cooking time in minutes
- "ingredients" (array of objects with "name", "quantity", "unit")
- "steps" (array of strings)
- "servings" (integer)
- "tags" (array of strings like "vegetarian", "quick", etc.)
''';

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() => _chefLoading = false);
        return;
      }
      final raw = await AiService.ask(prompt: '$systemPrompt\n\n$prompt', feature: 'ai_recipes', familyId: familyId);
      if (raw == null) {
        if (mounted) setState(() => _chefLoading = false);
        return;
      }
      context.read<AppProvider>().saveAiHistory(module: 'meals', prompt: 'Generate chef meal suggestions', response: raw);
      final cleaned = _stripFences(raw);
      final decoded = jsonDecode(cleaned);
      if (decoded is List) {
        setState(() {
          _chefSuggestions = decoded.cast<Map<String, dynamic>>();
          _chefLoading = false;
        });
      } else {
        setState(() => _chefLoading = false);
      }
    } catch (e) {
      debugPrint('[Meals] chef suggestion error: $e');
      if (mounted) {
        setState(() => _chefLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate suggestions. Please try again.'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _saveChefRecipe(Map<String, dynamic> suggestion) {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final userId = provider.activeUser?.id ?? '';
    final familyId = provider.activeFamily?.id ?? '';

    final ingredients = <RecipeIngredient>[];
    if (suggestion['ingredients'] is List) {
      for (final ing in suggestion['ingredients'] as List) {
        if (ing is Map<String, dynamic>) {
          ingredients.add(RecipeIngredient(
            name: ing['name']?.toString() ?? '',
            quantity: ing['quantity']?.toString(),
            unit: ing['unit']?.toString(),
          ));
        }
      }
    }
    final steps = <String>[];
    if (suggestion['steps'] is List) {
      for (final s in suggestion['steps'] as List) {
        steps.add(s.toString());
      }
    }
    final tags = <String>[];
    if (suggestion['tags'] is List) {
      for (final t in suggestion['tags'] as List) {
        tags.add(t.toString());
      }
    }

    final rawTitle = suggestion['title']?.toString().trim() ?? '';
    final title = rawTitle.isNotEmpty ? rawTitle : 'AI Recipe';
    final dup = _findRecipeByNormTitle(db.recipes, familyId, title);
    if (dup != null) {
      _showSnack(context, '"$title" is already in your Recipe Box');
      return;
    }

    final newRecipe = Recipe(
      id: const Uuid().v4(),
      familyId: familyId,
      title: title,
      ingredients: ingredients,
      steps: steps,
      servings: (suggestion['servings'] is int) ? suggestion['servings'] as int : 4,
      tags: tags,
      prepMinutes: (suggestion['prepMinutes'] as num?)?.toInt(),
      cookMinutes: (suggestion['cookMinutes'] as num?)?.toInt(),
      createdBy: userId,
    );

    provider.saveAndSync(db.copyWith(recipes: [...db.recipes, newRecipe]));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${newRecipe.title}" to Recipe Box'), behavior: SnackBarBehavior.floating),
    );
  }

  // ── AI Week Planner ──
  Future<void> _generateWeekPlan() async {
    if (SubscriptionModal.guardAI(context)) return;
    final prefs = _weekPlannerController.text.trim();
    if (prefs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your meal preferences'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _weekPlannerLoading = true);

    final localeService = context.read<LocaleService>();
    final useMetric = localeService.config.useMetric;
    final unitInstruction = useMetric
        ? 'IMPORTANT: Use metric units (grams, kilograms, millilitres, litres, centimetres). Never use ounces, pounds, cups, or other imperial units.'
        : 'Use standard US units (cups, tablespoons, ounces, pounds).';

    final family = context.read<AppProvider>().activeFamily;
    final db = context.read<AppProvider>().db;
    final familyId = family?.id ?? '';
    final targets = mealMacroTargetsFromSettings(family?.settings ?? {});
    final pantryLines = db.pantryItems
        .where((p) => p.familyId == familyId)
        .map((p) {
          final q = [p.quantity, p.unit].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
          return q.isEmpty ? p.name : '$q ${p.name}';
        })
        .toList();

    final macroBlock = StringBuffer();
    if (targets.isNotEmpty) {
      macroBlock.writeln('Approximate daily nutrition targets for the household (use as a soft guide across the week):');
      if (targets['kcal'] != null) macroBlock.writeln('- Calories: ~${targets['kcal']!.round()} kcal');
      if (targets['protein'] != null) macroBlock.writeln('- Protein: ~${targets['protein']!.round()} g');
      if (targets['carbs'] != null) macroBlock.writeln('- Carbs: ~${targets['carbs']!.round()} g');
      if (targets['fat'] != null) macroBlock.writeln('- Fat: ~${targets['fat']!.round()} g');
      macroBlock.writeln('Include estimated per-meal calories and macros in each meal object when possible (see JSON shape below).');
    }

    final pantryBlock = pantryLines.isEmpty
        ? '(No pantry list in the app — shop as needed.)'
        : pantryLines.map((s) => '- $s').join('\n');

    const systemPrompt =
        'You are a weekly meal planning AI for families. Always respond with valid JSON only, no markdown fences.';
    final prompt = '''
Create a 7-day meal plan (Monday through Sunday) based on these preferences:
"$prefs"

$unitInstruction

${_pantryFirstWeek ? 'PRIORITY: Prefer recipes that use ingredients from the pantry list below. Minimize waste; you may still add a few fresh items each day.' : 'Pantry reference (use when helpful):'}
Pantry on hand:
$pantryBlock

${macroBlock.isEmpty ? '' : macroBlock.toString()}

Return a JSON array of 7 objects, each with:
- "dayName" (string): "Monday", "Tuesday", etc.
- "meals" (array of objects, each with):
  - "type" (string): "breakfast", "lunch", or "dinner"
  - "name" (string): meal name
  - "prepMinutes" (integer): estimated prep time in minutes
  - "cookMinutes" (integer): estimated cooking time in minutes
  - "ingredients" (array of objects with "name", "quantity", "unit")
  - "steps" (array of strings)
  - "servings" (integer)
  - "kcal" (number, optional): estimated calories for the whole meal at the given servings
  - "proteinG" (number, optional): grams of protein for the whole meal
  - "carbsG" (number, optional): grams of carbs for the whole meal
  - "fatG" (number, optional): grams of fat for the whole meal
''';

    try {
      if (familyId.isEmpty) {
        if (mounted) setState(() => _weekPlannerLoading = false);
        return;
      }
      final raw = await AiService.ask(prompt: '$systemPrompt\n\n$prompt', feature: 'ai_recipes', familyId: familyId);
      if (raw == null) {
        if (mounted) setState(() => _weekPlannerLoading = false);
        return;
      }
      context.read<AppProvider>().saveAiHistory(module: 'meals', prompt: 'Generate weekly meal plan', response: raw);
      final cleaned = _stripFences(raw);
      final decoded = jsonDecode(cleaned);
      if (decoded is! List) {
        if (mounted) setState(() => _weekPlannerLoading = false);
        return;
      }

      // Store for refinement
      _lastPlanJson = cleaned;
      _refineHistory.clear();

      final provider = context.read<AppProvider>();
      var dbState = provider.db;
      final userId = provider.activeUser?.id ?? '';

      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final dayNameToOffset = {
        'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
        'friday': 4, 'saturday': 5, 'sunday': 6,
      };

      final newRecipes = <Recipe>[];
      final newMealPlans = <MealPlanEntry>[];
      // Reuse existing recipes when AI repeats a title (normalized).
      final recipeIdByNormTitle = <String, String>{};
      for (final r in dbState.recipes.where((r) => r.familyId == familyId)) {
        final k = _recipeTitleNormKey(r.title);
        if (k.isNotEmpty) recipeIdByNormTitle[k] = r.id;
      }
      // Track ingredients for consolidation: key = "name|unit", value = total qty
      final ingredientMap = <String, _IngredientAccum>{};

      for (final dayData in decoded) {
        if (dayData is! Map<String, dynamic>) continue;
        final dayName = (dayData['dayName'] as String?)?.toLowerCase() ?? '';
        final offset = dayNameToOffset[dayName] ?? 0;
        final date = DateTime(monday.year, monday.month, monday.day + offset);

        final meals = dayData['meals'];
        if (meals is! List) continue;

        for (final meal in meals) {
          if (meal is! Map<String, dynamic>) continue;
          final mealType = (meal['type'] as String?)?.toLowerCase() ?? 'dinner';
          final mealName = meal['name']?.toString() ?? 'Untitled';

          // Build ingredients
          final ingredients = <RecipeIngredient>[];
          if (meal['ingredients'] is List) {
            for (final ing in meal['ingredients'] as List) {
              if (ing is Map<String, dynamic>) {
                final name = ing['name']?.toString() ?? '';
                final qty = ing['quantity']?.toString();
                final unit = ing['unit']?.toString();
                ingredients.add(RecipeIngredient(name: name, quantity: qty, unit: unit));

                // Consolidate: merge by name+unit key
                final key = '${name.toLowerCase()}|${(unit ?? '').toLowerCase()}';
                final numQty = double.tryParse(qty ?? '');
                if (ingredientMap.containsKey(key)) {
                  final existing = ingredientMap[key]!;
                  if (numQty != null && existing.numQty != null) {
                    existing.numQty = existing.numQty! + numQty;
                  }
                } else {
                  ingredientMap[key] = _IngredientAccum(name: name, unit: unit, numQty: numQty, rawQty: qty);
                }
              }
            }
          }

          // Build steps
          final steps = <String>[];
          if (meal['steps'] is List) {
            for (final s in meal['steps'] as List) {
              steps.add(s.toString());
            }
          }

          final norm = _recipeTitleNormKey(mealName);
          String recipeId;
          if (norm.isNotEmpty && recipeIdByNormTitle.containsKey(norm)) {
            recipeId = recipeIdByNormTitle[norm]!;
          } else {
            recipeId = const Uuid().v4();
            newRecipes.add(Recipe(
              id: recipeId,
              familyId: familyId,
              title: mealName,
              ingredients: ingredients,
              steps: steps,
              servings: (meal['servings'] is int) ? meal['servings'] as int : 4,
              tags: const ['meal-plan'],
              prepMinutes: (meal['prepMinutes'] as num?)?.toInt(),
              cookMinutes: (meal['cookMinutes'] as num?)?.toInt(),
              kcal: (meal['kcal'] as num?)?.toInt(),
              proteinG: (meal['proteinG'] as num?)?.toDouble() ?? (meal['protein_g'] as num?)?.toDouble(),
              carbsG: (meal['carbsG'] as num?)?.toDouble() ?? (meal['carbs_g'] as num?)?.toDouble(),
              fatG: (meal['fatG'] as num?)?.toDouble() ?? (meal['fat_g'] as num?)?.toDouble(),
              createdBy: userId,
            ));
            if (norm.isNotEmpty) recipeIdByNormTitle[norm] = recipeId;
          }

          // Create meal plan entry
          newMealPlans.add(MealPlanEntry(
            id: const Uuid().v4(),
            familyId: familyId,
            date: date,
            mealType: mealType,
            recipeId: recipeId,
            customMeal: mealName,
          ));
        }
      }

      // Save recipes and meal plans
      dbState = dbState.copyWith(
        recipes: [...dbState.recipes, ...newRecipes],
        mealPlans: [...dbState.mealPlans, ...newMealPlans],
      );

      // Create shopping list from consolidated ingredients
      if (ingredientMap.isNotEmpty) {
        // Build consolidated ingredient strings
        final consolidatedItems = ingredientMap.values.map((a) {
          final qtyStr = a.numQty != null
              ? (a.numQty! == a.numQty!.roundToDouble() ? a.numQty!.toInt().toString() : a.numQty!.toStringAsFixed(1))
              : a.rawQty;
          if (qtyStr != null && qtyStr.isNotEmpty) {
            return '$qtyStr${a.unit != null && a.unit!.isNotEmpty ? ' ${a.unit}' : ''} ${a.name}';
          }
          return a.name;
        }).toList();

        final listItems = consolidatedItems.map((ing) => ListItem(
          id: const Uuid().v4(),
          text: ing,
        )).toList();

        // Try AI categorization
        try {
          final categories = await AiService.categorizeItems(
            consolidatedItems.map((i) => i.split(' ').last).toList(),
            familyId: familyId,
          );
          for (var i = 0; i < listItems.length; i++) {
            final itemName = consolidatedItems[i].split(' ').last;
            final cat = categories[itemName];
            if (cat != null) {
              listItems[i] = listItems[i].copyWith(aiCategory: cat);
            }
          }
        } catch (_) {}

        final shoppingList = ShoppingList(
          id: const Uuid().v4(),
          familyId: familyId,
          creatorId: userId,
          title: 'Meal Plan Shopping - ${DateFormat('MMM d').format(monday)}',
          items: listItems,
          category: ListCategory.GROCERY,
        );
        dbState = dbState.copyWith(lists: [...dbState.lists, shoppingList]);
      }

      // Auto-create meal prep tasks for each day
      final mealTasks = <Task>[];
      for (final mp in newMealPlans) {
        final recipeName = mp.customMeal ??
            newRecipes.where((r) => r.id == mp.recipeId).firstOrNull?.title ??
            mp.mealType;
        mealTasks.add(Task(
          id: const Uuid().v4(),
          familyId: provider.activeFamily!.id,
          creatorId: provider.activeUser!.id,
          title: 'Prep ${mp.mealType}: $recipeName',
          dueDate: mp.date,
          tags: const ['meals', 'auto'],
        ));
      }
      dbState = dbState.copyWith(tasks: [...dbState.tasks, ...mealTasks]);

      await provider.saveAndSync(dbState);
      if (provider.activeFamily != null) await provider.syncTasksNow();

      try {
        NotificationService.notifyFamilyActivityWithDb(
          provider.db,
          title: 'New meal plan generated 🍽️',
          body: '${provider.activeUser?.name ?? 'Someone'} generated a meal plan for the week',
          path: '/meals',
          familyId: provider.activeFamily?.id,
          excludeUserId: provider.activeUser?.id,
        );
      } catch (_) {}

      if (mounted) {
        setState(() => _weekPlannerLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created ${newRecipes.length} recipes, ${newMealPlans.length} meal slots, ${mealTasks.length} tasks & shopping list!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Meals] week planner error: $e');
      if (mounted) {
        setState(() => _weekPlannerLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate meal plan. Please try again.'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  // ── Refine Meal Plan ──
  Future<void> _refineMealPlan() async {
    if (SubscriptionModal.guardAI(context)) return;
    final request = _refineController.text.trim();
    if (request.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe how to refine the plan'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_lastPlanJson == null) return;

    setState(() {
      _refineLoading = true;
      _refineHistory.add({'request': request, 'status': 'pending'});
    });
    _refineController.clear();

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() {
          _refineLoading = false;
          _refineHistory.last['status'] = 'error';
          _refineHistory.last['error'] = 'No active family';
        });
        return;
      }

      final raw = await AiService.refineWeeklyMealPlan(
        currentPlanJson: _lastPlanJson!,
        refinementRequest: request,
        familyId: familyId,
      );

      if (raw == null || !mounted) {
        if (mounted) setState(() {
          _refineLoading = false;
          _refineHistory.last['status'] = 'error';
          _refineHistory.last['error'] = 'AI failed to refine. Try again.';
        });
        return;
      }
      context.read<AppProvider>().saveAiHistory(module: 'meals', prompt: 'Refine meal plan: "$request"', response: raw);

      final cleaned = _stripFences(raw);
      final decoded = jsonDecode(cleaned);
      if (decoded is! List) {
        if (mounted) setState(() {
          _refineLoading = false;
          _refineHistory.last['status'] = 'error';
          _refineHistory.last['error'] = 'Invalid response from AI.';
        });
        return;
      }

      // Update stored plan
      _lastPlanJson = cleaned;

      // Re-process the refined plan (same logic as _generateWeekPlan)
      final provider = context.read<AppProvider>();
      var db = provider.db;
      final userId = provider.activeUser?.id ?? '';

      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final dayNameToOffset = {
        'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
        'friday': 4, 'saturday': 5, 'sunday': 6,
      };

      // Remove old meal-plan tagged recipes and entries for this week
      final weekStart = DateTime(monday.year, monday.month, monday.day);
      final weekEnd = weekStart.add(const Duration(days: 7));
      final oldPlanEntries = db.mealPlans.where((e) =>
        e.familyId == familyId &&
        e.date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
        e.date.isBefore(weekEnd),
      ).toList();
      final oldRecipeIds = oldPlanEntries.map((e) => e.recipeId).whereType<String>().toSet();

      db = db.copyWith(
        mealPlans: db.mealPlans.where((e) => !oldPlanEntries.contains(e)).toList(),
        recipes: db.recipes.where((r) => !oldRecipeIds.contains(r.id) || !r.tags.contains('meal-plan')).toList(),
      );

      final newRecipes = <Recipe>[];
      final newMealPlans = <MealPlanEntry>[];
      final recipeIdByNormTitleRefine = <String, String>{};
      for (final r in db.recipes.where((r) => r.familyId == familyId)) {
        final k = _recipeTitleNormKey(r.title);
        if (k.isNotEmpty) recipeIdByNormTitleRefine[k] = r.id;
      }

      for (final dayData in decoded) {
        if (dayData is! Map<String, dynamic>) continue;
        final dayName = (dayData['dayName'] as String?)?.toLowerCase() ?? '';
        final offset = dayNameToOffset[dayName] ?? 0;
        final date = DateTime(monday.year, monday.month, monday.day + offset);

        final meals = dayData['meals'];
        if (meals is! List) continue;

        for (final meal in meals) {
          if (meal is! Map<String, dynamic>) continue;
          final mealType = (meal['type'] as String?)?.toLowerCase() ?? 'dinner';
          final mealName = meal['name']?.toString() ?? 'Untitled';

          final ingredients = <RecipeIngredient>[];
          if (meal['ingredients'] is List) {
            for (final ing in meal['ingredients'] as List) {
              if (ing is Map<String, dynamic>) {
                ingredients.add(RecipeIngredient(
                  name: ing['name']?.toString() ?? '',
                  quantity: ing['quantity']?.toString(),
                  unit: ing['unit']?.toString(),
                ));
              }
            }
          }

          final steps = <String>[];
          if (meal['steps'] is List) {
            for (final s in meal['steps'] as List) {
              steps.add(s.toString());
            }
          }

          final normR = _recipeTitleNormKey(mealName);
          String recipeId;
          if (normR.isNotEmpty && recipeIdByNormTitleRefine.containsKey(normR)) {
            recipeId = recipeIdByNormTitleRefine[normR]!;
          } else {
            recipeId = const Uuid().v4();
            newRecipes.add(Recipe(
              id: recipeId,
              familyId: familyId,
              title: mealName,
              ingredients: ingredients,
              steps: steps,
              servings: (meal['servings'] is int) ? meal['servings'] as int : 4,
              tags: const ['meal-plan'],
              prepMinutes: (meal['prepMinutes'] as num?)?.toInt(),
              cookMinutes: (meal['cookMinutes'] as num?)?.toInt(),
              createdBy: userId,
            ));
            if (normR.isNotEmpty) recipeIdByNormTitleRefine[normR] = recipeId;
          }

          newMealPlans.add(MealPlanEntry(
            id: const Uuid().v4(),
            familyId: familyId,
            date: date,
            mealType: mealType,
            recipeId: recipeId,
            customMeal: mealName,
          ));
        }
      }

      db = db.copyWith(
        recipes: [...db.recipes, ...newRecipes],
        mealPlans: [...db.mealPlans, ...newMealPlans],
      );

      await provider.saveAndSync(db);

      try {
        NotificationService.notifyFamilyActivityWithDb(
          provider.db,
          title: 'Meal plan updated 🍽️',
          body: '${provider.activeUser?.name ?? 'Someone'} refined the meal plan',
          path: '/meals',
          familyId: provider.activeFamily?.id,
          excludeUserId: provider.activeUser?.id,
        );
      } catch (_) {}

      if (mounted) setState(() {
        _refineLoading = false;
        _refineHistory.last['status'] = 'done';
      });
    } catch (e) {
      debugPrint('[Meals] refine error: $e');
      if (mounted) setState(() {
        _refineLoading = false;
        _refineHistory.last['status'] = 'error';
        _refineHistory.last['error'] = 'Refinement failed. Try again.';
      });
    }
  }

  // ── Import from URL (inline) ──
  Future<void> _importFromUrl() async {
    if (SubscriptionModal.guardAI(context)) return;
    final url = _importUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a recipe URL'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _importLoading = true);

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() => _importLoading = false);
        return;
      }
      final result = await AiService.scrapeRecipe(url, familyId: familyId);
      if (result == null) {
        if (mounted) {
          setState(() => _importLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not extract recipe. Try a different URL.'), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }

      final provider = context.read<AppProvider>();
      final db = provider.db;
      final userId = provider.activeUser?.id ?? '';

      final ingredients = <RecipeIngredient>[];
      if (result['ingredients'] is List) {
        for (final ing in result['ingredients'] as List) {
          if (ing is Map<String, dynamic>) {
            ingredients.add(RecipeIngredient(
              name: ing['name']?.toString() ?? '',
              quantity: ing['amount']?.toString(),
              unit: ing['unit']?.toString(),
            ));
          } else if (ing is String) {
            ingredients.add(RecipeIngredient(name: ing));
          }
        }
      }
      final steps = <String>[];
      if (result['steps'] is List) {
        for (final s in result['steps'] as List) {
          steps.add(s.toString());
        }
      }

      final newRecipe = Recipe(
        id: const Uuid().v4(),
        familyId: familyId,
        title: result['title']?.toString() ?? 'Imported Recipe',
        ingredients: ingredients,
        steps: steps,
        servings: _parseInt(result['servings']),
        tags: const [],
        createdBy: userId,
      );

      await provider.saveAndSync(db.copyWith(recipes: [...db.recipes, newRecipe]));

      if (mounted) {
        setState(() { _importLoading = false; _importUrlController.clear(); });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${newRecipe.title}"!'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<void> _addPantryItem() async {
    final provider = context.read<AppProvider>();
    final fam = provider.activeFamily;
    if (fam == null) return;
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add pantry item', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Rice, Olive oil'),
              textCapitalization: TextCapitalization.sentences,
            ),
            TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity (optional)')),
            TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final db = provider.db;
    final item = PantryItem(
      id: const Uuid().v4(),
      familyId: fam.id,
      name: name,
      quantity: qtyCtrl.text.trim().isEmpty ? null : qtyCtrl.text.trim(),
      unit: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );
    await provider.saveAndSync(db.copyWith(pantryItems: [...db.pantryItems, item]));
  }

  Future<void> _removePantryItem(PantryItem item) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(
      db.copyWith(pantryItems: db.pantryItems.where((p) => p.id != item.id).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final weekLabel = '${DateFormat('MMM d').format(monday)} - ${DateFormat('MMM d').format(sunday)}';

    // ── Computed stats ──
    final recipes = provider.db.recipes.where((r) => r.familyId == familyId).toList();
    final mealsThisWeek = provider.db.mealPlans
        .where((m) => m.familyId == familyId && m.date.isAfter(monday.subtract(const Duration(days: 1))) && m.date.isBefore(sunday.add(const Duration(days: 1))))
        .length;
    final pantry = provider.db.pantryItems
        .where((p) => p.familyId == familyId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            PageHeader(
              title: '\u{1F37D}\u{FE0F} Meal Hub',
              subtitle: 'Plan nutrition and manage family recipes.',
              actions: [
                ActionChipButton(
                  icon: Icons.add_rounded,
                  label: 'Add Recipe',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) => const _AddRecipeSheet(),
                  ),
                  isPrimary: true,
                ),
              ],
            ),

            // ── Stat cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                _MiniStat(
                  icon: Icons.menu_book_rounded,
                  iconColor: AppTheme.primary,
                  value: '${recipes.length}',
                  label: 'Recipes',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.calendar_today_rounded,
                  iconColor: AppTheme.success,
                  value: '$mealsThisWeek',
                  label: 'This Week',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.restaurant_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  value: '${recipes.where((r) => r.tags.contains('family-favorite')).length}',
                  label: 'Favorites',
                ),
              ]),
            ),

            // ── Pantry staples ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pantry staples',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addPantryItem,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Track what you usually keep on hand. Helps when meal planning and shopping.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    if (pantry.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'No items yet — add rice, oil, spices, etc.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      )
                    else
                      ...pantry.map((p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                            subtitle: (p.quantity != null || p.unit != null)
                                ? Text(
                                    [p.quantity, p.unit].whereType<String>().where((s) => s.isNotEmpty).join(' '),
                                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12),
                                  )
                                : null,
                            trailing: IconButton(
                              tooltip: 'Remove ${p.name}',
                              icon: const Icon(Icons.delete_outline_rounded, size: 20),
                              onPressed: () => _removePantryItem(p),
                            ),
                          )),
                  ],
                ),
              ),
            ),

            // ── Tab chips ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppTabBar(
                tabs: const ['Weekly Plan', 'Recipe Box'],
                selectedIndex: _tabController.index,
                onSelected: (i) => _tabController.animateTo(i),
              ),
            ),

            const SizedBox(height: 16),

            // ── AI Tools Section Header ──
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 20, 10),
              child: Text('AI TOOLS', style: TextStyle(
                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
                color: AppTheme.stone400, letterSpacing: 1.2,
              )),
            ),

            // ── AI Chef Suggestion card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _AiFeatureCard(
                icon: Icons.restaurant_rounded,
                gradientColors: const [Color(0xFF16A34A), Color(0xFF0D9488)],
                title: 'AI Chef Suggestion',
                hintText: 'e.g. Quick dinner for 4, vegetarian...',
                controller: _chefController,
                loading: _chefLoading,
                buttonLabel: 'Suggest Meals',
                onAction: _chefLoading ? null : _generateChefSuggestion,
              ),
            ),

            // ── Chef Suggestion Results ──
            if (_chefSuggestions != null && _chefSuggestions!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _chefSuggestions!.map((s) {
                    final title = s['title']?.toString() ?? 'Recipe';
                    final summary = s['summary']?.toString() ?? '';
                    final ings = s['ingredients'] is List ? (s['ingredients'] as List).length : 0;
                    final prep = (s['prepMinutes'] as num?)?.toInt() ?? 0;
                    final cook = (s['cookMinutes'] as num?)?.toInt() ?? 0;
                    final totalMin = prep + cook;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 22))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone900)),
                                  if (summary.isNotEmpty)
                                    Text(summary, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.stone100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text('$ings items', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                                    ),
                                    if (totalMin > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.timer_outlined, size: 10, color: AppTheme.primary),
                                            const SizedBox(width: 3),
                                            Text('${totalMin}m', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => _saveChefRecipe(s),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text('Save', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white)),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 10),

            // ── Import from URL card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _AiFeatureCard(
                icon: Icons.link_rounded,
                gradientColors: const [Color(0xFF0D9488), Color(0xFF06B6D4)],
                title: 'Import from URL',
                hintText: 'Paste recipe URL...',
                controller: _importUrlController,
                loading: _importLoading,
                buttonLabel: 'Import Recipe',
                onAction: _importLoading ? null : _importFromUrl,
                keyboardType: TextInputType.url,
              ),
            ),

            const SizedBox(height: 10),

            // ── AI Week Planner card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AiFeatureCard(
                    icon: Icons.calendar_month_rounded,
                    gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                    title: 'AI Week Planner',
                    hintText: 'e.g. Healthy meals, budget-friendly...',
                    controller: _weekPlannerController,
                    loading: _weekPlannerLoading,
                    buttonLabel: 'Plan My Week',
                    onAction: _weekPlannerLoading ? null : _generateWeekPlan,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Pantry-first week'),
                        selected: _pantryFirstWeek,
                        onSelected: (v) => setState(() => _pantryFirstWeek = v),
                      ),
                      TextButton.icon(
                        onPressed: _showMacroTargetsDialog,
                        icon: const Icon(Icons.pie_chart_outline_rounded, size: 18),
                        label: const Text('Macro targets'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Refinement Input ──
            if (_lastPlanJson != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF6366F1)),
                        ),
                        const SizedBox(width: 8),
                        const Text('Refine your meal plan', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4338CA))),
                      ]),
                      const SizedBox(height: 10),
                      // History thread
                      if (_refineHistory.isNotEmpty) ...[
                        ..._refineHistory.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(entry['request'] as String, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: entry['status'] == 'done'
                                        ? const Color(0xFFD1FAE5)
                                        : entry['status'] == 'error'
                                            ? const Color(0xFFFEE2E2)
                                            : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: entry['status'] == 'done'
                                          ? const Color(0xFF86EFAC)
                                          : entry['status'] == 'error'
                                              ? const Color(0xFFFCA5A5)
                                              : AppTheme.stone200,
                                    ),
                                  ),
                                  child: entry['status'] == 'pending'
                                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF6366F1))),
                                          SizedBox(width: 6),
                                          Text('Updating plan...', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF6366F1))),
                                        ])
                                      : entry['status'] == 'done'
                                          ? const Text('Plan updated', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF166534)))
                                          : Text(entry['error'] as String? ?? 'Error', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFDC2626))),
                                ),
                              ),
                            ]),
                          );
                        }),
                        const SizedBox(height: 4),
                      ],
                      // Input row
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _refineController,
                            enabled: !_refineLoading,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'e.g. "Make Mondays vegetarian"',
                              hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.3))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF6366F1).withValues(alpha: 0.3))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _refineMealPlan(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _refineLoading ? null : _refineMealPlan,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _refineLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        'Change cuisine, swap ingredients, adjust dietary needs, and more.',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: const Color(0xFF6366F1).withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            const SizedBox(height: 20),

            // ── Tab content ──
            if (_tabController.index == 0) ...[
              // ── Detailed day-by-day planner ──
              const _MealPlanTab(),
            ] else ...[
              // ── RECIPE BOX section ──
              _RecipesTab(onCookMode: _openCookMode),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Meal Plan Section ────────────────────────────────────────────────────────

class _MealPlanTab extends StatefulWidget {
  const _MealPlanTab();

  @override
  State<_MealPlanTab> createState() => _MealPlanTabState();
}

class _MealPlanTabState extends State<_MealPlanTab> {
  late DateTime _selectedDay;
  late List<DateTime> _weekDays;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _weekDays = _buildWeek(_selectedDay);
  }

  List<DateTime> _buildWeek(DateTime day) {
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  void _goToPreviousWeek() {
    setState(() {
      _weekDays = _buildWeek(_weekDays.first.subtract(const Duration(days: 7)));
      _selectedDay = _weekDays.first;
    });
  }

  void _goToNextWeek() {
    setState(() {
      _weekDays = _buildWeek(_weekDays.first.add(const Duration(days: 7)));
      _selectedDay = _weekDays.first;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Recipe? _recipeFor(AppProvider provider, MealPlanEntry? m) {
    if (m?.recipeId == null) return null;
    for (final r in provider.db.recipes) {
      if (r.id == m!.recipeId) return r;
    }
    return null;
  }

  Map<String, double?> _macrosForDay(AppProvider provider, DateTime day) {
    final familyId = provider.activeFamily?.id ?? '';
    final meals = provider.db.mealPlans
        .where((m) => m.familyId == familyId && _isSameDay(m.date, day))
        .toList();
    final parts = <Map<String, double?>>[];
    for (final m in meals) {
      final r = _recipeFor(provider, m);
      parts.add(scaledMacrosForMeal(r, m.servings));
    }
    return aggregateMacros(parts);
  }

  Map<String, double?> _macrosForWeek(AppProvider provider) {
    final parts = <Map<String, double?>>[];
    for (final d in _weekDays) {
      parts.add(_macrosForDay(provider, d));
    }
    return aggregateMacros(parts);
  }

  String _fmtMacro(String label, double? v, String unit) {
    if (v == null) return '';
    final s = v >= 100 ? v.round().toString() : v.toStringAsFixed(0);
    return '$label $s$unit';
  }

  Future<void> _repeatMealWeekly(BuildContext context, MealPlanEntry source) async {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    if (familyId.isEmpty) return;
    final nextWeek = source.date.add(const Duration(days: 7));
    final exists = provider.db.mealPlans.any(
      (m) =>
          m.familyId == familyId &&
          _isSameDay(m.date, nextWeek) &&
          m.mealType == source.mealType,
    );
    if (exists) {
      _showSnack(context, 'That slot next week is already filled.');
      return;
    }
    final copy = MealPlanEntry(
      id: const Uuid().v4(),
      familyId: familyId,
      date: nextWeek,
      mealType: source.mealType,
      recipeId: source.recipeId,
      customMeal: source.customMeal,
      notes: source.notes,
      servings: source.servings,
      prepNotes: source.prepNotes,
      repeatRule: 'weekly_same_slot',
      sourceMealPlanId: source.id,
    );
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(mealPlans: [...db.mealPlans, copy]));
    if (context.mounted) _showSnack(context, 'Copied to ${DateFormat('EEE MMM d').format(nextWeek)}');
  }

  Future<void> _scheduleLeftovers(
    BuildContext context,
    MealPlanEntry source, {
    required String targetMealType,
    required DateTime targetDay,
  }) async {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    if (familyId.isEmpty) return;
    final exists = provider.db.mealPlans.any(
      (m) =>
          m.familyId == familyId &&
          _isSameDay(m.date, targetDay) &&
          m.mealType == targetMealType,
    );
    if (exists) {
      _showSnack(context, 'Target meal slot is already filled.');
      return;
    }
    final copy = MealPlanEntry(
      id: const Uuid().v4(),
      familyId: familyId,
      date: targetDay,
      mealType: targetMealType,
      recipeId: source.recipeId,
      customMeal: source.customMeal == null || source.customMeal!.isEmpty
          ? 'Leftovers: ${source.title}'
          : 'Leftovers: ${source.customMeal}',
      notes: source.notes,
      servings: source.servings,
      prepNotes: 'Leftovers from ${DateFormat('MMM d').format(source.date)}',
      leftoverMealPlanId: source.id,
    );
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(mealPlans: [...db.mealPlans, copy]));
    if (context.mounted) {
      _showSnack(context, 'Leftovers scheduled for ${DateFormat('EEE').format(targetDay)} $targetMealType');
    }
  }

  Future<void> _showLeftoverTargetPicker(BuildContext context, MealPlanEntry source) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Schedule leftovers for',
                style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            ListTile(
              title: const Text('Tomorrow — lunch'),
              onTap: () => Navigator.pop(ctx, 'tomorrow_lunch'),
            ),
            ListTile(
              title: const Text('Tomorrow — dinner'),
              onTap: () => Navigator.pop(ctx, 'tomorrow_dinner'),
            ),
            ListTile(
              title: const Text('Next day — same meal type'),
              onTap: () => Navigator.pop(ctx, 'nextday_same'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final tomorrow = DateTime(source.date.year, source.date.month, source.date.day)
        .add(const Duration(days: 1));
    if (choice == 'tomorrow_lunch') {
      await _scheduleLeftovers(context, source, targetMealType: 'lunch', targetDay: tomorrow);
    } else if (choice == 'tomorrow_dinner') {
      await _scheduleLeftovers(context, source, targetMealType: 'dinner', targetDay: tomorrow);
    } else if (choice == 'nextday_same') {
      await _scheduleLeftovers(context, source, targetMealType: source.mealType, targetDay: tomorrow);
    }
  }

  List<MealShoppingLine> _weekShopLines(BuildContext context) {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    if (familyId.isEmpty) return [];
    return linesFromMealPlans(
      familyId: familyId,
      meals: provider.db.mealPlans,
      recipes: provider.db.recipes,
      weekDays: _weekDays,
    );
  }

  Future<void> _addWeekIngredientsToGrocery(BuildContext context) async {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    if (familyId.isEmpty) return;
    final lines = _weekShopLines(context);
    if (lines.isEmpty) {
      _showSnack(context, 'Link meals to recipes (pick from Recipes) to build a list from ingredients.');
      return;
    }
    final userId = provider.activeUser?.id ?? '';
    final listItems = lines.map((l) {
      final q = (l.quantity != null && l.quantity!.trim().isNotEmpty)
          ? '${l.quantity!.trim()}${l.unit != null && l.unit!.trim().isNotEmpty ? ' ${l.unit!.trim()}' : ''}'
          : null;
      final text = (q != null && q.isNotEmpty) ? '$q ${l.name}' : l.name;
      return ListItem(id: const Uuid().v4(), text: text);
    }).toList();
    final title =
        'Week shop ${DateFormat('MMM d').format(_weekDays.first)}–${DateFormat('d').format(_weekDays.last)}';
    final list = ShoppingList(
      id: const Uuid().v4(),
      familyId: familyId,
      creatorId: userId,
      title: title,
      items: listItems,
      category: ListCategory.GROCERY,
    );
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(lists: [...db.lists, list]));
    if (context.mounted) {
      _showSnack(context, 'Added ${listItems.length} items to Lists');
    }
  }

  Future<void> _shareWeekShopList(BuildContext context) async {
    final lines = _weekShopLines(context);
    if (lines.isEmpty) {
      _showSnack(context, 'Link meals to recipes to export a grocery list.');
      return;
    }
    final buf = StringBuffer();
    buf.writeln(
      'Grocery list — week of ${DateFormat('MMM d').format(_weekDays.first)}–${DateFormat('d, y').format(_weekDays.last)}',
    );
    buf.writeln('');
    for (final l in lines) {
      final q = (l.quantity != null && l.quantity!.trim().isNotEmpty)
          ? '${l.quantity!.trim()}${l.unit != null && l.unit!.trim().isNotEmpty ? ' ${l.unit!.trim()}' : ''}'
          : null;
      buf.writeln((q != null && q.isNotEmpty) ? '• $q ${l.name}' : '• ${l.name}');
    }
    await Share.share(buf.toString().trim(), subject: 'Family grocery list');
  }

  Future<void> _shareWeekPlan(BuildContext context) async {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    if (familyId.isEmpty) return;
    final all = provider.db.mealPlans.where((m) => m.familyId == familyId).toList();
    final buf = StringBuffer();
    buf.writeln('Meal plan ${DateFormat('MMM d, y').format(_weekDays.first)} week');
    buf.writeln('');
    for (final day in _weekDays) {
      buf.writeln(DateFormat('EEEE, MMM d').format(day));
      for (final type in _mealTypes) {
        MealPlanEntry? m;
        try {
          m = all.firstWhere(
            (e) => _isSameDay(e.date, day) && e.mealType == type,
          );
        } catch (_) {
          m = null;
        }
        final label = _mealTypeLabels[type] ?? type;
        if (m == null) {
          buf.writeln('  $label: —');
        } else {
          var line = '  $label: ${m.title}';
          if (m.servings != null) line += ' (${m.servings} servings)';
          if (m.prepNotes != null && m.prepNotes!.trim().isNotEmpty) {
            line += '\n    Prep: ${m.prepNotes!.trim()}';
          }
          buf.writeln(line);
        }
      }
      buf.writeln('');
    }
    await Share.share(buf.toString().trim(), subject: 'Family meal plan');
  }

  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final mealsForDay = provider.db.mealPlans
        .where((m) => m.familyId == familyId && _isSameDay(m.date, _selectedDay))
        .toList();

    final weekLabel =
        '${DateFormat('MMM d').format(_weekDays.first)} – ${DateFormat('MMM d').format(_weekDays.last)}';

    final targets = mealMacroTargetsFromSettings(provider.activeFamily?.settings ?? {});
    final dayMacros = _macrosForDay(provider, _selectedDay);
    final weekMacros = _macrosForWeek(provider);
    String macroLine(Map<String, double?> m) {
      final bits = <String>[
        if (m['kcal'] != null) _fmtMacro('', m['kcal']!, ' kcal').replaceFirst(' ', ''),
        if (m['protein'] != null) _fmtMacro('P', m['protein']!, 'g'),
        if (m['carbs'] != null) _fmtMacro('C', m['carbs']!, 'g'),
        if (m['fat'] != null) _fmtMacro('F', m['fat']!, 'g'),
      ];
      return bits.isEmpty ? '—' : bits.join(' · ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 20, 10),
          child: Text('DAILY PLANNER', style: TextStyle(
            fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
            color: AppTheme.stone400, letterSpacing: 1.2,
          )),
        ),
        // Week navigation header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.stone500),
                onPressed: _goToPreviousWeek,
              ),
              Text(
                weekLabel,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  color: AppTheme.stone700,
                  fontSize: 14,
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.stone500),
                onPressed: _goToNextWeek,
              ),
            ],
          ),
        ),
        if (targets.isNotEmpty || weekMacros['kcal'] != null || weekMacros['protein'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.stone50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.stone200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nutrition (from recipes)',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.stone600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Week total: ${macroLine(weekMacros)}',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone700),
                  ),
                  if (targets.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Daily goals: '
                      '${targets['kcal'] != null ? '~${targets['kcal']!.round()} kcal' : '—'}'
                      '${targets['protein'] != null ? ' · P ~${targets['protein']!.round()}g' : ''}'
                      '${targets['carbs'] != null ? ' · C ~${targets['carbs']!.round()}g' : ''}'
                      '${targets['fat'] != null ? ' · F ~${targets['fat']!.round()}g' : ''}',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone500.withValues(alpha: 0.95)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        // Day selector
        SizedBox(
          height: 76,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: 7,
            itemBuilder: (context, i) {
              final day = _weekDays[i];
              final isSelected = _isSameDay(day, _selectedDay);
              final isToday = _isToday(day);
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : isToday
                            ? AppTheme.primaryLight
                            : AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : isToday
                              ? AppTheme.primary.withValues(alpha: 0.4)
                              : AppTheme.stone200,
                      width: isSelected || isToday ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('E').format(day).substring(0, 1),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white70 : AppTheme.stone500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.day.toString(),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : AppTheme.stone800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Selected day label
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, MMMM d').format(_selectedDay),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.stone800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Day total: ${_macroLine(dayMacros)}',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
              ),
            ],
          ),
        ),
        // Meal slots
        ..._mealTypes.map((type) {
          final meal = mealsForDay.cast<MealPlan?>().firstWhere(
                (m) => m?.mealType == type,
                orElse: () => null,
              );
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: _MealSlotCard(
              mealType: type,
              meal: meal,
              day: _selectedDay,
              onRepeatWeekly:
                  meal != null ? () => _repeatMealWeekly(context, meal!) : null,
              onScheduleLeftovers: meal != null
                  ? () => _showLeftoverTargetPicker(context, meal!)
                  : null,
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Add this week ingredients to grocery list',
                      button: true,
                      child: OutlinedButton.icon(
                        onPressed: () => _addWeekIngredientsToGrocery(context),
                        icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                        label: const Text('Week shop', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      label: 'Share grocery list text for this week',
                      button: true,
                      child: OutlinedButton.icon(
                        onPressed: () => _shareWeekShopList(context),
                        icon: const Icon(Icons.list_alt_rounded, size: 18),
                        label: const Text('Share list', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Share meal plan for this week',
                button: true,
                child: OutlinedButton.icon(
                  onPressed: () => _shareWeekPlan(context),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share week plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MealSlotCard extends StatelessWidget {
  final String mealType;
  final MealPlan? meal;
  final DateTime day;
  final VoidCallback? onRepeatWeekly;
  final VoidCallback? onScheduleLeftovers;

  const _MealSlotCard({
    required this.mealType,
    required this.meal,
    required this.day,
    this.onRepeatWeekly,
    this.onScheduleLeftovers,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    Recipe? linkedRecipe;
    if (meal?.recipeId != null) {
      for (final r in provider.db.recipes) {
        if (r.id == meal!.recipeId) {
          linkedRecipe = r;
          break;
        }
      }
    }
    final macros = scaledMacrosForMeal(linkedRecipe, meal?.servings);
    final kcal = macros['kcal'];
    final hasMacros = kcal != null ||
        macros['protein'] != null ||
        macros['carbs'] != null ||
        macros['fat'] != null;

    final emoji = _mealTypeEmojis[mealType] ?? '🍽️';
    final label = _mealTypeLabels[mealType] ?? mealType;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: meal != null
            ? () => _showMealOptions(context)
            : () => _openAddMealSheet(context, mealType, day),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: meal != null ? AppTheme.surface : AppTheme.stone50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: meal != null ? AppTheme.stone100 : AppTheme.stone200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: meal != null ? AppTheme.primaryLight : AppTheme.stone100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (meal != null) ...[
                      Text(
                        meal!.title,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.stone900,
                        ),
                      ),
                      if (meal!.servings != null)
                        Text(
                          '${meal!.servings} servings',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppTheme.stone400,
                          ),
                        ),
                      if (meal!.prepNotes != null && meal!.prepNotes!.trim().isNotEmpty)
                        Text(
                          meal!.prepNotes!.trim(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppTheme.stone500,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (meal!.notes != null && meal!.notes!.isNotEmpty)
                        Text(
                          meal!.notes!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.stone500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (hasMacros)
                        Text(
                          [
                            if (kcal != null) '${kcal.round()} kcal',
                            if (macros['protein'] != null) 'P ${macros['protein']!.toStringAsFixed(0)}g',
                            if (macros['carbs'] != null) 'C ${macros['carbs']!.toStringAsFixed(0)}g',
                            if (macros['fat'] != null) 'F ${macros['fat']!.toStringAsFixed(0)}g',
                          ].join(' · '),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: AppTheme.stone400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (meal!.repeatRule != null && meal!.repeatRule!.isNotEmpty)
                        Text(
                          meal!.repeatRule == 'weekly_same_slot'
                              ? 'Repeats weekly'
                              : meal!.repeatRule == 'daily'
                                  ? 'Repeats daily'
                                  : 'Repeat: ${meal!.repeatRule}',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFF6366F1)),
                        ),
                      if (meal!.leftoverMealPlanId != null)
                        const Text(
                          'Leftovers',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                        ),
                    ] else
                      Text(
                        '+ Add meal',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              if (meal != null)
                const Icon(Icons.more_horiz_rounded, color: AppTheme.stone400, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showMealOptions(BuildContext context) {
    final emoji = _mealTypeEmojis[mealType] ?? '🍽️';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            // Header with meal info
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(meal!.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
                    Text(
                      '${_mealTypeLabels[mealType] ?? mealType} · ${DateFormat('MMM d').format(day)}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                    ),
                  ]),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppTheme.stone100),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
              ),
              title: const Text('Edit Meal', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _openAddMealSheet(context, mealType, day, existingMeal: meal);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFF8B5CF6)),
              ),
              title: const Text('AI Swap Meal', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _aiSwapMeal(context);
              },
            ),
            if (onRepeatWeekly != null)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.repeat_rounded, size: 18, color: Color(0xFF6366F1)),
                ),
                title: const Text('Repeat next week', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Copy to same weekday + meal slot', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  onRepeatWeekly!();
                },
              ),
            if (onScheduleLeftovers != null)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.takeout_dining_rounded, size: 18, color: Color(0xFF16A34A)),
                ),
                title: const Text('Schedule leftovers', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  onScheduleLeftovers!();
                },
              ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
              ),
              title: const Text('Delete Meal', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteMeal(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMeal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
          ),
          const SizedBox(width: 10),
          const Text('Delete Meal', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: Text(
          'Remove "${meal!.title}" from your plan? This cannot be undone.',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updated = db.mealPlans.where((m) => m.id != meal!.id).toList();
    provider.saveAndSync(db.copyWith(mealPlans: updated));
    if (context.mounted) _showSnack(context, 'Meal removed');
  }

  Future<void> _aiSwapMeal(BuildContext context) async {
    if (SubscriptionModal.guardAI(context)) return;
    final currentMealName = meal!.title;
    final label = _mealTypeLabels[mealType] ?? mealType;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF8B5CF6)))),
            ),
            const SizedBox(height: 16),
            Text('Finding a swap for "$currentMealName"...', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone700)),
          ],
        ),
      ),
    );

    final localeService = context.read<LocaleService>();
    final unitInstruction = localeService.config.useMetric
        ? 'Use metric units (grams, kilograms, millilitres, litres). No imperial units.'
        : 'Use standard US units (cups, tablespoons, ounces, pounds).';

    const systemPrompt =
        'You are a meal swap AI. Always respond with valid JSON only, no markdown fences.';
    final prompt = '''
Suggest a replacement for this ${label.toLowerCase()} meal: "$currentMealName"

$unitInstruction

Return a JSON object with:
- "name" (string): new meal name
- "ingredients" (array of objects with "name", "quantity", "unit")
- "steps" (array of strings)
- "servings" (integer)

The replacement should be similar in style but different. Keep it healthy and family-friendly.
''';

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) return;
      final raw = await AiService.ask(prompt: '$systemPrompt\n\n$prompt', feature: 'ai_recipes', familyId: familyId);
      if (!context.mounted) return;
      Navigator.pop(context); // dismiss loading

      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate swap. Try again.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      context.read<AppProvider>().saveAiHistory(module: 'meals', prompt: 'Swap meal: "$currentMealName"', response: raw);

      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(cleaned.indexOf('\n') + 1);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.lastIndexOf('```'));
      cleaned = cleaned.trim();

      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) return;

      final newName = decoded['name']?.toString() ?? 'Swapped Meal';
      final swapServings = (decoded['servings'] is int) ? decoded['servings'] as int : int.tryParse(decoded['servings']?.toString() ?? '');

      final provider = context.read<AppProvider>();
      final db = provider.db;
      final userId = provider.activeUser?.id ?? '';

      final existingSwap = _findRecipeByNormTitle(db.recipes, familyId, newName);
      String? recipeIdForMeal = existingSwap?.id;
      List<Recipe> nextRecipes = List<Recipe>.from(db.recipes);

      if (recipeIdForMeal == null) {
        final ingredients = <RecipeIngredient>[];
        if (decoded['ingredients'] is List) {
          for (final ing in decoded['ingredients'] as List) {
            if (ing is Map<String, dynamic>) {
              ingredients.add(RecipeIngredient(
                name: ing['name']?.toString() ?? '',
                quantity: ing['quantity']?.toString(),
                unit: ing['unit']?.toString(),
              ));
            }
          }
        }
        final steps = <String>[];
        if (decoded['steps'] is List) {
          for (final s in decoded['steps'] as List) steps.add(s.toString());
        }
        recipeIdForMeal = const Uuid().v4();
        nextRecipes.add(Recipe(
          id: recipeIdForMeal,
          familyId: familyId,
          title: newName,
          ingredients: ingredients,
          steps: steps,
          servings: (decoded['servings'] is int) ? decoded['servings'] as int : 4,
          tags: const ['ai-swap'],
          createdBy: userId,
        ));
      }

      final updated = db.mealPlans.map((m) {
        if (m.id == meal!.id) {
          return m.copyWith(
            customMeal: newName,
            recipeId: recipeIdForMeal,
            servings: swapServings ?? m.servings,
          );
        }
        return m;
      }).toList();

      await provider.saveAndSync(db.copyWith(
        mealPlans: updated,
        recipes: nextRecipes,
      ));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Swapped to "$newName"!'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // dismiss loading if still showing
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Swap failed. Please try again.'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _openAddMealSheet(BuildContext context, String type, DateTime day,
      {MealPlan? existingMeal}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AddMealSheet(
        mealType: type,
        day: day,
        existingMeal: existingMeal,
      ),
    );
  }
}

// ─── Add Meal Sheet ───────────────────────────────────────────────────────────

class _AddMealSheet extends StatefulWidget {
  final String mealType;
  final DateTime day;
  final MealPlan? existingMeal;

  const _AddMealSheet({
    required this.mealType,
    required this.day,
    this.existingMeal,
  });

  @override
  State<_AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<_AddMealSheet> {
  late String _selectedType;
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _servingsController = TextEditingController();
  final _prepController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.mealType;
    if (widget.existingMeal != null) {
      _titleController.text = widget.existingMeal!.title;
      _notesController.text = widget.existingMeal!.notes ?? '';
      if (widget.existingMeal!.servings != null) {
        _servingsController.text = widget.existingMeal!.servings!.toString();
      }
      _prepController.text = widget.existingMeal!.prepNotes ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _servingsController.dispose();
    _prepController.dispose();
    super.dispose();
  }

  Future<void> _pickFromRecipes() async {
    final provider = context.read<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final recipes = provider.db.recipes
        .where((r) => r.familyId == familyId)
        .toList();

    final picked = await showModalBottomSheet<Recipe>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _RecipePickerSheet(recipes: recipes),
    );

    if (picked != null) {
      setState(() => _titleController.text = picked.title);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final userId = provider.activeUser?.id ?? '';
    final familyId = provider.activeFamily?.id ?? '';

    final servings = int.tryParse(_servingsController.text.trim());
    final prep = _prepController.text.trim().isEmpty ? null : _prepController.text.trim();

    if (widget.existingMeal != null) {
      final updated = widget.existingMeal!.copyWith(
        mealType: _selectedType,
        customMeal: _titleController.text.trim(),
        servings: servings,
        prepNotes: prep,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      final meals =
          db.mealPlans.map((m) => m.id == updated.id ? updated : m).toList();
      await provider.saveAndSync(db.copyWith(mealPlans: meals));
    } else {
      final newMeal = MealPlan(
        id: const Uuid().v4(),
        familyId: familyId,
        date: widget.day,
        mealType: _selectedType,
        customMeal: _titleController.text.trim(),
        servings: servings,
        prepNotes: prep,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      final meals = [...db.mealPlans, newMeal];
      await provider.saveAndSync(db.copyWith(mealPlans: meals));
      try {
        NotificationService.notifyFamilyActivityWithDb(
          provider.db,
          title: 'New meal added 🍽️',
          body: '${provider.activeUser?.name ?? 'Someone'} added a meal to the plan',
          path: '/meals',
          familyId: provider.activeFamily?.id,
          excludeUserId: provider.activeUser?.id,
        );
      } catch (_) {}
    }

    if (mounted) Navigator.pop(context);
  }

  InputDecoration _inputDecor(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone500),
        filled: true,
        fillColor: AppTheme.stone50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom + 16;
    final emoji = _mealTypeEmojis[widget.mealType] ?? '🍽️';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 8),
          // Header with icon badge
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Text(
              widget.existingMeal != null ? 'Edit Meal' : 'Add Meal',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
            ),
          ]),
          const SizedBox(height: 18),
          // Section label
          const Text('MEAL TYPE', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _mealTypes.map((type) {
                final selected = _selectedType == type;
                return GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : AppTheme.stone100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${_mealTypeEmojis[type]} ${_mealTypeLabels[type]}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppTheme.stone700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Section label
          const Text('DETAILS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 15),
            decoration: _inputDecor('Meal title'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _servingsController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            decoration: _inputDecor('Servings (optional, for shopping math)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _prepController,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            decoration: _inputDecor('Prep ahead (optional)'),
          ),
          const SizedBox(height: 10),
          // Pick from recipes
          GestureDetector(
            onTap: _pickFromRecipes,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book_outlined, size: 14, color: AppTheme.primary),
                ),
                const SizedBox(width: 8),
                const Text('Pick from Recipes', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            decoration: _inputDecor('Notes (optional)'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      widget.existingMeal != null ? 'Update Meal' : 'Save Meal',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recipe Picker Sheet ──────────────────────────────────────────────────────

class _RecipePickerSheet extends StatefulWidget {
  final List<Recipe> recipes;
  const _RecipePickerSheet({required this.recipes});

  @override
  State<_RecipePickerSheet> createState() => _RecipePickerSheetState();
}

class _RecipePickerSheetState extends State<_RecipePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.recipes
        .where((r) => r.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: [
          const SheetHandle(),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Center(child: Icon(Icons.menu_book_rounded, size: 20, color: AppTheme.primary)),
            ),
            const SizedBox(width: 10),
            const Text('Pick a Recipe', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
          ]),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search recipes...',
              hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
              prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.stone400),
              filled: true,
              fillColor: AppTheme.stone50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🍽️', style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 8),
                      Text(
                        _query.isEmpty ? 'No recipes yet' : 'No matches',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone400),
                      ),
                    ]),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppTheme.stone100),
                    itemBuilder: (ctx, i) {
                      final r = filtered[i];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Center(
                            child: Text(_recipeEmoji(r), style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                        title: Text(r.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone800)),
                        subtitle: r.tags.isNotEmpty
                            ? Text(r.tags.take(2).join(', '), style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400))
                            : null,
                        onTap: () => Navigator.pop(ctx, r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Recipe Box Section ───────────────────────────────────────────────────────

class _RecipesTab extends StatefulWidget {
  final void Function(Recipe recipe) onCookMode;
  const _RecipesTab({required this.onCookMode});

  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final t = _searchCtrl.text;
      _searchDebounce.run(() {
        if (mounted) setState(() => _query = t);
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final q = _query.trim().toLowerCase();
    final recipes = provider.db.recipes
        .where((r) =>
            r.familyId == familyId &&
            (q.isEmpty ||
                r.title.toLowerCase().contains(q) ||
                r.tags.any((t) => t.toLowerCase().contains(q))))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 20, 10),
          child: Text('YOUR RECIPES', style: TextStyle(
            fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
            color: AppTheme.stone400, letterSpacing: 1.2,
          )),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search recipes...',
              hintStyle: const TextStyle(fontFamily: 'Inter', color: AppTheme.stone400),
              prefixIcon: const Icon(Icons.search, color: AppTheme.stone400, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.stone400),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: AppTheme.stone50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        // Recipe grid
        if (recipes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OnboardingCard(
              emoji: '🍽️',
              title: _query.isEmpty ? 'No Recipes Yet' : 'No Matches',
              bullets: _query.isEmpty
                  ? const [
                      'Save family recipes in one place',
                      'Import from URLs or generate with AI',
                      'Add recipes to your weekly meal plan',
                    ]
                  : const ['Try a different search term'],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: recipes.length,
              itemBuilder: (ctx, i) => _RecipeCard(
                    recipe: recipes[i],
                    onCookMode: () => widget.onCookMode(recipes[i]),
                  ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─── Recipe Card ──────────────────────────────────────────────────────────────

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onCookMode;
  const _RecipeCard({required this.recipe, required this.onCookMode});

  String _timeLabel() {
    final total = (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0);
    if (total == 0) return '';
    if (total < 60) return '${total}m';
    final h = total ~/ 60;
    final m = total % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = _timeLabel();
    final emoji = _recipeEmoji(recipe);

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _RecipeDetailSheet(recipe: recipe, onCookMode: onCookMode),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone100),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / placeholder
            SizedBox(
              height: 100,
              width: double.infinity,
              child: recipe.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: recipe.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _EmojiPlaceholder(emoji),
                      placeholder: (_, __) => Container(
                        color: AppTheme.stone100,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    )
                  : _EmojiPlaceholder(emoji),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (timeLabel.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, size: 10, color: AppTheme.primary),
                                const SizedBox(width: 2),
                                Text(timeLabel, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                              ],
                            ),
                          ),
                        if (recipe.servings != null && recipe.servings! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.stone100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${recipe.servings} srv',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone500),
                            ),
                          ),
                      ],
                    ),
                    if (recipe.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: recipe.tags.take(2).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.stone100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(tag, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone500)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPlaceholder extends StatelessWidget {
  final String emoji;
  const _EmojiPlaceholder(this.emoji);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryLight,
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 40)),
      ),
    );
  }
}

String _recipeEmoji(Recipe r) {
  for (final tag in r.tags) {
    if (_tagEmojis.containsKey(tag.toLowerCase())) {
      return _tagEmojis[tag.toLowerCase()]!;
    }
  }
  return '🍽️';
}

// ─── Recipe Detail Sheet ──────────────────────────────────────────────────────

class _RecipeDetailSheet extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onCookMode;
  const _RecipeDetailSheet({required this.recipe, required this.onCookMode});

  String _totalTime() {
    final total = (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0);
    if (total == 0) return '—';
    if (total < 60) return '${total} min';
    final h = total ~/ 60;
    final m = total % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SheetHandle(),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  // Hero image or placeholder
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: recipe.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: recipe.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _EmojiPlaceholder(_recipeEmoji(recipe)),
                            )
                          : _EmojiPlaceholder(_recipeEmoji(recipe)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Title & edit/delete row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          recipe.title,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.stone900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                            ),
                            builder: (_) => _AddRecipeSheet(existingRecipe: recipe),
                          );
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.stone100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.stone500),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: Row(children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: AppTheme.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                                ),
                                const SizedBox(width: 10),
                                const Text('Delete Recipe', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
                              ]),
                              content: Text(
                                'Delete "${recipe.title}"? This cannot be undone.',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, color: AppTheme.stone500))),
                                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppTheme.error))),
                              ],
                            ),
                          );
                          if (confirmed == true && context.mounted) {
                            final db = provider.db;
                            final updated = db.recipes.where((r) => r.id != recipe.id).toList();
                            provider.saveAndSync(db.copyWith(recipes: updated));
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) _showSnack(context, 'Recipe deleted');
                          }
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.error),
                        ),
                      ),
                    ],
                  ),
                  if (recipe.description != null && recipe.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      recipe.description!,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone600, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Info chips row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (recipe.prepMinutes != null)
                        _InfoChip(icon: Icons.hourglass_top_outlined, label: 'Prep: ${recipe.prepMinutes}m'),
                      if (recipe.cookMinutes != null)
                        _InfoChip(icon: Icons.local_fire_department_outlined, label: 'Cook: ${recipe.cookMinutes}m'),
                      if ((recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0) > 0)
                        _InfoChip(icon: Icons.timer_outlined, label: 'Total: ${_totalTime()}'),
                      if (recipe.servings != null)
                        _InfoChip(icon: Icons.people_outline, label: '${recipe.servings} servings'),
                    ],
                  ),
                  if (recipe.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: recipe.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(tag, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                    ),
                  ],
                  if (recipe.ingredients.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('INGREDIENTS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    ...recipe.ingredients.map((ing) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6, height: 6,
                                margin: const EdgeInsets.only(top: 7, right: 10),
                                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                              ),
                              Expanded(
                                child: Text(
                                  '${ing.amount != null ? '${ing.amount} ' : ''}${ing.unit != null ? '${ing.unit} ' : ''}${ing.name}',
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone700, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                  if (recipe.steps.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('INSTRUCTIONS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    ...recipe.steps.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final step = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 26, height: 26,
                              margin: const EdgeInsets.only(right: 12, top: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text('$idx', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                            Expanded(
                              child: Text(step, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone700, height: 1.5)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 20),
                  if (recipe.steps.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onCookMode();
                        },
                        icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                        label: const Text('Cook mode', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Add to Meal Plan button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          builder: (c) => _AddMealSheet(
                            mealType: 'dinner',
                            day: DateTime.now(),
                            existingMeal: null,
                          ),
                        );
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: const Text('Add to Meal Plan', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-screen step-by-step view (large type, swipe between steps).
class _CookModeScreen extends StatefulWidget {
  final Recipe recipe;
  const _CookModeScreen({required this.recipe});

  @override
  State<_CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<_CookModeScreen> {
  late final PageController _pageCtrl;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.recipe.steps.where((s) => s.trim().isNotEmpty).toList();
    if (steps.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.recipe.title)),
        body: const Center(child: Text('No steps for this recipe.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Text(
                  'Step ${_index + 1} of ${steps.length}',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone500),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: steps.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (ctx, i) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Semantics(
                    header: true,
                    label: 'Step ${i + 1}',
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: AppTheme.stone800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _index > 0
                        ? () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut)
                        : null,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _index < steps.length - 1
                        ? () => _pageCtrl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut)
                        : () => Navigator.pop(context),
                    child: Text(_index < steps.length - 1 ? 'Next' : 'Done'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.stone50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.stone200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.stone500),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone600)),
        ],
      ),
    );
  }
}

// ─── Import URL Dialog ────────────────────────────────────────────────────────

class _ImportUrlDialog extends StatefulWidget {
  const _ImportUrlDialog();

  @override
  State<_ImportUrlDialog> createState() => _ImportUrlDialogState();
}

class _ImportUrlDialogState extends State<_ImportUrlDialog> {
  final _urlController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (SubscriptionModal.guardAI(context)) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a recipe URL'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() { _loading = false; _error = 'No active family'; });
        return;
      }
      final result = await AiService.scrapeRecipe(url, familyId: familyId);
      if (result == null) {
        setState(() {
          _error = 'Could not extract recipe. Try a different URL.';
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      final provider = context.read<AppProvider>();
      final db = provider.db;
      final userId = provider.activeUser?.id ?? '';

      final ingredients = <RecipeIngredient>[];
      if (result['ingredients'] is List) {
        for (final ing in result['ingredients'] as List) {
          if (ing is Map<String, dynamic>) {
            ingredients.add(RecipeIngredient(
              name: ing['name']?.toString() ?? '',
              quantity: ing['amount']?.toString(),
              unit: ing['unit']?.toString(),
            ));
          } else if (ing is String) {
            ingredients.add(RecipeIngredient(name: ing));
          }
        }
      }

      final steps = <String>[];
      if (result['steps'] is List) {
        for (final s in result['steps'] as List) {
          steps.add(s.toString());
        }
      }

      final newRecipe = Recipe(
        id: const Uuid().v4(),
        familyId: familyId,
        title: result['title']?.toString() ?? 'Imported Recipe',
        description: result['description']?.toString(),
        ingredients: ingredients,
        steps: steps,
        prepMinutes: _parseInt(result['prepMinutes']),
        cookMinutes: _parseInt(result['cookMinutes']),
        servings: _parseInt(result['servings']),
        tags: const [],
        sourceUrl: url,
        createdBy: userId,
      );

      await provider.saveAndSync(
          db.copyWith(recipes: [...db.recipes, newRecipe]));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.link_rounded, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          const Text('Import Recipe', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Paste the URL of a recipe page and we\'ll extract it for you.',
            style: TextStyle(fontSize: 13, color: AppTheme.stone600),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Recipe URL',
              hintText: 'https://...',
              filled: true,
              fillColor: AppTheme.stone50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.stone200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _import,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}

// ─── Add Recipe Sheet ─────────────────────────────────────────────────────────

class _AddRecipeSheet extends StatefulWidget {
  final Recipe? existingRecipe;
  const _AddRecipeSheet({this.existingRecipe});

  @override
  State<_AddRecipeSheet> createState() => _AddRecipeSheetState();
}

class _AddRecipeSheetState extends State<_AddRecipeSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _prepController = TextEditingController();
  final _cookController = TextEditingController();
  final _servingsController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();

  final List<_IngredientRow> _ingredients = [];
  final List<TextEditingController> _steps = [];
  final List<String> _selectedTags = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRecipe;
    if (r != null) {
      _titleController.text = r.title;
      _descController.text = r.description ?? '';
      _prepController.text = r.prepMinutes?.toString() ?? '';
      _cookController.text = r.cookMinutes?.toString() ?? '';
      _servingsController.text = r.servings?.toString() ?? '';
      if (r.kcal != null) _kcalController.text = r.kcal!.toString();
      if (r.proteinG != null) _proteinController.text = r.proteinG!.toString();
      if (r.carbsG != null) _carbsController.text = r.carbsG!.toString();
      if (r.fatG != null) _fatController.text = r.fatG!.toString();
      if (r.fiberG != null) _fiberController.text = r.fiberG!.toString();
      _ingredients.addAll(r.ingredients.map((i) => _IngredientRow(
            nameController: TextEditingController(text: i.name),
            amountController: TextEditingController(text: i.amount),
            unitController: TextEditingController(text: i.unit ?? ''),
          )));
      _steps.addAll(
          r.steps.map((s) => TextEditingController(text: s)));
      _selectedTags.addAll(r.tags);
    }
    if (_ingredients.isEmpty) _addIngredient();
    if (_steps.isEmpty) _addStep();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _prepController.dispose();
    _cookController.dispose();
    _servingsController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    for (final ing in _ingredients) {
      ing.nameController.dispose();
      ing.amountController.dispose();
      ing.unitController.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  void _addIngredient() {
    setState(() {
      _ingredients.add(_IngredientRow(
        nameController: TextEditingController(),
        amountController: TextEditingController(),
        unitController: TextEditingController(),
      ));
    });
  }

  void _removeIngredient(int index) {
    final row = _ingredients[index];
    row.nameController.dispose();
    row.amountController.dispose();
    row.unitController.dispose();
    setState(() => _ingredients.removeAt(index));
  }

  void _addStep() {
    setState(() => _steps.add(TextEditingController()));
  }

  void _removeStep(int index) {
    _steps[index].dispose();
    setState(() => _steps.removeAt(index));
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final userId = provider.activeUser?.id ?? '';
    final familyId = provider.activeFamily?.id ?? '';

    final ingredients = _ingredients
        .where((row) => row.nameController.text.trim().isNotEmpty)
        .map((row) => RecipeIngredient(
              name: row.nameController.text.trim(),
              quantity: row.amountController.text.trim().isEmpty ? null : row.amountController.text.trim(),
              unit: row.unitController.text.trim().isEmpty ? null : row.unitController.text.trim(),
            ))
        .toList();

    final steps = _steps
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    int? pInt(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      return int.tryParse(t);
    }

    double? pDbl(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    if (widget.existingRecipe != null) {
      final updated = widget.existingRecipe!.copyWith(
        title: _titleController.text.trim(),
        ingredients: ingredients,
        steps: steps,
        servings: int.tryParse(_servingsController.text),
        tags: List.from(_selectedTags),
        kcal: pInt(_kcalController.text),
        proteinG: pDbl(_proteinController.text),
        carbsG: pDbl(_carbsController.text),
        fatG: pDbl(_fatController.text),
        fiberG: pDbl(_fiberController.text),
      );
      final recipes = db.recipes
          .map((r) => r.id == updated.id ? updated : r)
          .toList();
      await provider.saveAndSync(db.copyWith(recipes: recipes));
    } else {
      final newRecipe = Recipe(
        id: const Uuid().v4(),
        familyId: familyId,
        title: _titleController.text.trim(),
        ingredients: ingredients,
        steps: steps,
        servings: int.tryParse(_servingsController.text),
        tags: List.from(_selectedTags),
        kcal: pInt(_kcalController.text),
        proteinG: pDbl(_proteinController.text),
        carbsG: pDbl(_carbsController.text),
        fatG: pDbl(_fatController.text),
        fiberG: pDbl(_fiberController.text),
        createdBy: userId,
      );
      await provider.saveAndSync(
          db.copyWith(recipes: [...db.recipes, newRecipe]));
    }

    if (mounted) Navigator.pop(context);
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
        filled: true,
        fillColor: AppTheme.stone50,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.stone200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.stone200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom + 16;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(child: Text('🍽️', style: TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.existingRecipe != null ? 'Edit Recipe' : 'Add Recipe',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppTheme.stone400),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 8, 20, padding),
                children: [
                  // Title
                  const Text('BASIC INFO', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: _fieldDecoration('Recipe Title *'),
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  // Description
                  TextField(
                    controller: _descController,
                    maxLines: 2,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                    decoration: _fieldDecoration('Description'),
                  ),
                  const SizedBox(height: 14),
                  // Time & servings row
                  const Text('TIMING', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _prepController,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration('Prep (min)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _cookController,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration('Cook (min)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _servingsController,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration('Servings'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('NUTRITION (full recipe)', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Text(
                    'Shown on the planner scaled by servings vs recipe servings.',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _kcalController,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration('kcal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _proteinController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _fieldDecoration('Protein g'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _carbsController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _fieldDecoration('Carbs g'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _fatController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _fieldDecoration('Fat g'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _fiberController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _fieldDecoration('Fiber g'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Ingredients section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('INGREDIENTS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
                      TextButton.icon(
                        onPressed: _addIngredient,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._ingredients.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row.nameController,
                              decoration: _fieldDecoration('Ingredient'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row.amountController,
                              decoration: _fieldDecoration('Amount'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row.unitController,
                              decoration: _fieldDecoration('Unit'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppTheme.error, size: 20),
                            onPressed: _ingredients.length > 1
                                ? () => _removeIngredient(i)
                                : null,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  // Steps section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('STEPS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
                      TextButton.icon(
                        onPressed: _addStep,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ..._steps.asMap().entries.map((entry) {
                    final i = entry.key;
                    final ctrl = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(top: 10, right: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              maxLines: 2,
                              decoration: _fieldDecoration('Step ${i + 1}'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppTheme.error, size: 20),
                            onPressed: _steps.length > 1
                                ? () => _removeStep(i)
                                : null,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  // Tags section
                  const Text('TAGS', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.stone400, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _availableTags.map((tag) {
                      final selected = _selectedTags.contains(tag);
                      final tagEmoji = _tagEmojis[tag];
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (selected) {
                            _selectedTags.remove(tag);
                          } else {
                            _selectedTags.add(tag);
                          }
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primary : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200),
                          ),
                          child: Text(
                            '${tagEmoji != null ? '$tagEmoji ' : ''}$tag',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : AppTheme.stone600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(
                              widget.existingRecipe != null ? 'Update Recipe' : 'Save Recipe',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Ingredient Row Model ─────────────────────────────────────────────────────

class _IngredientRow {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController unitController;

  _IngredientRow({
    required this.nameController,
    required this.amountController,
    required this.unitController,
  });
}

// ─── Mini Stat Card ───────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(
                    fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w900, color: iconColor,
                  )),
                  Text(label, style: const TextStyle(
                    fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.stone400,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AI Feature Card ──────────────────────────────────────────────────────────

class _AiFeatureCard extends StatelessWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String hintText;
  final TextEditingController controller;
  final bool loading;
  final String buttonLabel;
  final VoidCallback? onAction;
  final TextInputType? keyboardType;

  const _AiFeatureCard({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.hintText,
    required this.controller,
    required this.loading,
    required this.buttonLabel,
    this.onAction,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
          ]),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
              keyboardType: keyboardType,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: loading
                    ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: gradientColors.first))
                    : Text(buttonLabel, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: gradientColors.first)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
