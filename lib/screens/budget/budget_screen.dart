// lib/screens/budget/budget_screen.dart
// Budget / finance screen for FamilyHub
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Visibility;
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
import '../../widgets/subscription_modal.dart';
import '../../utils/debounce.dart';
import '../../utils/budget_envelope.dart' show
    effectiveCapForMonth,
    limitPeriodLabel,
    rolloverIntoMonth,
    weekBucketRowsForCategory;

// ─── Helpers ──────────────────────────────────────────────────────────────────

void _showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

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
  final _searchCtrl = TextEditingController();
  final _searchDebounce = Debouncer();
  String _searchQuery = '';
  bool _showAllTransactions = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _searchCtrl.dispose();
    super.dispose();
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
    HapticFeedback.lightImpact();
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
                _showSnack(ctx, 'Enter an amount greater than \$0');
                return;
              }
              final remaining = goal.targetAmount - goal.savedAmount;
              if (remaining > 0 && amount > remaining) {
                _showSnack(ctx, 'Only \$${remaining.toStringAsFixed(2)} needed to reach the goal');
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

  void _showDebtTrackerSheet(Family family) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DebtTrackerSheet(familyId: family.id),
    );
  }

  void _showFoodBudgetSheet(Family family) {
    final ctrl = TextEditingController(
      text: (family.settings['foodBudgetMonthly'] as num?)?.toString() ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Food budget (monthly)', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Cap for food category',
            hintText: 'e.g. 600',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final v = double.tryParse(ctrl.text.trim());
              final provider = context.read<AppProvider>();
              final db = provider.db;
              final nextSettings = Map<String, dynamic>.from(family.settings);
              if (v == null || v <= 0) {
                nextSettings.remove('foodBudgetMonthly');
              } else {
                nextSettings['foodBudgetMonthly'] = v;
              }
              final next = family.copyWith(settings: nextSettings);
              await provider.saveAndSync(db.copyWith(
                families: db.families.map((f) => f.id == family.id ? next : f).toList(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
    required DateTime reportMonth,
    required List<BudgetEntry> monthExpenseEntries,
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
                leading: const Icon(Icons.text_snippet_rounded, color: AppTheme.primary),
                title: const Text('Copy Full Report', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                subtitle: const Text('Copy formatted summary to clipboard', style: TextStyle(fontSize: 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.stone50,
                onTap: () {
                  Navigator.pop(ctx);
                  _copyReport(
                    entries: entries,
                    categories: categories,
                    totalIncome: totalIncome,
                    totalExpenses: totalExpenses,
                    familyName: familyName,
                    reportMonth: reportMonth,
                    monthExpenseEntries: monthExpenseEntries,
                  );
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
                    reportMonth: reportMonth,
                    monthExpenseEntries: monthExpenseEntries,
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
    if (mounted) _showSnack(context, 'CSV copied to clipboard!');
  }

  void _copyReport({
    required List<BudgetEntry> entries,
    required List<BudgetCategoryRecord> categories,
    required double totalIncome,
    required double totalExpenses,
    required String familyName,
    required DateTime reportMonth,
    required List<BudgetEntry> monthExpenseEntries,
  }) {
    final net = totalIncome - totalExpenses;
    final sorted = List<BudgetEntry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));

    final buf = StringBuffer();
    buf.writeln('$familyName — Finance Report');
    buf.writeln('Generated: ${DateFormat.yMMMd().format(DateTime.now())}');
    buf.writeln('');
    buf.writeln('SUMMARY');
    buf.writeln('  Income:   \$${totalIncome.toStringAsFixed(2)}');
    buf.writeln('  Expenses: \$${totalExpenses.toStringAsFixed(2)}');
    buf.writeln('  Net:      \$${net.toStringAsFixed(2)}');
    buf.writeln('');

    // Spending by category
    final catTotals = <String, double>{};
    for (final e in entries.where((e) => !e.isIncome)) {
      catTotals[e.category.name] = (catTotals[e.category.name] ?? 0) + e.amount;
    }
    if (catTotals.isNotEmpty) {
      buf.writeln('SPENDING BY CATEGORY');
      final sortedCats = catTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final cat in sortedCats) {
        final pct = totalExpenses > 0
            ? (cat.value / totalExpenses * 100).toStringAsFixed(0)
            : '0';
        buf.writeln('  ${cat.key}: \$${cat.value.toStringAsFixed(2)} ($pct%)');
      }
      buf.writeln('');
    }

    buf.writeln('BUDGET TARGETS (${DateFormat('MMMM yyyy').format(reportMonth)})');
    for (final c in categories) {
      if (c.limit <= 0) continue;
      final spent = monthExpenseEntries
          .where((e) => e.category.name == c.name)
          .fold<double>(0, (s, e) => s + e.amount);
      final cap = effectiveCapForMonth(c, entries, reportMonth);
      final roll = rolloverIntoMonth(c, entries, reportMonth);
      buf.writeln(
        '  ${c.name}: ${limitPeriodLabel(c.limitPeriod)} limit \$${c.limit.toStringAsFixed(2)}'
        '${c.rolloverEnabled ? ' · rollover in \$${roll.toStringAsFixed(2)}' : ''}'
        ' · cap \$${cap.toStringAsFixed(2)} · spent \$${spent.toStringAsFixed(2)}',
      );
    }
    buf.writeln('');

    // Transactions list
    buf.writeln('TRANSACTIONS (${sorted.length})');
    for (final e in sorted) {
      final date = DateFormat('MM/dd').format(e.date);
      final sign = e.isIncome ? '+' : '-';
      buf.writeln('  $date  $sign\$${e.amount.toStringAsFixed(2)}  ${e.title}');
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) _showSnack(context, 'Full report copied to clipboard!');
  }

  void _showReportView({
    required List<BudgetEntry> entries,
    required List<BudgetCategoryRecord> categories,
    required double totalIncome,
    required double totalExpenses,
    required String familyName,
    required DateTime reportMonth,
    required List<BudgetEntry> monthExpenseEntries,
  }) {
    final net = totalIncome - totalExpenses;
    final byCategory = <String, double>{};
    for (final e in entries.where((e) => !e.isIncome)) {
      byCategory[e.category.name] = (byCategory[e.category.name] ?? 0) + e.amount;
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
                BudgetCategoryRecord? rec;
                for (final c in categories) {
                  if (c.name == e.key) {
                    rec = c;
                    break;
                  }
                }
                final cap = rec != null && rec.limit > 0
                    ? effectiveCapForMonth(rec, entries, reportMonth)
                    : 0.0;
                final pct = cap > 0 ? (e.value / cap * 100).toStringAsFixed(0) : '—';
                final limLabel = rec == null
                    ? '—'
                    : '${limitPeriodLabel(rec.limitPeriod)} ${_formatCurrency(rec.limit)}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        'Limit $limLabel · Cap ${cap > 0 ? _formatCurrency(cap) : '—'} · Spent ${_formatCurrency(e.value)} · $pct%',
                        style: const TextStyle(fontSize: 11, color: AppTheme.stone500),
                      ),
                    ],
                  ),
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

    final userId = user.id;
    final allEntries = provider.db.budgetEntries
        .where((e) =>
            e.familyId == family.id &&
            (e.visibility == Visibility.FAMILY || (e.visibility == Visibility.PRIVATE && e.creatorId == userId)))
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
        .where((c) =>
            c.familyId == family.id &&
            (c.visibility == Visibility.FAMILY || (c.visibility == Visibility.PRIVATE && c.creatorId == userId)))
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
      // backgroundColor handled by theme
      drawer: const AppDrawer(),
      appBar: const FamilyHubAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
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
                  reportMonth: _selectedMonth,
                  monthExpenseEntries: monthEntries.where((e) => !e.isIncome).toList(),
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
              ActionChipButton(
                icon: Icons.credit_card_rounded,
                label: 'Debts',
                onTap: () => _showDebtTrackerSheet(family),
                backgroundColor: AppTheme.stone100,
                foregroundColor: AppTheme.stone700,
              ),
              ActionChipButton(
                icon: Icons.restaurant_rounded,
                label: 'Food cap',
                onTap: () => _showFoodBudgetSheet(family),
                backgroundColor: AppTheme.stone100,
                foregroundColor: AppTheme.stone700,
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
            child: Semantics(
              label: 'Search transactions',
              textField: true,
              child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _searchDebounce.run(() {
                  if (!mounted) return;
                  setState(() => _searchQuery = v);
                });
              },
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.stone400),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.stone400),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchDebounce.cancel();
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
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
          ),
          const SizedBox(height: 16),

          // ─── Stat Cards ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _MiniStat(
                icon: Icons.trending_up_rounded,
                iconColor: AppTheme.success,
                value: _currencyFmt.format(totalIncome),
                label: 'Income',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.trending_down_rounded,
                iconColor: AppTheme.error,
                value: _currencyFmt.format(totalExpenses),
                label: 'Expenses',
              ),
              const SizedBox(width: 10),
              _MiniStat(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: net >= 0 ? AppTheme.success : AppTheme.error,
                value: _currencyFmt.format(net),
                label: 'Net',
              ),
            ]),
          ),

          Builder(builder: (ctx) {
            final cap = (family.settings['foodBudgetMonthly'] as num?)?.toDouble();
            final foodSpent = monthEntries
                .where((e) => !e.isIncome && e.category == BudgetCategory.food)
                .fold<double>(0, (s, e) => s + e.amount);
            if (cap == null || cap <= 0) return const SizedBox.shrink();
            final frac = (foodSpent / cap).clamp(0.0, 1.5);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.restaurant_rounded, size: 18, color: AppTheme.stone600),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Food spending vs cap',
                            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                        Text(
                          '\$${foodSpent.toStringAsFixed(0)} / \$${cap.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: foodSpent > cap ? AppTheme.error : AppTheme.stone600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: frac > 1 ? 1 : frac,
                        minHeight: 8,
                        backgroundColor: AppTheme.stone100,
                        color: foodSpent > cap ? AppTheme.error : AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 16),

          // ─── Filter Chips ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _FilterChip(label: 'All', selected: _filter == _BudgetFilter.all, onTap: () => setState(() => _filter = _BudgetFilter.all)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Income', selected: _filter == _BudgetFilter.income, onTap: () => setState(() => _filter = _BudgetFilter.income)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Expenses', selected: _filter == _BudgetFilter.expenses, onTap: () => setState(() => _filter = _BudgetFilter.expenses)),
            ]),
          ),

          // ─── Monthly Targets ───────────────────────────────────────────
          Semantics(
            header: true,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Row(
              children: [
                const Text(
                  'Budget targets',
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
                    'No categories yet. Add one to set spending targets (weekly buckets + rollover optional).',
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
                  final cap = cat.limit > 0
                      ? effectiveCapForMonth(cat, allEntries, _selectedMonth)
                      : 0.0;
                  final roll = cat.limit > 0 && cat.rolloverEnabled
                      ? rolloverIntoMonth(cat, allEntries, _selectedMonth)
                      : 0.0;
                  final pct = cap > 0 ? (spent / cap).clamp(0.0, 1.5) : 0.0;
                  final overBudget = pct > 1.0;
                  final catColor = _categoryColor(cat.color ?? cat.name);
                  final weekRows = weekBucketRowsForCategory(cat, allEntries, _selectedMonth);
                  final denom = cap > 0 ? cap : cat.limit;

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
                              denom > 0
                                  ? '${_formatCurrency(spent)} / ${_formatCurrency(denom)}'
                                  : _formatCurrency(spent),
                              style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: overBudget ? AppTheme.error : AppTheme.stone500),
                            ),
                          ]),
                          if (cat.limit > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${limitPeriodLabel(cat.limitPeriod)} · base ${_formatCurrency(cat.limit)}'
                              '${cat.rolloverEnabled && roll > 0 ? ' · rollover in ${_formatCurrency(roll)}' : ''}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone400),
                            ),
                          ],
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: cap > 0 ? pct.clamp(0.0, 1.0) : 0,
                              minHeight: 6,
                              backgroundColor: AppTheme.stone100,
                              valueColor: AlwaysStoppedAnimation(overBudget ? AppTheme.error : catColor),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              cap > 0 ? '${(pct * 100).toStringAsFixed(0)}% of cap' : 'No limit set',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: overBudget ? AppTheme.error : AppTheme.stone400),
                            ),
                          ),
                          if (weekRows.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text('Weeks in this month', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.stone500)),
                            const SizedBox(height: 2),
                            ...weekRows.map((w) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${w.label}: spent ${_formatCurrency(w.spent)} / budget ${_formatCurrency(w.budgetWithCarry)} → carry ${_formatCurrency(w.carryToNext)}',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.stone500, height: 1.25),
                              ),
                            )),
                          ],
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
                  'Set weekly or monthly caps per category, with optional rollover',
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

          // ─── AI Tools ──────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: SectionHeader(title: 'AI TOOLS'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 20, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AI Savings Coach', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.stone900,
                    )),
                    const SizedBox(height: 2),
                    const Text('Get tips on where to cut back.', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500,
                    )),
                  ]),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showAiAnalysis(
                    context,
                    totalIncome: totalIncome,
                    totalExpenses: totalExpenses,
                    entries: monthEntries,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Analyze', style: TextStyle(
                      fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                    )),
                  ),
                ),
              ]),
            ),
          ),
        ],
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
      _showSnack(context, 'Please enter a goal name');
      return;
    }
    if (target == null || target <= 0) {
      _showSnack(context, 'Please enter a valid target amount');
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
    if (SubscriptionModal.guardAI(context)) return;
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
        if (result != null) {
          context.read<AppProvider>().saveAiHistory(module: 'budget', prompt: 'Analyze budget spending', response: result);
        }
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
  Visibility _entryVisibility = Visibility.FAMILY;
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
      _entryVisibility = e.visibility;
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
      _showSnack(context, 'Please enter a title');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack(context, 'Please enter a valid amount');
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
      visibility: _entryVisibility,
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
                  const Text('Visibility', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                  const SizedBox(height: 6),
                  SegmentedButton<Visibility>(
                    segments: [
                      ButtonSegment(value: Visibility.FAMILY, label: const Text('Shared'), icon: const Icon(Icons.group_rounded, size: 18)),
                      ButtonSegment(value: Visibility.PRIVATE, label: const Text('Private'), icon: const Icon(Icons.lock_rounded, size: 18)),
                    ],
                    selected: {_entryVisibility},
                    onSelectionChanged: (s) => setState(() => _entryVisibility = s.first),
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
    if (SubscriptionModal.guardAI(context)) return;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack(context, 'Please paste your bank statement text');
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
      provider.saveAiHistory(module: 'budget', prompt: 'Parse bank statement', response: raw);

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
      _showSnack(context, 'Imported ${newEntries.length} transactions!');
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

// ─── Debt tracker (family.settings['debts']) ─────────────────────────────

class _DebtTrackerSheet extends StatefulWidget {
  final String familyId;
  const _DebtTrackerSheet({required this.familyId});

  @override
  State<_DebtTrackerSheet> createState() => _DebtTrackerSheetState();
}

class _DebtTrackerSheetState extends State<_DebtTrackerSheet> {
  final _nameCtrl = TextEditingController();
  final _balCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '0');
  final _minCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balCtrl.dispose();
    _rateCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _debtsFrom(Family f) {
    final raw = f.settings['debts'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _persist(Family family, List<Map<String, dynamic>> debts) async {
    final provider = context.read<AppProvider>();
    final db = provider.db;
    final next = family.copyWith(
      settings: {...Map<String, dynamic>.from(family.settings), 'debts': debts},
    );
    await provider.saveAndSync(
      db.copyWith(
        families: db.families.map((f) => f.id == family.id ? next : f).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    Family? family;
    for (final f in provider.db.families) {
      if (f.id == widget.familyId) {
        family = f;
        break;
      }
    }
    if (family == null) return const SizedBox.shrink();
    final fam = family;
    final debts = _debtsFrom(fam);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: sc,
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          children: [
            const Text(
              'Debt tracker',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Manual balances (not bank-linked). Stored with your family.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.stone500),
            ),
            const SizedBox(height: 16),
            ...debts.asMap().entries.map((e) {
              final i = e.key;
              final d = e.value;
              final name = d['name']?.toString() ?? 'Debt';
              final bal = (d['balance'] as num?)?.toDouble() ?? 0;
              final rate = (d['aprPercent'] as num?)?.toDouble() ?? 0;
              final minPay = (d['minPayment'] as num?)?.toDouble() ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Balance \$${bal.toStringAsFixed(2)} · APR ${rate.toStringAsFixed(1)}% · Min \$${minPay.toStringAsFixed(2)}/mo',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                  onPressed: () async {
                    final nextList = List<Map<String, dynamic>>.from(debts)..removeAt(i);
                    await _persist(fam, nextList);
                  },
                ),
              );
            }),
            const Divider(height: 32),
            const Text('Add debt', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _balCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Balance', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'APR %', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _minCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Min payment / month', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) return;
                final bal = double.tryParse(_balCtrl.text.trim()) ?? 0;
                final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0;
                final minP = double.tryParse(_minCtrl.text.trim()) ?? 0;
                final nextList = [...debts, {
                  'name': name,
                  'balance': bal,
                  'aprPercent': rate,
                  'minPayment': minP,
                }];
                await _persist(fam, nextList);
                _nameCtrl.clear();
                _balCtrl.clear();
                _rateCtrl.text = '0';
                _minCtrl.text = '0';
              },
              child: const Text('Add'),
            ),
          ],
        ),
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
  Visibility _categoryVisibility = Visibility.FAMILY;
  bool _rolloverEnabled = false;
  BudgetLimitPeriod _limitPeriod = BudgetLimitPeriod.monthly;

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
      visibility: _categoryVisibility,
      rolloverEnabled: _rolloverEnabled,
      limitPeriod: _limitPeriod,
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
      visibility: _categoryVisibility,
      rolloverEnabled: _rolloverEnabled,
      limitPeriod: _limitPeriod,
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
      _categoryVisibility = cat.visibility;
      _rolloverEnabled = cat.rolloverEnabled;
      _limitPeriod = cat.limitPeriod;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final familyId = provider.activeFamily?.id ?? '';
    final userId = provider.activeUser?.id ?? '';
    final categories = provider.db.budgetCategories
        .where((c) =>
            c.familyId == familyId &&
            (c.visibility == Visibility.FAMILY || (c.visibility == Visibility.PRIVATE && c.creatorId == userId)))
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
                        decoration: const InputDecoration(
                          labelText: 'Budget limit amount',
                          helperText: 'Monthly: one cap for the calendar month. Weekly: each week-long bucket in the month (partial weeks prorated).',
                          prefixIcon: Icon(Icons.attach_money_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Period', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                      const SizedBox(height: 6),
                      SegmentedButton<BudgetLimitPeriod>(
                        segments: const [
                          ButtonSegment(value: BudgetLimitPeriod.monthly, label: Text('Monthly')),
                          ButtonSegment(value: BudgetLimitPeriod.weekly, label: Text('Weekly')),
                        ],
                        selected: {_limitPeriod},
                        onSelectionChanged: (s) => setState(() => _limitPeriod = s.first),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Rollover unused budget', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Carry leftover into the next month or week bucket', style: TextStyle(fontSize: 12)),
                        value: _rolloverEnabled,
                        onChanged: (v) => setState(() => _rolloverEnabled = v),
                      ),
                      const SizedBox(height: 12),
                      const Text('Visibility', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.stone500)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: SegmentedButton<Visibility>(
                            segments: [
                              ButtonSegment(value: Visibility.FAMILY, label: const Text('Shared'), icon: const Icon(Icons.group_rounded, size: 18)),
                              ButtonSegment(value: Visibility.PRIVATE, label: const Text('Private'), icon: const Icon(Icons.lock_rounded, size: 18)),
                            ],
                            selected: {_categoryVisibility},
                            onSelectionChanged: (s) => setState(() => _categoryVisibility = s.first),
                          ),
                        ),
                      ]),
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
                            onPressed: () => setState(() {
                              _editingId = null;
                              _nameCtrl.clear();
                              _limitCtrl.clear();
                              _categoryVisibility = Visibility.FAMILY;
                              _rolloverEnabled = false;
                              _limitPeriod = BudgetLimitPeriod.monthly;
                            }),
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
                            Text(
                              '\$${cat.limit.toStringAsFixed(0)} · ${limitPeriodLabel(cat.limitPeriod)}'
                              '${cat.rolloverEnabled ? ' · rollover' : ''}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.stone400),
                            ),
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

// ─── Mini Stat Card ──────────────────────────────────────────────────────────

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
                    fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w900, color: iconColor,
                  ), overflow: TextOverflow.ellipsis),
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

// ─── Filter Chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.stone200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? Colors.white : AppTheme.stone600,
          ),
        ),
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
