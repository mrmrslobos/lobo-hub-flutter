import 'dart:math';

import '../models/models.dart';

/// Per-user prayer: [DevotionalThought] kind prayer, or legacy [DevotionalEntry.userPrayer].
bool devotionalEntryHasPersonalPrayer(
  DevotionalEntry e,
  String? uid,
  List<DevotionalThought> thoughts,
) {
  if (uid != null) {
    for (final t in thoughts) {
      if (t.devotionalId == e.id &&
          t.userId == uid &&
          t.kind == DevotionalNoteKind.prayer &&
          t.body.trim().isNotEmpty) {
        return true;
      }
    }
  }
  return e.userPrayer != null && e.userPrayer!.trim().isNotEmpty;
}

/// 1-based day indices the user has completed (synced row ∪ prayer on each entry).
Set<int> readingPlanCompletedDaySet(
  ReadingPlan plan,
  String? userId,
  AppDB db,
) {
  if (userId == null || userId.isEmpty) return {};
  final n = plan.entryIds.length;
  if (n == 0) return {};
  final progId = ReadingPlanProgress.stableId(plan.id, userId);
  ReadingPlanProgress? prog;
  for (final p in db.readingPlanProgress) {
    if (p.id == progId) {
      prog = p;
      break;
    }
  }
  final done = <int>{};
  if (prog != null) {
    done.addAll(prog.completedDayNumbers.where((d) => d >= 1 && d <= n));
  }
  for (var i = 0; i < plan.entryIds.length; i++) {
    final dayNum = i + 1;
    if (done.contains(dayNum)) continue;
    final devId = plan.entryIds[i];
    DevotionalEntry? entry;
    for (final e in db.devotionals) {
      if (e.id == devId) {
        entry = e;
        break;
      }
    }
    if (entry != null &&
        devotionalEntryHasPersonalPrayer(entry, userId, db.devotionalThoughts)) {
      done.add(dayNum);
    }
  }
  return done;
}

/// Completed plan days for [userId]: synced `reading_plan_progress` ∪ prayer-based detection.
int readingPlanEffectiveCompletedDays(
  ReadingPlan plan,
  String? userId,
  AppDB db,
) =>
    readingPlanCompletedDaySet(plan, userId, db).length;

bool readingPlanDayIsDone(
  ReadingPlan plan,
  String? userId,
  AppDB db,
  int zeroBasedDayIndex,
) {
  if (zeroBasedDayIndex < 0) return false;
  return readingPlanCompletedDaySet(plan, userId, db)
      .contains(zeroBasedDayIndex + 1);
}

int _currentStreakFromDayOne(List<int> sortedUnique) {
  var streak = 0;
  var expect = 1;
  for (final d in sortedUnique) {
    if (d != expect) break;
    streak++;
    expect++;
  }
  return streak;
}

int _longestRunOfConsecutive(List<int> sortedUnique) {
  if (sortedUnique.isEmpty) return 0;
  var best = 1;
  var run = 1;
  for (var i = 1; i < sortedUnique.length; i++) {
    if (sortedUnique[i] == sortedUnique[i - 1]) continue;
    if (sortedUnique[i] == sortedUnique[i - 1] + 1) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

/// Upserts per-plan progress when a user's prayer state changes for [devotionalId].
AppDB applyReadingPlanProgressAfterPrayerChange(
  AppDB db, {
  required String userId,
  required String familyId,
  required String devotionalId,
  required bool hasPrayer,
}) {
  var list = db.readingPlanProgress.toList();

  for (final plan in db.readingPlans) {
    if (plan.familyId != familyId) continue;
    final idx = plan.entryIds.indexOf(devotionalId);
    if (idx < 0) continue;
    final dayNum = idx + 1;
    final id = ReadingPlanProgress.stableId(plan.id, userId);
    ReadingPlanProgress? existing;
    var existingIndex = -1;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == id) {
        existing = list[i];
        existingIndex = i;
        break;
      }
    }

    final days = {...?existing?.completedDayNumbers};
    if (hasPrayer) {
      days.add(dayNum);
    } else {
      days.remove(dayNum);
    }
    final sorted = days.toList()..sort();
    if (sorted.isEmpty) {
      if (existingIndex >= 0) list.removeAt(existingIndex);
      continue;
    }

    final now = DateTime.now().toUtc();
    final started = existing?.startedAt ?? now;
    final lastCompleted = sorted.isNotEmpty ? now : existing?.lastCompletedAt;
    final cur = _currentStreakFromDayOne(sorted);
    final runLongest = _longestRunOfConsecutive(sorted);
    final nextLongest = max(
      runLongest,
      existing?.longestStreak ?? 0,
    );
    final row = ReadingPlanProgress(
      id: id,
      planId: plan.id,
      userId: userId,
      familyId: familyId,
      completedDayNumbers: sorted,
      currentStreak: cur,
      longestStreak: nextLongest,
      startedAt: started,
      lastCompletedAt: lastCompleted,
    );
    if (existingIndex >= 0) {
      list[existingIndex] = row;
    } else {
      list.add(row);
    }
  }

  return db.copyWith(readingPlanProgress: list);
}
