// lib/screens/meals/meals_screen.dart
// Meal planning + recipe library screen for FamilyHub

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';
import '../../services/ai_service.dart';
import '../../config/theme.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

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
  bool _fabOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final weekLabel = '${DateFormat('MMM d').format(monday)} - ${DateFormat('MMM d').format(sunday)}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppTheme.stone700),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('FamilyHub', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.primary)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(icon: const Icon(Icons.menu_rounded, color: AppTheme.stone500), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page Header ──
            const PageHeader(
              title: 'Meal Hub',
              subtitle: 'Plan nutrition and manage family recipes.',
            ),

            // ── Tab chips ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tabController.index == 0 ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: _tabController.index == 0 ? null : Border.all(color: AppTheme.stone200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Weekly Plan',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _tabController.index == 0 ? Colors.white : AppTheme.stone600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tabController.index == 1 ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: _tabController.index == 1 ? null : Border.all(color: AppTheme.stone200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Recipe Box',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _tabController.index == 1 ? Colors.white : AppTheme.stone600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── AI Chef Suggestion card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF16A34A), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.restaurant_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('AI Chef Suggestion', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const TextField(
                        style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Quick dinner for 4, vegetarian...',
                          hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          filled: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Suggest Meals', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF16A34A))),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Import from URL card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D9488), Color(0xFF06B6D4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.link_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Import from URL', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const TextField(
                        style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Paste recipe URL...',
                          hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          filled: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Import Recipe', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0D9488))),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── AI Week Planner card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.calendar_month_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('AI Week Planner', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const TextField(
                        style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Healthy meals, budget-friendly...',
                          hintStyle: TextStyle(color: Colors.white54, fontFamily: 'Inter'),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          filled: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Plan My Week + Shopping List', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF8B5CF6))),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Week of [Date] section ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Week of $weekLabel',
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.stone800),
              ),
            ),
            const SizedBox(height: 12),

            // ── Day-by-day meal plan (Sun-Sat) ──
            ...List.generate(7, (i) {
              final day = monday.add(Duration(days: i));
              final dayName = DateFormat('EEEE').format(day);
              final dayDate = DateFormat('MMM d').format(day);
              final mealsForDay = provider.db.mealPlans
                  .where((m) => m.familyId == familyId && m.date.year == day.year && m.date.month == day.month && m.date.day == day.day)
                  .toList();

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.stone100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Row(
                          children: [
                            Text(dayName, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone800)),
                            const SizedBox(width: 8),
                            Text(dayDate, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400)),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppTheme.stone100),
                      ...['breakfast', 'lunch', 'dinner'].map((type) {
                        final meal = mealsForDay.cast<MealPlan?>().firstWhere((m) => m?.mealType == type, orElse: () => null);
                        final label = type[0].toUpperCase() + type.substring(1);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: Text(label.toUpperCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8)),
                              ),
                              Expanded(
                                child: meal != null
                                    ? Text(meal.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.stone700))
                                    : Text('+ Add', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.primary.withOpacity(0.7))),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            // ── Tab content ──
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _MealPlanTab(),
                  _RecipesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab 1: Meal Plan ────────────────────────────────────────────────────────

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

    return Column(
      children: [
        // Week navigation header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _goToPreviousWeek,
              ),
              Text(
                weekLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.stone700,
                  fontSize: 14,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _goToNextWeek,
              ),
            ],
          ),
        ),
        // Day selector
        SizedBox(
          height: 76,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: 7,
            itemBuilder: (context, i) {
              final day = _weekDays[i];
              final isSelected = _isSameDay(day, _selectedDay);
              final isToday = _isToday(day);
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
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
                              ? AppTheme.primary.withOpacity(0.4)
                              : AppTheme.stone200,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('E').format(day).substring(0, 1),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white70 : AppTheme.stone500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.day.toString(),
                        style: TextStyle(
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
        // Meal slots
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                DateFormat('EEEE, MMMM d').format(_selectedDay),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.stone800,
                ),
              ),
              const SizedBox(height: 12),
              ..._mealTypes.map((type) {
                final meal = mealsForDay.cast<MealPlan?>().firstWhere(
                      (m) => m?.mealType == type,
                      orElse: () => null,
                    );
                return _MealSlotCard(
                  mealType: type,
                  meal: meal,
                  day: _selectedDay,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _MealSlotCard extends StatelessWidget {
  final String mealType;
  final MealPlan? meal;
  final DateTime day;

  const _MealSlotCard({
    required this.mealType,
    required this.meal,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final emoji = _mealTypeEmojis[mealType] ?? '🍽️';
    final label = _mealTypeLabels[mealType] ?? mealType;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.all(14),
        onTap: meal != null
            ? () => _showMealOptions(context)
            : () => _openAddMealSheet(context, mealType, day),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
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
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.stone500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (meal != null) ...[
                    Text(
                      meal!.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.stone900,
                      ),
                    ),
                    if (meal!.notes != null && meal!.notes!.isNotEmpty)
                      Text(
                        meal!.notes!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.stone500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ] else
                    Text(
                      '+ Add',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.primary.withOpacity(0.7),
                      ),
                    ),
                ],
              ),
            ),
            if (meal != null)
              const Icon(Icons.more_horiz, color: AppTheme.stone400, size: 20),
          ],
        ),
      ),
    );
  }

  void _showMealOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.stone300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                title: const Text('Edit meal'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAddMealSheet(context, mealType, day, existingMeal: meal);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.error),
                title: const Text('Delete meal',
                    style: TextStyle(color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMeal(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteMeal(BuildContext context) {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updated =
        db.mealPlans.where((m) => m.id != meal!.id).toList();
    provider.saveAndSync(db.copyWith(mealPlans: updated));
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.mealType;
    if (widget.existingMeal != null) {
      _titleController.text = widget.existingMeal!.title;
      _notesController.text = widget.existingMeal!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
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
    if (_titleController.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final userId = provider.activeUser?.id ?? '';
    final familyId = provider.activeFamily?.id ?? '';

    if (widget.existingMeal != null) {
      final updated = widget.existingMeal!.copyWith(
        mealType: _selectedType,
        customMeal: _titleController.text.trim(),
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
      );
      final meals = [...db.mealPlans, newMeal];
      await provider.saveAndSync(db.copyWith(mealPlans: meals));
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom + 16;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.existingMeal != null ? 'Edit Meal' : 'Add Meal',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.stone900,
            ),
          ),
          const SizedBox(height: 16),
          // Meal type selector
          const Text(
            'Meal Type',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.stone600,
            ),
          ),
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
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${_mealTypeEmojis[type]} ${_mealTypeLabels[type]}',
                      style: TextStyle(
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
          // Title field
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Meal title',
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
          const SizedBox(height: 10),
          // Pick from recipes button
          OutlinedButton.icon(
            onPressed: _pickFromRecipes,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Pick from Recipes'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          // Notes field
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
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
          const SizedBox(height: 16),
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
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.stone300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pick a Recipe',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.stone900),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search recipes...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: AppTheme.stone100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No recipes found',
                        style: TextStyle(color: AppTheme.stone400)))
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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              _recipeEmoji(r),
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                        title: Text(r.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: r.tags.isNotEmpty
                            ? Text(r.tags.take(2).join(', '),
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.stone400))
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

// ─── Tab 2: Recipes ───────────────────────────────────────────────────────────

class _RecipesTab extends StatefulWidget {
  const _RecipesTab();

  @override
  State<_RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<_RecipesTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final recipes = provider.db.recipes
        .where((r) =>
            r.familyId == familyId &&
            (r.title.toLowerCase().contains(_query.toLowerCase()) ||
                r.tags.any((t) => t.toLowerCase().contains(_query.toLowerCase()))))
        .toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search recipes...',
              hintStyle: const TextStyle(color: AppTheme.stone400),
              prefixIcon:
                  const Icon(Icons.search, color: AppTheme.stone400, size: 20),
              filled: true,
              fillColor: AppTheme.stone100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        // Recipe grid
        Expanded(
          child: recipes.isEmpty
              ? EmptyState(
                  emoji: '🍽️',
                  title: _query.isEmpty ? 'No recipes yet' : 'No matches',
                  subtitle: _query.isEmpty
                      ? 'Add your first recipe using the button below.'
                      : 'Try a different search term.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: recipes.length,
                  itemBuilder: (ctx, i) =>
                      _RecipeCard(recipe: recipes[i]),
                ),
        ),
      ],
    );
  }
}

// ─── Recipe Card ──────────────────────────────────────────────────────────────

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  const _RecipeCard({required this.recipe});

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
        builder: (_) => _RecipeDetailSheet(recipe: recipe),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.stone100),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / placeholder
            SizedBox(
              height: 110,
              width: double.infinity,
              child: recipe.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: recipe.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _EmojiPlaceholder(emoji),
                      placeholder: (_, __) => Container(
                        color: AppTheme.stone100,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    if (timeLabel.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined,
                                size: 12, color: AppTheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              timeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (recipe.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: recipe.tags.take(2).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.stone100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.stone600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
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
  const _RecipeDetailSheet({required this.recipe});

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
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.stone300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
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
                              errorWidget: (_, __, ___) =>
                                  _EmojiPlaceholder(_recipeEmoji(recipe)),
                            )
                          : _EmojiPlaceholder(_recipeEmoji(recipe)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    recipe.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.stone900,
                    ),
                  ),
                  if (recipe.description != null &&
                      recipe.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      recipe.description!,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.stone600, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Info chips row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (recipe.prepMinutes != null)
                        _InfoChip(
                            icon: Icons.hourglass_top_outlined,
                            label: 'Prep: ${recipe.prepMinutes}m'),
                      if (recipe.cookMinutes != null)
                        _InfoChip(
                            icon: Icons.local_fire_department_outlined,
                            label: 'Cook: ${recipe.cookMinutes}m'),
                      if ((recipe.prepMinutes ?? 0) +
                              (recipe.cookMinutes ?? 0) >
                          0)
                        _InfoChip(
                            icon: Icons.timer_outlined,
                            label: 'Total: ${_totalTime()}'),
                      if (recipe.servings != null)
                        _InfoChip(
                            icon: Icons.people_outline,
                            label: '${recipe.servings} servings'),
                    ],
                  ),
                  if (recipe.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: recipe.tags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (recipe.ingredients.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Ingredients',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...recipe.ingredients.map((ing) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 6, right: 10),
                                decoration: const BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${ing.amount}${ing.unit != null ? ' ${ing.unit}' : ''} ${ing.name}',
                                  style: const TextStyle(
                                      fontSize: 14, color: AppTheme.stone700),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                  if (recipe.steps.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.stone900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...recipe.steps.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final step = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(right: 12, top: 1),
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$idx',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                step,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.stone700,
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 20),
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
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          builder: (c) => _AddMealSheet(
                            mealType: 'dinner',
                            day: DateTime.now(),
                            existingMeal: null,
                          ),
                        );
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: const Text('Add to Meal Plan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.stone100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.stone600),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.stone700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recipes FAB ──────────────────────────────────────────────────────────────

class _RecipesFab extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onToggle;

  const _RecipesFab({required this.isOpen, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isOpen) ...[
          _FabOption(
            label: 'Import from URL',
            icon: Icons.link,
            onTap: () {
              onToggle();
              _showImportDialog(context);
            },
          ),
          const SizedBox(height: 8),
          _FabOption(
            label: 'Add Recipe',
            icon: Icons.add,
            onTap: () {
              onToggle();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (_) => const _AddRecipeSheet(),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton(
          onPressed: onToggle,
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: isOpen ? 0.125 : 0,
            child: const Icon(Icons.add, size: 28),
          ),
        ),
      ],
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _ImportUrlDialog(),
    );
  }
}

class _FabOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FabOption(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.stone200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.stone800,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
          ],
        ),
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
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await AiService.scrapeRecipe(url);
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
      final familyId = provider.activeFamily?.id ?? '';

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
      title: const Row(
        children: [
          Icon(Icons.link, color: AppTheme.primary),
          SizedBox(width: 10),
          Text('Import Recipe from URL'),
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
    if (_titleController.text.trim().isEmpty) return;
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

    if (widget.existingRecipe != null) {
      final updated = widget.existingRecipe!.copyWith(
        title: _titleController.text.trim(),
        ingredients: ingredients,
        steps: steps,
        servings: int.tryParse(_servingsController.text),
        tags: List.from(_selectedTags),
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
        createdBy: userId,
      );
      await provider.saveAndSync(
          db.copyWith(recipes: [...db.recipes, newRecipe]));
    }

    if (mounted) Navigator.pop(context);
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppTheme.stone50,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.stone200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.stone200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.stone300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.existingRecipe != null
                            ? 'Edit Recipe'
                            : 'Add Recipe',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.stone900,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.stone500),
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
                  TextField(
                    controller: _titleController,
                    decoration: _fieldDecoration('Recipe Title *'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  // Description
                  TextField(
                    controller: _descController,
                    maxLines: 2,
                    decoration: _fieldDecoration('Description'),
                  ),
                  const SizedBox(height: 12),
                  // Time & servings row
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
                  const SizedBox(height: 20),
                  // Ingredients section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ingredients',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.stone900,
                        ),
                      ),
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
                  const SizedBox(height: 16),
                  // Steps section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Steps',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.stone900,
                        ),
                      ),
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
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
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
                  const SizedBox(height: 16),
                  // Tags section
                  const Text(
                    'Tags',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.stone900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _availableTags.map((tag) {
                      final selected = _selectedTags.contains(tag);
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.stone100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: selected
                                  ? Colors.white
                                  : AppTheme.stone700,
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
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Save Recipe',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
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
