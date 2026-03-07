// lib/screens/budget/budget_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

// ─── Budget screen ────────────────────────────────────────────────────────────

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

enum _BudgetFilter { all, income, expenses }

class _BudgetScreenState extends State<BudgetScreen> {
  _BudgetFilter _filter = _BudgetFilter.all;
  final _currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  String _formatCurrency(double amount) => '\$${amount.toStringAsFixed(2)}';

  Future<void> _deleteEntry(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      budgetEntries: db.budgetEntries.where((e) => e.id != id).toList(),
    ));
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetEntrySheet(
        onSave: (entry) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(
              db.copyWith(budgetEntries: [...db.budgetEntries, entry]));
        },
      ),
    );
  }

  void _showAddGoalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddGoalSheet(
        onSave: (goal) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(
              db.copyWith(savingsGoals: [...db.savingsGoals, goal]));
        },
      ),
    );
  }

  Future<void> _deleteGoal(String id) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    await provider.saveAndSync(db.copyWith(
      savingsGoals: db.savingsGoals.where((g) => g.id != id).toList(),
    ));
  }

  void _showAddFundsDialog(BuildContext context, SavingsGoal goal) {
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Funds to ${goal.title}'),
        content: TextField(
          controller: amountCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.attach_money_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) return;
              Navigator.pop(ctx);
              final provider = context.read<AppProvider>();
              final db = provider.db;
              final updated = goal.copyWith(
                currentAmount: goal.currentAmount + amount,
              );
              final goals = db.savingsGoals
                  .map((g) => g.id == goal.id ? updated : g)
                  .toList();
              await provider.saveAndSync(db.copyWith(savingsGoals: goals));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAiAnalysis(
    BuildContext context, {
    required double totalIncome,
    required double totalExpenses,
    required List<BudgetEntry> entries,
  }) async {
    // Build byCategory map
    final byCategory = <String, double>{};
    for (final entry in entries) {
      if (!entry.isIncome) {
        byCategory[entry.category.name] =
            (byCategory[entry.category.name] ?? 0) + entry.amount;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiBudgetAnalysisSheet(
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        byCategory: byCategory,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.activeUser;
    final family = provider.activeFamily;
    if (user == null || family == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final now = DateTime.now();
    final allEntries = provider.db.budgetEntries
        .where((e) => e.familyId == family.id)
        .toList();

    final monthEntries = allEntries
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .toList();

    final totalIncome = monthEntries
        .where((e) => e.isIncome)
        .fold(0.0, (s, e) => s + e.amount);
    final totalExpenses = monthEntries
        .where((e) => !e.isIncome)
        .fold(0.0, (s, e) => s + e.amount);
    final net = totalIncome - totalExpenses;

    final savingsGoals = provider.db.savingsGoals
        .where((g) => g.familyId == family.id)
        .toList();

    List<BudgetEntry> shown;
    switch (_filter) {
      case _BudgetFilter.all:
        shown = allEntries;
        break;
      case _BudgetFilter.income:
        shown = allEntries.where((e) => e.isIncome).toList();
        break;
      case _BudgetFilter.expenses:
        shown = allEntries.where((e) => !e.isIncome).toList();
        break;
    }
    shown.sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Budget'),
            floating: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'AI Budget Analysis',
                onPressed: () => _showAiAnalysis(
                  context,
                  totalIncome: totalIncome,
                  totalExpenses: totalExpenses,
                  entries: monthEntries,
                ),
              ),
            ],
          ),
          // Monthly summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: StatCard(
                      label: 'Income',
                      value: _currencyFmt.format(totalIncome),
                      emoji: '💰',
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatCard(
                      label: 'Expenses',
                      value: _currencyFmt.format(totalExpenses),
                      emoji: '💸',
                      color: AppTheme.error,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (net >= 0 ? AppTheme.success : AppTheme.error)
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: (net >= 0 ? AppTheme.success : AppTheme.error)
                            .withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Text(net >= 0 ? '📈' : '📉',
                        style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currencyFmt.format(net.abs()),
                            style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: net >= 0
                                    ? AppTheme.success
                                    : AppTheme.error),
                          ),
                          Text(
                              net >= 0
                                  ? 'Net savings this month'
                                  : 'Overspent this month',
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.stone500)),
                        ]),
                  ]),
                ),
              ]),
            ),
          ),

          // ─── Savings Goals section ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Savings Goals',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.stone900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showAddGoalSheet,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Goal'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (savingsGoals.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.stone50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.stone200),
                  ),
                  child: Row(children: [
                    const Text('🎯', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No savings goals yet',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.stone800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Set a goal to start tracking your savings.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.stone500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final goal = savingsGoals[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SavingsGoalCard(
                        goal: goal,
                        formatCurrency: _formatCurrency,
                        onTap: () => _showAddFundsDialog(context, goal),
                        onDelete: () => _deleteGoal(goal.id),
                      ),
                    );
                  },
                  childCount: savingsGoals.length,
                ),
              ),
            ),

          // Filter tabs
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: AppTabBar(
                tabs: const ['All', 'Income', 'Expenses'],
                selectedIndex: _filter.index,
                onSelected: (i) =>
                    setState(() => _filter = _BudgetFilter.values[i]),
              ),
            ),
          ),
          // Entries list
          shown.isEmpty
              ? SliverFillRemaining(
                  child: EmptyState(
                    emoji: '💰',
                    title: 'No entries yet',
                    subtitle: 'Track income and expenses for your family.',
                    actionLabel: 'Add Entry',
                    onAction: _showAddSheet,
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final entry = shown[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _EntryCard(
                            entry: entry,
                            currencyFmt: _currencyFmt,
                            onDelete: () => _deleteEntry(entry.id),
                          ),
                        );
                      },
                      childCount: shown.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Savings Goal Card ────────────────────────────────────────────────────────

class _SavingsGoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final String Function(double) formatCurrency;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavingsGoalCard({
    required this.goal,
    required this.formatCurrency,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final daysUntil = goal.deadline != null
        ? goal.deadline!.difference(DateTime.now()).inDays
        : null;

    return GestureDetector(
      onTap: goal.isComplete ? null : onTap,
      onLongPress: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Goal'),
            content: Text('Delete "${goal.title}"?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete',
                      style: TextStyle(color: AppTheme.error))),
            ],
          ),
        );
        if (confirmed == true) onDelete();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: goal.isComplete
              ? AppTheme.success.withOpacity(0.06)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: goal.isComplete
                ? AppTheme.success.withOpacity(0.3)
                : AppTheme.stone100,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (goal.emoji != null)
                  Text(goal.emoji!,
                      style: const TextStyle(fontSize: 22)),
                if (goal.emoji != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goal.title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.stone900,
                    ),
                  ),
                ),
                if (goal.isComplete)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.success.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 12, color: AppTheme.success),
                        SizedBox(width: 4),
                        Text(
                          'Complete!',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Icon(Icons.add_circle_outline_rounded,
                      color: AppTheme.primary.withOpacity(0.6), size: 20),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal.progress,
                minHeight: 8,
                backgroundColor: AppTheme.stone100,
                valueColor: AlwaysStoppedAnimation(
                  goal.isComplete ? AppTheme.success : AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatCurrency(goal.currentAmount)} of ${formatCurrency(goal.targetAmount)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.stone600,
                  ),
                ),
                if (daysUntil != null && !goal.isComplete)
                  Text(
                    daysUntil > 0
                        ? '$daysUntil day${daysUntil == 1 ? '' : 's'} left'
                        : daysUntil == 0
                            ? 'Due today'
                            : 'Overdue',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: daysUntil <= 0
                          ? AppTheme.error
                          : daysUntil <= 7
                              ? AppTheme.warning
                              : AppTheme.stone400,
                    ),
                  ),
                Text(
                  '${(goal.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.stone500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Goal Sheet ───────────────────────────────────────────────────────────

class _AddGoalSheet extends StatefulWidget {
  final Future<void> Function(SavingsGoal) onSave;
  const _AddGoalSheet({required this.onSave});

  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  static const _emojis = ['🏠', '🚗', '✈️', '💍', '🎓', '📱', '🎄', '🏖️', '💻', '🎁'];

  final _titleCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  String _selectedEmoji = '🎯';
  DateTime? _deadline;
  bool _isSaving = false;
  final _uuid = const Uuid();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (d != null) setState(() => _deadline = d);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text.trim());
    if (title.isEmpty || target == null || target <= 0) return;

    final current = double.tryParse(_currentCtrl.text.trim()) ?? 0.0;

    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final goal = SavingsGoal(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      title: title,
      targetAmount: target,
      currentAmount: current,
      emoji: _selectedEmoji,
      deadline: _deadline,
      createdBy: provider.activeUser!.id,
      createdAt: DateTime.now(),
    );
    await widget.onSave(goal);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'New Savings Goal',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: AppTheme.stone900,
                    ),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Emoji picker
                  const Text(
                    'Choose an emoji',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.stone700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _emojis.map((e) {
                        final selected = e == _selectedEmoji;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedEmoji = e),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.primary.withOpacity(0.12)
                                  : AppTheme.stone50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primary
                                    : AppTheme.stone200,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(e,
                                style: const TextStyle(fontSize: 22)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title
                  TextField(
                    controller: _titleCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Goal title *',
                      hintText: 'e.g. Family vacation',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Target amount
                  TextField(
                    controller: _targetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Target amount *',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Current amount (optional)
                  TextField(
                    controller: _currentCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Current amount (optional)',
                      hintText: '0.00',
                      prefixIcon: Icon(Icons.savings_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Deadline
                  GestureDetector(
                    onTap: _pickDeadline,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.stone200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppTheme.stone500),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _deadline != null
                                ? DateFormat('EEE, MMM d, y').format(_deadline!)
                                : 'No deadline (optional)',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: _deadline != null
                                  ? AppTheme.stone800
                                  : AppTheme.stone400,
                            ),
                          ),
                        ),
                        if (_deadline != null)
                          GestureDetector(
                            onTap: () => setState(() => _deadline = null),
                            child: const Icon(Icons.clear,
                                size: 18, color: AppTheme.stone400),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Create Goal'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AI Budget Analysis Sheet ─────────────────────────────────────────────────

class _AiBudgetAnalysisSheet extends StatefulWidget {
  final double totalIncome;
  final double totalExpenses;
  final Map<String, double> byCategory;

  const _AiBudgetAnalysisSheet({
    required this.totalIncome,
    required this.totalExpenses,
    required this.byCategory,
  });

  @override
  State<_AiBudgetAnalysisSheet> createState() => _AiBudgetAnalysisSheetState();
}

class _AiBudgetAnalysisSheetState extends State<_AiBudgetAnalysisSheet> {
  String? _analysis;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnalysis();
  }

  Future<void> _fetchAnalysis() async {
    final result = await AiService.analyzeBudget(
      totalIncome: widget.totalIncome,
      totalExpenses: widget.totalExpenses,
      byCategory: widget.byCategory,
    );
    if (mounted) {
      setState(() {
        _loading = false;
        _analysis = result;
        _error = result == null ? 'Could not generate analysis. Please try again.' : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppTheme.primary, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AI Budget Analysis',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppTheme.stone900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Analyzing your budget...',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: AppTheme.stone500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('😕',
                                    style: TextStyle(fontSize: 40)),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    color: AppTheme.stone500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _loading = true;
                                      _error = null;
                                    });
                                    _fetchAnalysis();
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          controller: controller,
                          padding:
                              const EdgeInsets.fromLTRB(20, 0, 20, 32),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color:
                                        AppTheme.primary.withOpacity(0.15)),
                              ),
                              child: Text(
                                _analysis ?? '',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  height: 1.6,
                                  color: AppTheme.stone800,
                                ),
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Entry Card ───────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final BudgetEntry entry;
  final NumberFormat currencyFmt;
  final VoidCallback onDelete;

  const _EntryCard(
      {required this.entry,
      required this.currencyFmt,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.isIncome;
    final color = isIncome ? AppTheme.success : AppTheme.error;
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Entry'),
          content: Text('Delete "${entry.title}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: AppTheme.error))),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(
                isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: color,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(entry.title,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.stone900)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppTheme.stone100,
                        borderRadius: BorderRadius.circular(5)),
                    child: Text(entry.category.name,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.stone600)),
                  ),
                  const SizedBox(width: 6),
                  Text(DateFormat('MMM d, y').format(entry.date),
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.stone400)),
                ]),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${isIncome ? '+' : '-'}${currencyFmt.format(entry.amount)}',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: color),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5)),
              child: Text(isIncome ? 'Income' : 'Expense',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─── Budget Entry Sheet ───────────────────────────────────────────────────────

class _BudgetEntrySheet extends StatefulWidget {
  final Future<void> Function(BudgetEntry) onSave;
  const _BudgetEntrySheet({required this.onSave});

  @override
  State<_BudgetEntrySheet> createState() => _BudgetEntrySheetState();
}

class _BudgetEntrySheetState extends State<_BudgetEntrySheet> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isIncome = false;
  BudgetCategory _category = BudgetCategory.other;
  DateTime _date = DateTime.now();
  bool _isSaving = false;
  final _uuid = const Uuid();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty || _amountCtrl.text.trim().isEmpty)
      return;
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) return;
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final entry = BudgetEntry(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      title: _titleCtrl.text.trim(),
      amount: amount,
      category: _category,
      isIncome: _isIncome,
      date: _date,
      createdBy: provider.activeUser!.id,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await widget.onSave(entry);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New Entry',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: AppTheme.stone900)),
                  TextButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save',
                            style:
                                TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
          ),
          Expanded(
            child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Income / Expense toggle
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isIncome = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isIncome
                                ? AppTheme.success.withOpacity(0.1)
                                : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _isIncome
                                    ? AppTheme.success
                                    : AppTheme.stone200,
                                width: _isIncome ? 2 : 1),
                          ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.arrow_downward_rounded,
                                    color: _isIncome
                                        ? AppTheme.success
                                        : AppTheme.stone400,
                                    size: 16),
                                const SizedBox(width: 6),
                                Text('Income',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: _isIncome
                                            ? AppTheme.success
                                            : AppTheme.stone500)),
                              ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isIncome = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isIncome
                                ? AppTheme.error.withOpacity(0.1)
                                : AppTheme.stone50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: !_isIncome
                                    ? AppTheme.error
                                    : AppTheme.stone200,
                                width: !_isIncome ? 2 : 1),
                          ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.arrow_upward_rounded,
                                    color: !_isIncome
                                        ? AppTheme.error
                                        : AppTheme.stone400,
                                    size: 16),
                                const SizedBox(width: 6),
                                Text('Expense',
                                    style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: !_isIncome
                                            ? AppTheme.error
                                            : AppTheme.stone500)),
                              ]),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                      controller: _titleCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                          labelText: 'Title *',
                          prefixIcon: Icon(Icons.label_outline_rounded))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Amount *',
                          prefixIcon: Icon(Icons.attach_money_rounded))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BudgetCategory>(
                    value: _category,
                    decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined)),
                    items: BudgetCategory.values
                        .map((c) => DropdownMenuItem(
                            value: c, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _category = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                          color: AppTheme.stone50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.stone200)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 18, color: AppTheme.stone500),
                        const SizedBox(width: 10),
                        Text(DateFormat('EEE, MMM d, y').format(_date),
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: AppTheme.stone800)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          alignLabelWithHint: true)),
                ]),
          ),
        ]),
      ),
    );
  }
}
