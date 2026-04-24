// Weekly buckets within a calendar month + rollover (envelope-style).

import '../models/models.dart';

/// Inclusive day range (local calendar dates).
class BudgetWeekDayRange {
  const BudgetWeekDayRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

List<BudgetWeekDayRange> weekBucketsInMonth(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final last = DateTime(month.year, month.month + 1, 0);
  final out = <BudgetWeekDayRange>[];
  var d = first;
  while (!d.isAfter(last)) {
    final end = d.add(const Duration(days: 6));
    final endDay = DateTime(end.year, end.month, end.day);
    final endClamped = endDay.isAfter(last) ? last : endDay;
    out.add(BudgetWeekDayRange(d, endClamped));
    d = endClamped.add(const Duration(days: 1));
  }
  return out;
}

bool _inRange(DateTime t, DateTime start, DateTime end) {
  final d = DateTime(t.year, t.month, t.day);
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  return !d.isBefore(s) && !d.isAfter(e);
}

/// Expenses only, category matched by [BudgetCategory] enum name (same as custom category name match in UI).
double spentInCategoryRange(
  List<BudgetEntry> expenses,
  String categoryName,
  DateTime start,
  DateTime end,
) {
  var s = 0.0;
  for (final e in expenses) {
    if (e.isIncome) continue;
    if (e.category.name != categoryName) continue;
    if (_inRange(e.date, start, end)) s += e.amount;
  }
  return s;
}

double spentInCategoryMonth(
  List<BudgetEntry> expenses,
  String categoryName,
  DateTime month,
) {
  return spentInCategoryRange(
    expenses,
    categoryName,
    DateTime(month.year, month.month, 1),
    DateTime(month.year, month.month + 1, 0),
  );
}

/// Sum of nominal bucket limits for [month] (each full week = [limit], partial = prorated by days).
double sumWeeklyBucketLimits(BudgetCategoryRecord cat, DateTime month) {
  if (cat.limit <= 0) return 0;
  return weekBucketsInMonth(month).fold<double>(0, (sum, b) {
    final days = b.end.difference(b.start).inDays + 1;
    return sum + cat.limit * (days / 7.0);
  });
}

/// Carry rolling out of the last day of [month], given [rolloverIntoMonth] at the first bucket.
double weeklyCarryOutEndOfMonth(
  BudgetCategoryRecord cat,
  List<BudgetEntry> expenses,
  DateTime month,
  double rolloverIntoMonth,
) {
  var carry = rolloverIntoMonth;
  for (final b in weekBucketsInMonth(month)) {
    final days = b.end.difference(b.start).inDays + 1;
    final bucketLimit = cat.limit * (days / 7.0);
    final spent = spentInCategoryRange(expenses, cat.name, b.start, b.end);
    final budget = bucketLimit + carry;
    carry = (budget - spent).clamp(0.0, double.infinity);
  }
  return carry;
}

/// Rollover entering [month] from earlier months (iterative from 60 months back).
double rolloverIntoMonth(
  BudgetCategoryRecord cat,
  List<BudgetEntry> expenses,
  DateTime month,
) {
  if (!cat.rolloverEnabled || cat.limit <= 0) return 0;

  var carry = 0.0;
  var m = DateTime(month.year, month.month - 60, 1);
  final targetPrev = DateTime(month.year, month.month - 1, 1);

  while (!m.isAfter(targetPrev)) {
    if (cat.limitPeriod == BudgetLimitPeriod.monthly) {
      final spent = spentInCategoryMonth(expenses, cat.name, m);
      final budget = cat.limit + carry;
      carry = (budget - spent).clamp(0.0, double.infinity);
    } else {
      carry = weeklyCarryOutEndOfMonth(cat, expenses, m, carry);
    }
    m = DateTime(m.year, m.month + 1, 1);
  }
  return carry;
}

/// Spending cap for [month] (rollover + nominal limits for the period).
double effectiveCapForMonth(
  BudgetCategoryRecord cat,
  List<BudgetEntry> expenses,
  DateTime month,
) {
  if (cat.limit <= 0) return 0;
  final roll = rolloverIntoMonth(cat, expenses, month);
  if (cat.limitPeriod == BudgetLimitPeriod.monthly) {
    return cat.limit + roll;
  }
  return sumWeeklyBucketLimits(cat, month) + roll;
}

/// Human-readable period label for manage UI.
String limitPeriodLabel(BudgetLimitPeriod p) {
  switch (p) {
    case BudgetLimitPeriod.monthly:
      return 'Monthly';
    case BudgetLimitPeriod.weekly:
      return 'Weekly (buckets in month)';
  }
}

/// One row for the weekly-buckets card in the budget UI.
class WeekBucketRow {
  const WeekBucketRow({
    required this.label,
    required this.bucketLimit,
    required this.spent,
    required this.budgetWithCarry,
    required this.carryToNext,
  });
  final String label;
  final double bucketLimit;
  final double spent;
  final double budgetWithCarry;
  final double carryToNext;
}

List<WeekBucketRow> weekBucketRowsForCategory(
  BudgetCategoryRecord cat,
  List<BudgetEntry> expenses,
  DateTime month,
) {
  if (cat.limitPeriod != BudgetLimitPeriod.weekly || cat.limit <= 0) {
    return const [];
  }
  final rollIn = rolloverIntoMonth(cat, expenses, month);
  final buckets = weekBucketsInMonth(month);
  final rows = <WeekBucketRow>[];
  var carry = rollIn;
  for (var i = 0; i < buckets.length; i++) {
    final b = buckets[i];
    final days = b.end.difference(b.start).inDays + 1;
    final bucketLimit = cat.limit * (days / 7.0);
    final spent = spentInCategoryRange(expenses, cat.name, b.start, b.end);
    final budget = bucketLimit + carry;
    final carryNext = (budget - spent).clamp(0.0, double.infinity);
    final startStr = '${b.start.month}/${b.start.day}';
    final endStr = '${b.end.month}/${b.end.day}';
    rows.add(WeekBucketRow(
      label: 'Week ${i + 1} ($startStr–$endStr)',
      bucketLimit: bucketLimit,
      spent: spent,
      budgetWithCarry: budget,
      carryToNext: carryNext,
    ));
    carry = carryNext;
  }
  return rows;
}
