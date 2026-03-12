// lib/screens/budget/budget_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late DateTime _selectedMonth;
  String _searchQuery = '';
  bool _showAllTransactions = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  String _formatCurrency(double amount) => '\$${amount.toStringAsFixed(2)}';

  static const _categoryColors = <String, Color>{
    'amber': Color(0xFFF59E0B), 'blue': Color(0xFF3B82F6), 'pink': Color(0xFFEC4899),
    'emerald': Color(0xFF10B981), 'purple': Color(0xFF8B5CF6), 'red': Color(0xFFEF4444),
    'cyan': Color(0xFF06B6D4), 'orange': Color(0xFFF97316), 'teal': Color(0xFF14B8A6),
    'indigo': Color(0xFF6366F1), 'lime': Color(0xFF84CC16), 'rose': Color(0xFFF43F5E),
    'sky': Color(0xFF0EA5E9), 'violet': Color(0xFF7C3AED), 'green': Color(0xFF22C55E),
    // Also map by category name for fallback
    'housing': Color(0xFF6366F1), 'food': Color(0xFFF59E0B), 'transport': Color(0xFF3B82F6),
    'entertainment': Color(0xFFEC4899), 'utilities': Color(0xFF14B8A6), 'healthcare': Color(0xFFEF4444),
    'education': Color(0xFF8B5CF6), 'savings': Color(0xFF22C55E), 'other': Color(0xFF78716C),
  };

  static Color _categoryColor(String key) => _categoryColors[key.toLowerCase()] ?? const Color(0xFF78716C);

  Future<void> _deleteEntry(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Delete this transaction? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Savings Goal'),
        content: const Text('Delete this goal and all progress? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
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
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter an amount greater than \$0'), behavior: SnackBarBehavior.floating),
                );
                return;
              }
              final remaining = goal.targetAmount - goal.savedAmount;
              if (remaining > 0 && amount > remaining) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Only \$${remaining.toStringAsFixed(2)} needed to reach the goal'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              final provider = context.read<AppProvider>();
              final db = provider.db;
              final updated = goal.copyWith(
                savedAmount: goal.savedAmount + amount,
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

  void _showManageCategories() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ManageCategoriesSheet(),
    );
  }

  void _showEditEntry(BudgetEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetEntrySheet(
        existingEntry: entry,
        onSave: (updated) async {
          final provider = context.read<AppProvider>();
          final db = provider.db;
          await provider.saveAndSync(db.copyWith(
            budgetEntries: db.budgetEntries.map((e) => e.id == updated.id ? updated : e).toList(),
          ));
        },
      ),
    );
  }

  void _showImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AiBankStatementImportSheet(),
    );
  }

  void _showExportMenu({
    required List<BudgetEntry> entries,
    required List<BudgetCategoryRecord> categories,
    required double totalIncome,
    required double totalExpenses,
    required String familyName,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.stone200, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Export Finance Report', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.stone900)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.table_chart_rounded, color: AppTheme.primary),
                title: const Text('Copy as CSV', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                subtitle: const Text('Copy transaction data to clipboard', style: TextStyle(fontSize: 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.stone50,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportCsv(entries);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.summarize_rounded, color: AppTheme.primary),
                title: const Text('View Report', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                subtitle: const Text('View formatted finance summary', style: TextStyle(fontSize: 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.stone50,
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportView(
                    entries: entries,
                    categories: categories,
                    totalIncome: totalIncome,
                    totalExpenses: totalExpenses,
                    familyName: familyName,
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _exportCsv(List<BudgetEntry> entries) {
    final sorted = List<BudgetEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));
    final lines = <String>['Date,Description,Category,Type,Amount'];
    for (final e in sorted) {
      final date = DateFormat('yyyy-MM-dd').format(e.date);
      final desc = e.title.replaceAll(',', ' ');
      final cat = e.category.name;
      final type = e.isIncome ? 'INCOME' : 'EXPENSE';
      final amt = e.amount.toStringAsFixed(2);
      lines.add('$date,$desc,$cat,$type,$amt');
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV copied to clipboard!')),
    );
  }

  void _showReportView({
    required List<BudgetEntry> entries,
    required List<BudgetCategoryRecord> categories,
    required double totalIncome,
    required double totalExpenses,
    required String familyName,
  }) {
    final net = totalIncome - totalExpenses;
    final byCategory = <String, double>{};
    for (final e in entries.where((e) => !e.isIncome)) {
      byCategory[e.category.name] = (byCategory[e.category.name] ?? 0) + e.amount;
    }
    final catLimits = <String, double>{};
    for (final c in categories) {
      catLimits[c.name] = c.limit;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Finance Report', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Family Finance Report', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 22, color: AppTheme.stone900)),
              const SizedBox(height: 4),
              Text('Generated ${DateFormat('MMMM d, yyyy').format(DateTime.now())} · $familyName',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500)),
              const SizedBox(height: 20),
              // Summary cards
              Row(children: [
                _ReportSummaryBox(label: 'Income', value: _formatCurrency(totalIncome), color: const Color(0xFF166534), bgColor: const Color(0xFFF0FDF4)),
                const SizedBox(width: 8),
                _ReportSummaryBox(label: 'Expenses', value: _formatCurrency(totalExpenses), color: const Color(0xFF9F1239), bgColor: const Color(0xFFFFF1F2)),
                const SizedBox(width: 8),
                _ReportSummaryBox(label: 'Net', value: _formatCurrency(net), color: net >= 0 ? const Color(0xFF166534) : const Color(0xFF9F1239), bgColor: net >= 0 ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2)),
              ]),
              const SizedBox(height: 24),
              // Category breakdown
              const Text('BUDGET CATEGORIES', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.0, color: AppTheme.stone400)),
              const SizedBox(height: 8),
              ...byCategory.entries.map((e) {
                final limit = catLimits[e.key] ?? 0;
                final pct = limit > 0 ? (e.value / limit * 100).toStringAsFixed(0) : '—';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(e.key, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
                    Expanded(flex: 2, child: Text('Limit: ${_formatCurrency(limit)}', style: const TextStyle(fontSize: 12, color: AppTheme.stone500))),
                    Expanded(flex: 2, child: Text('Spent: ${_formatCurrency(e.value)}', style: const TextStyle(fontSize: 12, color: AppTheme.stone700, fontWeight: FontWeight.w600))),
                    SizedBox(width: 50, child: Text('$pct%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                  ]),
                );
              }),
              const SizedBox(height: 24),
              // Transactions table
              const Text('TRANSACTIONS', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.0, color: AppTheme.stone400)),
              const SizedBox(height: 8),
              ...(List<BudgetEntry>.from(entries)..sort((a, b) => b.date.compareTo(a.date))).map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 80, child: Text(DateFormat('MMM d').format(e.date), style: const TextStyle(fontSize: 12, color: AppTheme.stone500))),
                  Expanded(child: Text(e.title, style: const TextStyle(fontSize: 13, fontFamily: 'Inter'), overflow: TextOverflow.ellipsis)),
                  Text(
                    '${e.isIncome ? '+' : '-'}${_formatCurrency(e.amount)}',
                    style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: e.isIncome ? const Color(0xFF166534) : const Color(0xFF9F1239)),
                  ),
                ]),
              )),
            ],
          ),
        ),
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

  Widget _buildSpendingByCategory(List<BudgetEntry> monthEntries, double totalExpenses) {
    final byCategory = <String, double>{};
    for (final e in monthEntries.where((e) => !e.isIncome)) {
      byCategory[e.category.name] = (byCategory[e.category.name] ?? 0) + e.amount;
    }
    final sortedCats = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stone100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Spending by Category', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.stone900)),
            const SizedBox(height: 16),
            // Visual bar chart
            ...sortedCats.map((entry) {
              final pct = totalExpenses > 0 ? entry.value / totalExpenses : 0.0;
              final color = _categoryColor(entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entry.key, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.stone700))),
                      Text(_currencyFmt.format(entry.value), style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.stone800)),
                      const SizedBox(width: 6),
                      Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.stone400)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: AppTheme.stone100,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // Legend
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: sortedCats.map((entry) {
                final color = _categoryColor(entry.key);
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(entry.key, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone500)),
                ]);
              }).toList(),
            ),
          ],
        ),
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

    final allEntries = provider.db.budgetEntries
        .where((e) => e.familyId == family.id)
        .toList();

    final monthEntries = allEntries
        .where((e) => e.date.year == _selectedMonth.year && e.date.month == _selectedMonth.month)
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

    final categories = provider.db.budgetCategories
        .where((c) => c.familyId == family.id)
        .toList();

    List<BudgetEntry> shown;
    switch (_filter) {
      case _BudgetFilter.all:
        shown = monthEntries;
        break;
      case _BudgetFilter.income:
        shown = monthEntries.where((e) => e.isIncome).toList();
        break;
      case _BudgetFilter.expenses:
        shown = monthEntries.where((e) => !e.isIncome).toList();
        break;
    }
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      shown = shown.where((e) =>
        e.title.toLowerCase().contains(q) ||
        e.category.name.toLowerCase().contains(q) ||
        e.amount.toStringAsFixed(2).contains(q)
      ).toList();
    }
    shown.sort((a, b) => b.date.compareTo(a.date));

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
        actions: const [],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          // ─── Page Header ───────────────────────────────────────────────
          PageHeader(
            title: 'Family Finance',
            subtitle: 'Track spending, save together, stay balanced.',
            actions: [
              ActionChipButton(
                icon: Icons.file_download_outlined,
                label: 'Import',
                onTap: _showImportSheet,
                backgroundColor: AppTheme.stone100,
                foregroundColor: AppTheme.stone700,
              ),
              ActionChipButton(
                icon: Icons.arrow_drop_down,
                label: 'Export',
                onTap: () => _showExportMenu(
                  entries: allEntries,
                  categories: categories,
                  totalIncome: totalIncome,
                  totalExpenses: totalExpenses,
                  familyName: family.name as String? ?? 'My Family',
                ),
                backgroundColor: AppTheme.stone100,
                foregroundColor: AppTheme.stone700,
              ),
              if (categories.isEmpty)
                ActionChipButton(
                  icon: Icons.warning_amber_rounded,
                  label: 'Add a category first',
                  onTap: _showManageCategories,
                  backgroundColor: const Color(0xFFFFF7ED),
                  foregroundColor: AppTheme.warning,
                ),
              ActionChipButton(
                icon: Icons.add,
                label: 'Add Transaction',
                onTap: _showAddSheet,
                isPrimary: true,
              ),
            ],
          ),

          // ─── Month Navigation ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.stone600),
                  onPressed: () => setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                    _showAllTransactions = false;
                  }),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    final now = DateTime.now();
                    _selectedMonth = DateTime(now.year, now.month);
                    _showAllTransactions = false;
                  }),
                  child: Text(
                    DateFormat('MMMM yyyy').format(_selectedMonth),
                    style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone900),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: AppTheme.stone600),
                  onPressed: () => setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                    _showAllTransactions = false;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ─── Search ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _searchQuery = ''))
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Summary Cards ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Total Income
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.trending_up_rounded, color: AppTheme.success, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL INCOME',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFmt.format(totalIncome),
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.success),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Total Expenses
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.trending_down_rounded, color: AppTheme.error, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL EXPENSES',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFmt.format(totalExpenses),
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Net Savings
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.attach_money_rounded, color: AppTheme.success, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NET SAVINGS',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone400, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currencyFmt.format(net),
                              style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w900, color: net >= 0 ? AppTheme.success : AppTheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── Monthly Targets ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Row(
              children: [
                const Text(
                  'Monthly Targets',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _showManageCategories(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Manage Categories', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.stone100),
                ),
                child: const Center(
                  child: Text(
                    'No categories yet. Add one to set monthly spending targets.',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                children: categories.map((cat) {
                  // Calculate spending for this category in current month
                  final spent = monthEntries
                      .where((e) => !e.isIncome && e.category.name == cat.name)
                      .fold<double>(0, (s, e) => s + e.amount);
                  final pct = cat.limit > 0 ? (spent / cat.limit).clamp(0.0, 1.5) : 0.0;
                  final overBudget = pct > 1.0;
                  final catColor = _categoryColor(cat.color ?? cat.name);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: overBudget ? AppTheme.error.withValues(alpha: 0.3) : AppTheme.stone100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: catColor, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(cat.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800))),
                            Text(
                              '${_formatCurrency(spent)} / ${_formatCurrency(cat.limit)}',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: overBudget ? AppTheme.error : AppTheme.stone500),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor: AppTheme.stone100,
                              valueColor: AlwaysStoppedAnimation(overBudget ? AppTheme.error : catColor),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              cat.limit > 0 ? '${(pct * 100).toStringAsFixed(0)}%' : 'No limit set',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: overBudget ? AppTheme.error : AppTheme.stone400),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          // ─── Recent Activity ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Recent Activity',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.stone900),
                ),
                const SizedBox(width: 8),
                Text(
                  '${shown.length} transactions',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone400),
                ),
              ],
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OnboardingCard(
                emoji: '\u{1F4B0}',
                title: 'Track every dollar as a family',
                bullets: const [
                  'Add transactions manually or import a CSV / PDF bank statement',
                  'Set monthly spending limits per category to stay on budget',
                  'The AI coach reviews your spending and suggests where to save',
                  'Switch between months to compare spending trends over time',
                ],
                actionLabel: 'Add Entry',
                onAction: _showAddSheet,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ...(_showAllTransactions ? shown : shown.take(20)).map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EntryCard(
                        entry: entry,
                        currencyFmt: _currencyFmt,
                        onDelete: () => _deleteEntry(entry.id),
                        onEdit: () => _showEditEntry(entry),
                      ),
                    );
                  }),
                  if (shown.length > 20 && !_showAllTransactions)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: TextButton(
                        onPressed: () => setState(() => _showAllTransactions = true),
                        child: Text(
                          'View All ${shown.length} Transactions',
                          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.primary),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ─── Savings Goals ─────────────────────────────────────────────
          if (savingsGoals.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(children: [
                const Icon(Icons.savings_outlined, size: 20, color: AppTheme.stone500),
                const SizedBox(width: 8),
                const Expanded(child: Text('Savings Goals', style: TextStyle(
                  fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.stone900,
                ))),
                GestureDetector(
                  onTap: _showAddGoalSheet,
                  child: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppTheme.primary),
                ),
              ]),
            ),
            ...savingsGoals.map((goal) {
              final progress = goal.targetAmount > 0 ? (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0) : 0.0;
              final isComplete = goal.savedAmount >= goal.targetAmount && goal.targetAmount > 0;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isComplete ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.stone100),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(goal.icon ?? '\u{1F3AF}', style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(goal.title, style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone800,
                        )),
                      ),
                      if (isComplete)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Complete!', style: TextStyle(
                            fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.success,
                          )),
                        )
                      else
                        GestureDetector(
                          onTap: () => _showAddFundsDialog(context, goal),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('+ Add', style: TextStyle(
                              fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary,
                            )),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _deleteGoal(goal.id),
                        child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.stone300),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: AppTheme.stone100,
                        valueColor: AlwaysStoppedAnimation<Color>(isComplete ? AppTheme.success : AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_currencyFmt.format(goal.savedAmount)} of ${_currencyFmt.format(goal.targetAmount)}',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone400),
                    ),
                  ]),
                ),
              );
            }),
          ],

          // ─── Spending by Category ──────────────────────────────────────
          if (monthEntries.where((e) => !e.isIncome).isNotEmpty)
            _buildSpendingByCategory(monthEntries, totalExpenses),

          // ─── AI Savings Coach Banner ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'AI Savings Coach',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "I've looked at your category limits and spending. Want some tips on where to cut back?",
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => _showAiAnalysis(
                      context,
                      totalIncome: totalIncome,
                      totalExpenses: totalExpenses,
                      entries: monthEntries,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Analyze Spending',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
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
              ? AppTheme.success.withValues(alpha: 0.06)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: goal.isComplete
                ? AppTheme.success.withValues(alpha: 0.3)
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
                      color: AppTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.3)),
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
                      color: AppTheme.primary.withValues(alpha: 0.6), size: 20),
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
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a goal name'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid target amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final current = double.tryParse(_currentCtrl.text.trim()) ?? 0.0;

    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final goal = SavingsGoal(
      id: _uuid.v4(),
      familyId: provider.activeFamily!.id,
      userId: provider.activeUser!.id,
      title: title,
      targetAmount: target,
      savedAmount: current,
      icon: _selectedEmoji,
      completedAt: _deadline,
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
                                  ? AppTheme.primary.withValues(alpha: 0.12)
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
    try {
      final familyId = context.read<AppProvider>().activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() { _loading = false; _error = 'No active family'; });
        return;
      }
      final result = await AiService.analyzeBudget(
        totalIncome: widget.totalIncome,
        totalExpenses: widget.totalExpenses,
        byCategory: widget.byCategory,
        familyId: familyId,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _analysis = result;
          _error = result == null ? 'Could not generate analysis. Please try again.' : null;
        });
      }
    } catch (e) {
      debugPrint('[Budget] AI analysis error: $e');
      if (mounted) setState(() { _loading = false; _error = 'Something went wrong. Please try again.'; });
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
                                color: AppTheme.primary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color:
                                        AppTheme.primary.withValues(alpha: 0.15)),
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
  final VoidCallback? onEdit;

  const _EntryCard(
      {required this.entry,
      required this.currencyFmt,
      required this.onDelete,
      this.onEdit});

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
                color: color.withValues(alpha: 0.1),
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.edit_outlined, size: 14, color: AppTheme.stone400),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
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
        ]),
      ),
    );
  }
}

// ─── Budget Entry Sheet ───────────────────────────────────────────────────────

class _BudgetEntrySheet extends StatefulWidget {
  final Future<void> Function(BudgetEntry) onSave;
  final BudgetEntry? existingEntry;
  const _BudgetEntrySheet({required this.onSave, this.existingEntry});

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
  void initState() {
    super.initState();
    final e = widget.existingEntry;
    if (e != null) {
      _titleCtrl.text = e.title;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _notesCtrl.text = e.notes ?? '';
      _isIncome = e.isIncome;
      _category = e.category;
      _date = e.date;
    }
  }

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
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final existing = widget.existingEntry;
    final entry = BudgetEntry(
      id: existing?.id ?? _uuid.v4(),
      familyId: existing?.familyId ?? provider.activeFamily!.id,
      creatorId: existing?.creatorId ?? provider.activeUser!.id,
      title: _titleCtrl.text.trim(),
      amount: amount,
      category: _category,
      type: _isIncome ? TransactionType.INCOME : TransactionType.EXPENSE,
      date: _date,
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
                  Text(widget.existingEntry != null ? 'Edit Entry' : 'New Entry',
                      style: const TextStyle(
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
                                ? AppTheme.success.withValues(alpha: 0.1)
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
                                ? AppTheme.error.withValues(alpha: 0.1)
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

// ─── AI Bank Statement Import Sheet ───────────────────────────────────────────

class _AiBankStatementImportSheet extends StatefulWidget {
  const _AiBankStatementImportSheet();

  @override
  State<_AiBankStatementImportSheet> createState() => _AiBankStatementImportSheetState();
}

class _AiBankStatementImportSheetState extends State<_AiBankStatementImportSheet> {
  final _textController = TextEditingController();
  bool _loading = false;
  String? _fileName;
  String? _error;
  List<Map<String, dynamic>>? _parsedTransactions;
  // Track which transactions are selected for import
  late List<bool> _selected;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'pdf', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      setState(() { _fileName = file.name; _error = null; });

      String content;
      if (file.path != null) {
        final f = File(file.path!);
        if (file.extension?.toLowerCase() == 'pdf') {
          // For PDF, read bytes and send base64 to AI
          final bytes = await f.readAsBytes();
          content = '[PDF FILE - base64 encoded]\n${base64Encode(bytes)}';
        } else {
          content = await f.readAsString();
        }
      } else if (file.bytes != null) {
        if (file.extension?.toLowerCase() == 'pdf') {
          content = '[PDF FILE - base64 encoded]\n${base64Encode(file.bytes!)}';
        } else {
          content = String.fromCharCodes(file.bytes!);
        }
      } else {
        setState(() => _error = 'Could not read file.');
        return;
      }

      _textController.text = content;
    } catch (e) {
      debugPrint('[Budget] file pick error: $e');
      setState(() => _error = 'Could not open file: $e');
    }
  }

  Future<void> _parseStatement() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste your bank statement text'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() { _loading = true; _parsedTransactions = null; _error = null; });

    final provider = context.read<AppProvider>();
    final existingCategories = BudgetCategory.values.map((c) => c.name).join(', ');

    const systemPrompt =
        'You are a bank statement parser for a personal finance app. Always respond with valid JSON only, no markdown fences.';
    final prompt = '''
Extract every transaction from this bank statement / CSV data. Assign each to one of these categories: $existingCategories.
For each transaction set type to INCOME for credits/deposits and EXPENSE for debits/charges.
amount must always be a positive number. date must be ISO format YYYY-MM-DD.

Return a JSON object:
{
  "transactions": [
    {"date": "YYYY-MM-DD", "description": "string", "amount": number, "type": "INCOME" or "EXPENSE", "category": "string"}
  ]
}

Statement:
$text
''';

    try {
      final familyId = provider.activeFamily?.id;
      if (familyId == null) {
        if (mounted) setState(() { _loading = false; _error = 'No active family'; });
        return;
      }
      final raw = await AiService.ask(prompt: '$systemPrompt\n\n$prompt', feature: 'ai_budget', familyId: familyId);
      if (raw == null || !mounted) {
        if (mounted) setState(() { _loading = false; _error = 'AI could not parse the statement. Try again.'; });
        return;
      }

      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(cleaned.indexOf('\n') + 1);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.lastIndexOf('```'));
      cleaned = cleaned.trim();

      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic> && decoded['transactions'] is List) {
        final txs = (decoded['transactions'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _parsedTransactions = txs;
          _selected = List.filled(txs.length, true);
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = 'Unexpected response format. Try again.'; });
      }
    } catch (e) {
      debugPrint('[Budget] parse statement error: $e');
      if (mounted) setState(() { _loading = false; _error = 'Parse error: $e'; });
    }
  }

  Future<void> _importTransactions() async {
    if (_parsedTransactions == null || _parsedTransactions!.isEmpty) return;

    final provider = context.read<AppProvider>();
    final db = provider.db;
    final userId = provider.activeUser?.id ?? '';
    final familyId = provider.activeFamily?.id ?? '';

    final selectedTxs = <Map<String, dynamic>>[];
    for (var i = 0; i < _parsedTransactions!.length; i++) {
      if (_selected[i]) selectedTxs.add(_parsedTransactions![i]);
    }
    if (selectedTxs.isEmpty) return;

    final newEntries = selectedTxs.map((tx) {
      final category = BudgetCategory.values.firstWhere(
        (c) => c.name == tx['category'],
        orElse: () => BudgetCategory.other,
      );
      final isIncome = (tx['type'] as String?)?.toUpperCase() == 'INCOME';
      DateTime date;
      try {
        date = DateTime.parse(tx['date'] as String);
      } catch (_) {
        date = DateTime.now();
      }

      return BudgetEntry(
        id: const Uuid().v4(),
        familyId: familyId,
        creatorId: userId,
        title: tx['description']?.toString() ?? 'Imported',
        amount: ((tx['amount'] as num?) ?? 0).toDouble().abs(),
        type: isIncome ? TransactionType.INCOME : TransactionType.EXPENSE,
        category: category,
        date: date,
        notes: 'Imported from bank statement',
      );
    }).toList();

    await provider.saveAndSync(db.copyWith(
      budgetEntries: [...db.budgetEntries, ...newEntries],
    ));

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${newEntries.length} transactions!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom + 32;
    final selectedCount = _parsedTransactions != null ? _selected.where((s) => s).length : 0;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.stone200, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text('AI Bank Statement Import', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.stone900)),
            ]),
          ),
          const SizedBox(height: 8),

          // Loading overlay
          if (_loading)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 28),
                ),
                const SizedBox(height: 16),
                const Text('Analysing your statement', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.stone800)),
                const SizedBox(height: 6),
                const Text('AI is reading and categorising your transactions...', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500)),
                const SizedBox(height: 16),
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
            )

          // Input state (no parsed transactions yet)
          else if (_parsedTransactions == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload a CSV or PDF bank statement, or paste data below.',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone500),
                  ),
                  const SizedBox(height: 12),
                  // File picker button
                  GestureDetector(
                    onTap: _pickFile,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: AppTheme.stone50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.stone200, style: BorderStyle.solid),
                      ),
                      child: Column(children: [
                        Icon(Icons.upload_file_rounded, size: 32, color: AppTheme.primary.withValues(alpha: 0.6)),
                        const SizedBox(height: 8),
                        Text(
                          _fileName ?? 'Tap to select CSV or PDF file',
                          style: TextStyle(
                            fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600,
                            color: _fileName != null ? AppTheme.stone800 : AppTheme.stone400,
                          ),
                        ),
                        const Text('Supports .csv, .pdf, .txt', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Or paste text
                  const Text('Or paste data:', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _textController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'Paste bank statement text here...',
                      filled: true,
                      fillColor: AppTheme.stone50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.stone200)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.error)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _parseStatement,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Parse Statement', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          ]

          // Parsed transactions preview with checkboxes
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text(
                  'Found ${_parsedTransactions!.length} transactions',
                  style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.stone700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected = List.filled(_parsedTransactions!.length, true)),
                  child: const Text('Select all', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => setState(() => _selected = List.filled(_parsedTransactions!.length, false)),
                  child: const Text('Deselect', style: TextStyle(fontSize: 12)),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _parsedTransactions!.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.stone100),
                itemBuilder: (_, i) {
                  final tx = _parsedTransactions![i];
                  final isIncome = (tx['type'] as String?)?.toUpperCase() == 'INCOME';
                  final amount = ((tx['amount'] as num?) ?? 0).toDouble();
                  final isSelected = _selected[i];
                  return Opacity(
                    opacity: isSelected ? 1.0 : 0.4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 24, height: 24,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (v) => setState(() => _selected[i] = v ?? false),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 16, color: isIncome ? AppTheme.success : AppTheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tx['description']?.toString() ?? '', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone800), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('${tx['date']} \u00B7 ${tx['category']}', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400)),
                          ]),
                        ),
                        Text(
                          '${isIncome ? '+' : '-'}\$${amount.toStringAsFixed(2)}',
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: isIncome ? AppTheme.success : AppTheme.error),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, padding),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selectedCount > 0 ? _importTransactions : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Import $selectedCount Transaction${selectedCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
          if (_parsedTransactions == null && !_loading) SizedBox(height: padding),
        ],
      ),
    );
  }
}

// ─── Manage Categories Sheet ──────────────────────────────────────────────

class _ManageCategoriesSheet extends StatefulWidget {
  const _ManageCategoriesSheet();

  @override
  State<_ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<_ManageCategoriesSheet> {
  final _nameCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  String _selectedColor = 'blue';
  String? _editingId;
  bool _isSaving = false;

  static const _colorPresets = [
    'amber', 'blue', 'pink', 'emerald', 'purple', 'red', 'cyan',
    'orange', 'teal', 'indigo', 'lime', 'rose', 'sky', 'violet', 'green',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Color _colorForName(String name) => _BudgetScreenState._categoryColors[name.toLowerCase()] ?? const Color(0xFF78716C);

  Future<void> _addCategory() async {
    final name = _nameCtrl.text.trim();
    final limit = double.tryParse(_limitCtrl.text.trim()) ?? 0;
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final cat = BudgetCategoryRecord(
      id: const Uuid().v4(),
      familyId: provider.activeFamily!.id,
      creatorId: provider.activeUser!.id,
      name: name,
      limit: limit,
      color: _selectedColor,
    );
    await provider.saveAndSync(db.copyWith(
      budgetCategories: [...db.budgetCategories, cat],
    ));
    _nameCtrl.clear();
    _limitCtrl.clear();
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _saveEdit(BudgetCategoryRecord cat) async {
    final name = _nameCtrl.text.trim();
    final limit = double.tryParse(_limitCtrl.text.trim()) ?? 0;
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final updated = BudgetCategoryRecord(
      id: cat.id,
      familyId: cat.familyId,
      creatorId: cat.creatorId,
      name: name,
      limit: limit,
      color: _selectedColor,
      visibility: cat.visibility,
    );
    await provider.saveAndSync(db.copyWith(
      budgetCategories: db.budgetCategories.map((c) => c.id == cat.id ? updated : c).toList(),
    ));
    _nameCtrl.clear();
    _limitCtrl.clear();
    if (mounted) setState(() { _editingId = null; _isSaving = false; });
  }

  Future<void> _deleteCategory(BudgetCategoryRecord cat) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final txCount = db.budgetEntries.where((e) => e.category.name == cat.name).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "${cat.name}"${txCount > 0 ? ' and $txCount associated transactions' : ''}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    await provider.saveAndSync(db.copyWith(
      budgetCategories: db.budgetCategories.where((c) => c.id != cat.id).toList(),
    ));
  }

  void _startEdit(BudgetCategoryRecord cat) {
    setState(() {
      _editingId = cat.id;
      _nameCtrl.text = cat.name;
      _limitCtrl.text = cat.limit.toStringAsFixed(0);
      _selectedColor = cat.color ?? 'blue';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final categories = provider.db.budgetCategories
        .where((c) => c.familyId == (provider.activeFamily?.id ?? ''))
        .toList();

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
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              const Icon(Icons.category_rounded, color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('Manage Categories', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 20, color: AppTheme.stone900))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                // Add new category form
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_editingId != null ? 'Edit Category' : 'Add New Category',
                        style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.stone800)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Category name', prefixIcon: Icon(Icons.label_outlined)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _limitCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Monthly budget limit', prefixIcon: Icon(Icons.attach_money_rounded)),
                      ),
                      const SizedBox(height: 10),
                      const Text('Color', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: _colorPresets.map((c) {
                        final color = _colorForName(c);
                        final selected = c == _selectedColor;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = c),
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: selected ? AppTheme.stone900 : Colors.transparent, width: selected ? 2.5 : 0),
                            ),
                            child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                          ),
                        );
                      }).toList()),
                      const SizedBox(height: 12),
                      Row(children: [
                        if (_editingId != null) ...[
                          TextButton(
                            onPressed: () => setState(() { _editingId = null; _nameCtrl.clear(); _limitCtrl.clear(); }),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSaving ? null : () {
                              if (_editingId != null) {
                                final cat = categories.firstWhere((c) => c.id == _editingId);
                                _saveEdit(cat);
                              } else {
                                _addCategory();
                              }
                            },
                            child: _isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_editingId != null ? 'Save' : 'Add'),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('CURRENT CATEGORIES', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppTheme.stone400)),
                const SizedBox(height: 8),
                if (categories.isEmpty)
                  const Center(child: Text('No categories yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.stone400)))
                else
                  ...categories.map((cat) {
                    final color = _colorForName(cat.color ?? cat.name);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.stone100),
                      ),
                      child: Row(children: [
                        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cat.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.stone800)),
                            Text('\$${cat.limit.toStringAsFixed(0)} / month', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400)),
                          ],
                        )),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: AppTheme.stone400,
                          onPressed: () => _startEdit(cat),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          color: AppTheme.error,
                          onPressed: () => _deleteCategory(cat),
                        ),
                      ]),
                    );
                  }),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Report Summary Box ──────────────────────────────────────────────────────

class _ReportSummaryBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  const _ReportSummaryBox({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 11, color: color.withValues(alpha: 0.75))),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ],
        ),
      ),
    );
  }
}
