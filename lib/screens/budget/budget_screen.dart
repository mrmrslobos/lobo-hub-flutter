// lib/screens/budget/budget_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../config/theme.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common_widgets.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

enum _BudgetFilter { all, income, expenses }

class _BudgetScreenState extends State<BudgetScreen> {
  _BudgetFilter _filter = _BudgetFilter.all;
  final _currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

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
          await provider.saveAndSync(db.copyWith(budgetEntries: [...db.budgetEntries, entry]));
        },
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
          const SliverAppBar(title: Text('Budget'), floating: true),
          // Monthly summary
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                Row(children: [
                  Expanded(child: StatCard(label: 'Income', value: _currencyFmt.format(totalIncome), emoji: '💰', color: AppTheme.success)),
                  const SizedBox(width: 10),
                  Expanded(child: StatCard(label: 'Expenses', value: _currencyFmt.format(totalExpenses), emoji: '💸', color: AppTheme.error)),
                ]),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (net >= 0 ? AppTheme.success : AppTheme.error).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: (net >= 0 ? AppTheme.success : AppTheme.error).withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Text(net >= 0 ? '📈' : '📉', style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _currencyFmt.format(net.abs()),
                        style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w900, color: net >= 0 ? AppTheme.success : AppTheme.error),
                      ),
                      Text(net >= 0 ? 'Net savings this month' : 'Overspent this month',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          // Filter tabs
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: AppTabBar(
                tabs: const ['All', 'Income', 'Expenses'],
                selectedIndex: _filter.index,
                onSelected: (i) => setState(() => _filter = _BudgetFilter.values[i]),
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

class _EntryCard extends StatelessWidget {
  final BudgetEntry entry;
  final NumberFormat currencyFmt;
  final VoidCallback onDelete;

  const _EntryCard({required this.entry, required this.currencyFmt, required this.onDelete});

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
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Entry'),
          content: Text('Delete "${entry.title}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
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
            width: 42, height: 42,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.title, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone900)),
            const SizedBox(height: 2),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.stone100, borderRadius: BorderRadius.circular(5)),
                child: Text(entry.category.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.stone600)),
              ),
              const SizedBox(width: 6),
              Text(DateFormat('MMM d, y').format(entry.date), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${isIncome ? '+' : '-'}${currencyFmt.format(entry.amount)}',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 15, color: color),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
              child: Text(isIncome ? 'Income' : 'Expense', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
        ]),
      ),
    );
  }
}

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
    if (_titleCtrl.text.trim().isEmpty || _amountCtrl.text.trim().isEmpty) return;
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
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('New Entry', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.stone900)),
              TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
              // Income / Expense toggle
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isIncome = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isIncome ? AppTheme.success.withOpacity(0.1) : AppTheme.stone50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isIncome ? AppTheme.success : AppTheme.stone200, width: _isIncome ? 2 : 1),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.arrow_downward_rounded, color: _isIncome ? AppTheme.success : AppTheme.stone400, size: 16),
                        const SizedBox(width: 6),
                        Text('Income', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: _isIncome ? AppTheme.success : AppTheme.stone500)),
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
                        color: !_isIncome ? AppTheme.error.withOpacity(0.1) : AppTheme.stone50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: !_isIncome ? AppTheme.error : AppTheme.stone200, width: !_isIncome ? 2 : 1),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.arrow_upward_rounded, color: !_isIncome ? AppTheme.error : AppTheme.stone400, size: 16),
                        const SizedBox(width: 6),
                        Text('Expense', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: !_isIncome ? AppTheme.error : AppTheme.stone500)),
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              TextField(controller: _titleCtrl, autofocus: true, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title *', prefixIcon: Icon(Icons.label_outline_rounded))),
              const SizedBox(height: 12),
              TextField(controller: _amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount *', prefixIcon: Icon(Icons.attach_money_rounded))),
              const SizedBox(height: 12),
              DropdownButtonFormField<BudgetCategory>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                items: BudgetCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (v) { if (v != null) setState(() => _category = v); },
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.stone50, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.stone200)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.stone500),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEE, MMM d, y').format(_date), style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone800)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _notesCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true)),
            ]),
          ),
        ]),
      ),
    );
  }
}
