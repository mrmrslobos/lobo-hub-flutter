import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/models.dart';

const _uuid = Uuid();

class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key});

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _weekStart = _getWeekStart(DateTime.now());
  String _recipeSearch = '';

  static DateTime _getWeekStart(DateTime d) {
    final diff = d.weekday - 1;
    return DateTime(d.year, d.month, d.day - diff);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id;
    if (familyId == null) {
      return const Scaffold(body: Center(child: Text('No family selected')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            tooltip: 'Shopping List',
            onPressed: () => _showShoppingList(context, provider, familyId),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Week Plan'),
            Tab(text: 'Recipes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _WeekPlanTab(
            weekStart: _weekStart,
            familyId: familyId,
            provider: provider,
            onPrevWeek: () => setState(
                () => _weekStart = _weekStart.subtract(const Duration(days: 7))),
            onNextWeek: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7))),
          ),
          _RecipesTab(
            familyId: familyId,
            provider: provider,
            search: _recipeSearch,
            onSearchChanged: (v) => setState(() => _recipeSearch = v),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddRecipeSheet(context, provider, familyId),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showShoppingList(
      BuildContext context, AppProvider provider, String familyId) {
    final now = DateTime.now();
    final weekStart = _weekStart;
    final weekEnd = weekStart.add(const Duration(days: 7));
    final mealPlans = provider.db.mealPlans
        .where((m) =>
            m.familyId == familyId &&
            !m.date.isBefore(weekStart) &&
            m.date.isBefore(weekEnd))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This Week\'s Meals'),
        content: mealPlans.isEmpty
            ? const Text('No meals planned this week.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: mealPlans
                      .map((m) => ListTile(
                            leading:
                                Text(_mealIcon(m.mealType), style: const TextStyle(fontSize: 20)),
                            title: Text(m.title),
                            subtitle: Text(
                                DateFormat('EEE, MMM d').format(m.date)),
                          ))
                      .toList(),
                ),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  String _mealIcon(String type) {
    switch (type) {
      case 'breakfast': return '☀️';
      case 'lunch': return '🌤️';
      case 'dinner': return '🌙';
      default: return '🍽️';
    }
  }

  void _showAddRecipeSheet(
      BuildContext context, AppProvider provider, String familyId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          _RecipeFormSheet(familyId: familyId, provider: provider),
    );
  }
}

// ─────────────────────────────────────────────
// Week Plan Tab
// ─────────────────────────────────────────────

class _WeekPlanTab extends StatelessWidget {
  const _WeekPlanTab({
    required this.weekStart,
    required this.familyId,
    required this.provider,
    required this.onPrevWeek,
    required this.onNextWeek,
  });

  final DateTime weekStart;
  final String familyId;
  final AppProvider provider;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;

  static const _mealTypes = ['breakfast', 'lunch', 'dinner'];
  static const _mealLabels = {
    'breakfast': 'Breakfast',
    'lunch': 'Lunch',
    'dinner': 'Dinner',
  };
  static const _mealIcons = {
    'breakfast': '☀️',
    'lunch': '🌤️',
    'dinner': '🌙',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildWeekNav(context),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 7,
            itemBuilder: (ctx, dayIdx) {
              final day = weekStart.add(Duration(days: dayIdx));
              return _buildDayCard(context, day);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekNav(BuildContext context) {
    final fmt = DateFormat('MMM d');
    final weekEnd = weekStart.add(const Duration(days: 6));
    return Container(
      color: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: onPrevWeek),
          Expanded(
            child: Text(
              '${fmt.format(weekStart)} – ${fmt.format(weekEnd)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed: onNextWeek),
        ],
      ),
    );
  }

  Widget _buildDayCard(BuildContext context, DateTime day) {
    final isToday = _sameDay(day, DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFFE7E5E4),
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isToday
                  ? Theme.of(context).colorScheme.primaryContainer
                  : const Color(0xFFF5F5F4),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Text(
                  DateFormat('EEEE, MMM d').format(day),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isToday
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFF1C1917),
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Today',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
          ..._mealTypes.map((type) => _buildSlot(context, day, type)),
        ],
      ),
    );
  }

  Widget _buildSlot(BuildContext context, DateTime day, String mealType) {
    final plan = provider.db.mealPlans
        .where((m) =>
            m.familyId == familyId &&
            _sameDay(m.date, day) &&
            m.mealType == mealType)
        .firstOrNull;

    return InkWell(
      onTap: () => _pickMeal(context, day, mealType, plan),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(_mealIcons[mealType] ?? '🍽️',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mealLabels[mealType] ?? mealType,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF78716C)),
                ),
                Text(
                  plan?.title ?? 'Tap to add',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: plan != null
                        ? const Color(0xFF1C1917)
                        : const Color(0xFFA8A29E),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (plan != null)
              GestureDetector(
                onTap: () {
                  final newPlans =
                      provider.db.mealPlans.where((m) => m.id != plan.id).toList();
                  provider.saveAndSync(
                      provider.db.copyWith(mealPlans: newPlans));
                },
                child: const Icon(Icons.close, size: 16, color: Color(0xFFA8A29E)),
              )
            else
              const Icon(Icons.add_circle_outline,
                  size: 18, color: Color(0xFFA8A29E)),
          ],
        ),
      ),
    );
  }

  void _pickMeal(BuildContext context, DateTime day, String mealType,
      MealPlan? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MealPickerSheet(
        day: day,
        mealType: mealType,
        familyId: familyId,
        provider: provider,
        existing: existing,
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────
// Recipes Tab
// ─────────────────────────────────────────────

class _RecipesTab extends StatelessWidget {
  const _RecipesTab({
    required this.familyId,
    required this.provider,
    required this.search,
    required this.onSearchChanged,
  });

  final String familyId;
  final AppProvider provider;
  final String search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final recipes = provider.db.mealPlans
        .where((m) => m.familyId == familyId && seen.add(m.title))
        .toList();

    final filtered = search.isEmpty
        ? recipes
        : recipes
            .where((r) =>
                r.title.toLowerCase().contains(search.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search recipes...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🍽️',
                          style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text(
                        search.isEmpty
                            ? 'No recipes yet'
                            : 'No results found',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        search.isEmpty
                            ? 'Add a recipe using the + button below'
                            : 'Try a different search term',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _RecipeCard(plan: filtered[i]),
                ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.plan});
  final MealPlan plan;

  static const _icons = {
    'breakfast': '🥞',
    'lunch': '🥗',
    'dinner': '🍲',
    'snack': '🍎',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _icons[plan.mealType] ?? '🍽️',
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                if (plan.notes != null && plan.notes!.isNotEmpty)
                  Text(plan.notes!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF78716C)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _capitalize(plan.mealType),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6366F1)),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────
// Meal Picker Sheet
// ─────────────────────────────────────────────

class _MealPickerSheet extends StatefulWidget {
  const _MealPickerSheet({
    required this.day,
    required this.mealType,
    required this.familyId,
    required this.provider,
    this.existing,
  });

  final DateTime day;
  final String mealType;
  final String familyId;
  final AppProvider provider;
  final MealPlan? existing;

  @override
  State<_MealPickerSheet> createState() => _MealPickerSheetState();
}

class _MealPickerSheetState extends State<_MealPickerSheet> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _ctrl.text = widget.existing!.title;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final suggestions = widget.provider.db.mealPlans
        .where((m) =>
            m.familyId == widget.familyId &&
            m.mealType == widget.mealType &&
            seen.add(m.title))
        .map((m) => m.title)
        .take(6)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_capitalize(widget.mealType)} · ${DateFormat('EEE, MMM d').format(widget.day)}',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (suggestions.isNotEmpty) ...[
            const Text('Recent:',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: suggestions
                  .map((t) => ActionChip(
                        label: Text(t),
                        onPressed: () => _save(t),
                      ))
                  .toList(),
            ),
            const Divider(height: 24),
          ],
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              labelText: 'Meal name',
              hintText: 'e.g. Chicken Stir Fry',
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: suggestions.isEmpty,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_ctrl.text.trim().isNotEmpty) {
                      _save(_ctrl.text.trim());
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _save(String title) {
    final db = widget.provider.db;
    final newPlans = db.mealPlans
        .where((m) =>
            !(m.familyId == widget.familyId &&
                _sameDay(m.date, widget.day) &&
                m.mealType == widget.mealType))
        .toList();

    newPlans.add(MealPlan(
      id: widget.existing?.id ?? _uuid.v4(),
      familyId: widget.familyId,
      date: widget.day,
      mealType: widget.mealType,
      title: title,
      createdBy: widget.provider.activeUser?.id ?? '',
    ));

    widget.provider.saveAndSync(db.copyWith(mealPlans: newPlans));
    Navigator.pop(context);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─────────────────────────────────────────────
// Add Recipe Sheet
// ─────────────────────────────────────────────

class _RecipeFormSheet extends StatefulWidget {
  const _RecipeFormSheet({required this.familyId, required this.provider});
  final String familyId;
  final AppProvider provider;

  @override
  State<_RecipeFormSheet> createState() => _RecipeFormSheetState();
}

class _RecipeFormSheetState extends State<_RecipeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _ingredientsCtrl = TextEditingController();
  final _stepsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _mealType = 'dinner';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _ingredientsCtrl.dispose();
    _stepsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      builder: (ctx, scroll) => Form(
        key: _formKey,
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          children: [
            Row(
              children: [
                const Text('🍽️', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                const Text('Add Recipe',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleCtrl,
              decoration:
                  const InputDecoration(labelText: 'Recipe Title *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _mealType,
              decoration: const InputDecoration(labelText: 'Meal Type'),
              items: const [
                DropdownMenuItem(
                    value: 'breakfast', child: Text('Breakfast')),
                DropdownMenuItem(value: 'lunch', child: Text('Lunch')),
                DropdownMenuItem(value: 'dinner', child: Text('Dinner')),
                DropdownMenuItem(value: 'snack', child: Text('Snack')),
              ],
              onChanged: (v) => setState(() => _mealType = v ?? 'dinner'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ingredientsCtrl,
              decoration: const InputDecoration(
                labelText: 'Ingredients',
                hintText: 'One ingredient per line',
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _stepsCtrl,
              decoration: const InputDecoration(
                labelText: 'Steps / Instructions',
                hintText: 'Step-by-step instructions',
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                  labelText: 'Notes (servings, tips, etc.)'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Save Recipe'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final db = widget.provider.db;
    final notes = [
      if (_ingredientsCtrl.text.trim().isNotEmpty)
        'Ingredients:\n${_ingredientsCtrl.text.trim()}',
      if (_stepsCtrl.text.trim().isNotEmpty)
        'Steps:\n${_stepsCtrl.text.trim()}',
      if (_notesCtrl.text.trim().isNotEmpty) _notesCtrl.text.trim(),
    ].join('\n\n');

    widget.provider.saveAndSync(db.copyWith(mealPlans: [
      ...db.mealPlans,
      MealPlan(
        id: _uuid.v4(),
        familyId: widget.familyId,
        date: DateTime.now(),
        mealType: _mealType,
        title: _titleCtrl.text.trim(),
        notes: notes.isEmpty ? null : notes,
        createdBy: widget.provider.activeUser?.id ?? '',
      ),
    ]));
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Recipe saved!')));
  }
}
