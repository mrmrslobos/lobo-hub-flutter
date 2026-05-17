#!/usr/bin/env python3
"""Refactor _syncToCloud: enqueue in parallel, then one SyncOutbox.drain, tombstones, drain."""

import re
from typing import Optional

PATH = r"C:\Users\wsda\Documents\lobo-hub-flutter\lib\services\database_service.dart"


def matching_close_paren(s: str, open_idx: int) -> int:
    depth = 0
    quote: Optional[str] = None
    i = open_idx
    while i < len(s):
        ch = s[i]
        if quote:
            if ch == "\\" and quote != "'":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise SystemExit(f"unbalanced parens @ {open_idx}")


def split_top_level_commas(inner: str) -> list[str]:
    parts: list[str] = []
    buf: list[str] = []
    depth_paren = depth_bracket = depth_brace = 0
    i = 0
    quote: Optional[str] = None
    while i < len(inner):
        ch = inner[i]
        if quote:
            buf.append(ch)
            if ch == "\\":
                i += 1
                if i < len(inner):
                    buf.append(inner[i])
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "(":
            depth_paren += 1
        elif ch == ")":
            depth_paren -= 1
        elif ch == "[":
            depth_bracket += 1
        elif ch == "]":
            depth_bracket -= 1
        elif ch == "{":
            depth_brace += 1
        elif ch == "}":
            depth_brace -= 1

        combined = depth_paren + depth_bracket + depth_brace
        if (
            ch == ","
            and combined == 0
            and not quote
        ):
            parts.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    if buf:
        parts.append("".join(buf))
    return parts


def strip_trailing_db_id_args(blob: str) -> str:
    pat = re.compile(r"_outboxEnqueue(Family|User)Upserts\(")
    out_parts: list[str] = []
    cur = 0
    while True:
        m = pat.search(blob, cur)
        if not m:
            out_parts.append(blob[cur:])
            break
        out_parts.append(blob[cur : m.start()])
        open_paren = m.end() - 1
        close_paren = matching_close_paren(blob, open_paren)
        inner = blob[open_paren + 1 : close_paren]
        prefix = blob[m.start() : m.end()]
        raw_args = split_top_level_commas(inner)
        trimmed = list(raw_args)
        if (
            len(raw_args) >= 2
            and "onConflict:" not in raw_args[-1]
            and re.match(r"\s*db\.", raw_args[-1]) is not None
        ):
            trimmed = raw_args[:-1]
        new_inner = ",".join(trimmed)
        out_parts.append(prefix + new_inner + ")")
        cur = close_paren + 1
    return "".join(out_parts)


def main() -> None:
    s = open(PATH, encoding="utf-8").read()

    old_helpers = """  static Future<void> _outboxUpsertRowsAndCleanFamily(
    String table,
    String familyId,
    List<Map<String, dynamic>> rows,
    Set<String> localIds, {
    String onConflict = 'id',
  }) async {
    for (final raw in rows) {
      final row = sanitizeRowsForCloudUpsert(
        [Map<String, dynamic>.from(raw)],
        table,
      ).first;
      final key = row['id']?.toString();
      if (key == null || key.isEmpty) continue;
      await SyncOutbox.enqueue(
        table: table,
        rowKey: key,
        op: OutboxOp.upsert,
        payload: row,
        onConflict: onConflict,
      );
    }
    await SyncOutbox.drain();
    await _deleteRemovedRows(table, localIds, familyId);
  }

  static Future<void> _outboxUpsertRowsAndCleanUser(
    String table,
    String userId,
    List<Map<String, dynamic>> rows,
    Set<String> localIds, {
    String onConflict = 'id',
  }) async {
    for (final raw in rows) {
      final row = sanitizeRowsForCloudUpsert(
        [Map<String, dynamic>.from(raw)],
        table,
      ).first;
      final key = row['id']?.toString();
      if (key == null || key.isEmpty) continue;
      await SyncOutbox.enqueue(
        table: table,
        rowKey: key,
        op: OutboxOp.upsert,
        payload: row,
        onConflict: onConflict,
      );
    }
    await SyncOutbox.drain();
    await _deleteRemovedUserRows(table, localIds, userId);
  }

"""

    new_helpers = """  static Future<void> _outboxEnqueueFamilyUpserts(
    String table,
    List<Map<String, dynamic>> rows, {
    String onConflict = 'id',
  }) async {
    for (final raw in rows) {
      final row = sanitizeRowsForCloudUpsert(
        [Map<String, dynamic>.from(raw)],
        table,
      ).first;
      final key = row['id']?.toString();
      if (key == null || key.isEmpty) continue;
      await SyncOutbox.enqueue(
        table: table,
        rowKey: key,
        op: OutboxOp.upsert,
        payload: row,
        onConflict: onConflict,
      );
    }
  }

  static Future<void> _outboxEnqueueUserUpserts(
    String table,
    List<Map<String, dynamic>> rows, {
    String onConflict = 'id',
  }) async {
    for (final raw in rows) {
      final row = sanitizeRowsForCloudUpsert(
        [Map<String, dynamic>.from(raw)],
        table,
      ).first;
      final key = row['id']?.toString();
      if (key == null || key.isEmpty) continue;
      await SyncOutbox.enqueue(
        table: table,
        rowKey: key,
        op: OutboxOp.upsert,
        payload: row,
        onConflict: onConflict,
      );
    }
  }

"""

    if old_helpers not in s:
        raise SystemExit("_outboxUpsertRows* block not found (already migrated?)")

    s = s.replace(old_helpers, new_helpers, 1)

    s = s.replace(
        """  static Future<void> _deleteRemovedRows(
    String table, Set<String> localIds, String familyId,
  ) async {""",
        """  static Future<void> _deleteRemovedRows(
    String table, Set<String> localIds, String familyId, {
    bool deferOutboxDrain = false,
  }) async {""",
        1,
    )

    s = s.replace(
        """      if (removed.isNotEmpty) {
        // Best-effort immediate drain; failures stay queued for later.
        unawaited(SyncOutbox.drain());
      }
    } on Object catch (e, st) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e\\n$st');
    }
  }

  /// Delete cloud rows for a user-scoped table""",
        """      if (removed.isNotEmpty && !deferOutboxDrain) {
        // Best-effort immediate drain; failures stay queued for later.
        unawaited(SyncOutbox.drain());
      }
    } on Object catch (e, st) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e\\n$st');
    }
  }

  /// Delete cloud rows for a user-scoped table""",
        1,
    )

    s = s.replace(
        """  static Future<void> _deleteRemovedUserRows(
    String table,
    Set<String> localIds,
    String userId,
  ) async {""",
        """  static Future<void> _deleteRemovedUserRows(
    String table,
    Set<String> localIds,
    String userId, {
    bool deferOutboxDrain = false,
  }) async {""",
        1,
    )

    s = s.replace(
        """      if (removed.isNotEmpty) {
        unawaited(SyncOutbox.drain());
      }
    } on Object catch (e, st) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e\\n$st');
    }
  }

  // ── Cloud reconcile ───────────────────────────────────────────────────────""",
        """      if (removed.isNotEmpty && !deferOutboxDrain) {
        unawaited(SyncOutbox.drain());
      }
    } on Object catch (e, st) {
      final msg = e.toString();
      if (msg.contains('PGRST205') || msg.contains('Could not find the table')) {
        return; // table not in this project's schema — skip quietly
      }
      debugPrint('[DatabaseService] Failed to delete removed $table rows: $e\\n$st');
    }
  }

  // ── Cloud reconcile ───────────────────────────────────────────────────────""",
        1,
    )

    s = s.replace(
        """      if (pick('devotional_thoughts'))
        (() async {
          final thoughtRows = db.devotionalThoughts
              .where((t) => t.familyId == fid)
              .map((t) => {...t.toJson(), 'family_id': fid})
              .toList();
          final thoughtIds = db.devotionalThoughts
              .where((t) => t.familyId == fid)
              .map((t) => t.id)
              .toSet();
          await _outboxUpsertRowsAndCleanFamily(
            'devotional_thoughts',
            fid,
            thoughtRows,
            thoughtIds,
            onConflict: 'devotional_id,user_id,note_kind',
          );
        })(),""",
        """      if (pick('devotional_thoughts'))
        _outboxEnqueueFamilyUpserts(
          'devotional_thoughts',
          db.devotionalThoughts
              .where((t) => t.familyId == fid)
              .map((t) => {...t.toJson(), 'family_id': fid})
              .toList(),
          onConflict: 'devotional_id,user_id,note_kind',
        ),""",
        1,
    )

    s = s.replace(
        """      if (pick('tasks'))
        (() async {
          final taskRows = db.tasks
              .where((t) => t.familyId == fid)
              .map((t) => t.toJson())
              .toList();
          await up('tasks', taskRows, onConflict: 'id');
          await _deleteRemovedRows(
            'tasks',
            db.tasks
                .where((t) => t.familyId == fid)
                .map((t) => t.id)
                .toSet(),
            fid,
          );
        })(),""",
        """      if (pick('tasks'))
        (() async {
          final taskRows = db.tasks
              .where((t) => t.familyId == fid)
              .map((t) => t.toJson())
              .toList();
          await up('tasks', taskRows, onConflict: 'id');
        })(),""",
        1,
    )

    s = s.replace(
        """      if (pick('lists'))
        (() async {
          final familyLists =
              db.lists.where((l) => l.familyId == fid).toList();
          final localIds = familyLists.map((l) => l.id).toSet();
          for (final l in familyLists) {
            final row = sanitizeRowsForCloudUpsert(
              [_shoppingListRowForCloud(l, fid)],
              'lists',
            ).first;
            await SyncOutbox.enqueue(
              table: 'lists',
              rowKey: l.id,
              op: OutboxOp.upsert,
              payload: row,
              onConflict: 'id',
            );
          }
          await SyncOutbox.drain();
          await _deleteRemovedRows('lists', localIds, fid);
        })(),""",
        """      if (pick('lists'))
        (() async {
          final familyLists =
              db.lists.where((l) => l.familyId == fid).toList();
          for (final l in familyLists) {
            final row = sanitizeRowsForCloudUpsert(
              [_shoppingListRowForCloud(l, fid)],
              'lists',
            ).first;
            await SyncOutbox.enqueue(
              table: 'lists',
              rowKey: l.id,
              op: OutboxOp.upsert,
              payload: row,
              onConflict: 'id',
            );
          }
        })(),""",
        1,
    )

    if "_outboxUpsertRowsAndCleanFamily(" in s or "_outboxUpsertRowsAndCleanUser(" in s:
        s = re.sub(
            r"_outboxUpsertRowsAndCleanFamily\('([^']+)',\s*fid,\s*",
            r"_outboxEnqueueFamilyUpserts('\1', ",
            s,
        )
        s = re.sub(
            r"_outboxUpsertRowsAndCleanUser\('([^']+)',\s*currentUserId,\s*",
            r"_outboxEnqueueUserUpserts('\1', ",
            s,
        )

    s = strip_trailing_db_id_args(s)

    phase2 = """

    await SyncOutbox.drain();

    await Future.wait([
      if (pick('tasks'))
        _deleteRemovedRows(
          'tasks',
          db.tasks
              .where((t) => t.familyId == fid)
              .map((t) => t.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('events'))
        _deleteRemovedRows(
          'events',
          db.events.map((e) => e.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('recipes'))
        _deleteRemovedRows(
          'recipes',
          db.recipes.map((r) => r.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('meal_plans'))
        _deleteRemovedRows(
          'meal_plans',
          db.mealPlans
              .where((m) => m.familyId == fid)
              .map((m) => m.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('lists'))
        _deleteRemovedRows(
          'lists',
          db.lists
              .where((l) => l.familyId == fid)
              .map((l) => l.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('devotionals'))
        _deleteRemovedRows(
          'devotionals',
          db.devotionals.map((d) => d.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('devotional_thoughts'))
        _deleteRemovedRows(
          'devotional_thoughts',
          db.devotionalThoughts
              .where((t) => t.familyId == fid)
              .map((t) => t.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (currentUserId != null && pick('fitness'))
        _deleteRemovedUserRows(
          'fitness',
          db.fitness
              .where((f) => f.userId == currentUserId)
              .map((f) => f.id)
              .toSet(),
          currentUserId,
          deferOutboxDrain: true,
        ),
      if (currentUserId != null && pick('fitness_plans'))
        _deleteRemovedUserRows(
          'fitness_plans',
          db.fitnessPlans
              .whereType<Map>()
              .where((p) => p['user_id'] == currentUserId)
              .map((p) => fitnessPlanCloudRowId(p, fid))
              .toSet(),
          currentUserId,
          deferOutboxDrain: true,
        ),
      if (pick('fitness_logs'))
        _deleteRemovedRows(
          'fitness_logs',
          db.fitnessLogs
              .where((l) =>
                  l.familyId == fid &&
                  l.userId == SupabaseService.currentUser?.id)
              .map((l) => l.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('workout_sessions'))
        _deleteRemovedRows(
          'workout_sessions',
          db.workoutSessions
              .where((s) =>
                  s.familyId == fid &&
                  s.userId == SupabaseService.currentUser?.id)
              .map((s) => s.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('workout_exercises'))
        _deleteRemovedRows(
          'workout_exercises',
          db.workoutExercises
              .where((e) =>
                  e.familyId == fid &&
                  e.userId == SupabaseService.currentUser?.id)
              .map((e) => e.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('workout_sets'))
        _deleteRemovedRows(
          'workout_sets',
          db.workoutSets
              .where((set) =>
                  set.familyId == fid &&
                  set.userId == SupabaseService.currentUser?.id)
              .map((set) => set.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('exercise_prs'))
        _deleteRemovedRows(
          'exercise_prs',
          db.exercisePrs
              .where((p) => p.familyId == fid)
              .map((p) => p.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('budget_categories'))
        _deleteRemovedRows(
          'budget_categories',
          db.budgetCategories.map((b) => b.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('budget_entries'))
        _deleteRemovedRows(
          'budget_entries',
          db.budgetEntries.map((b) => b.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('transactions'))
        _deleteRemovedRows(
          'transactions',
          db.transactions.map((t) => t.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('ai_history'))
        _deleteRemovedRows(
          'ai_history',
          db.aiHistory.map((a) => a.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('daily_habits'))
        _deleteRemovedRows(
          'daily_habits',
          db.dailyHabits.map((h) => h.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (currentUserId != null && pick('daily_habit_completions'))
        _deleteRemovedUserRows(
          'daily_habit_completions',
          db.dailyHabitCompletions
              .where((c) => c.userId == currentUserId)
              .map((c) => c.id)
              .toSet(),
          currentUserId,
          deferOutboxDrain: true,
        )
      else
        Future.value(),
      if (pick('chores'))
        _deleteRemovedRows(
          'chores',
          db.chores
              .where((c) => c.familyId == fid)
              .map((c) => c.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('chore_completions'))
        _deleteRemovedRows(
          'chore_completions',
          db.choreCompletions.map((c) => c.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('polls'))
        _deleteRemovedRows(
          'polls',
          db.polls.map((p) => p.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('poll_votes'))
        _deleteRemovedRows(
          'poll_votes',
          db.pollVotes.map((v) => v.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('reward_items'))
        _deleteRemovedRows(
          'reward_items',
          db.rewardItems.map((r) => r.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('reward_redemptions'))
        _deleteRemovedRows(
          'reward_redemptions',
          db.rewardRedemptions.map((r) => r.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('savings_goals'))
        _deleteRemovedRows(
          'savings_goals',
          db.savingsGoals.map((g) => g.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('prayer_wall'))
        _deleteRemovedRows(
          'prayer_wall',
          db.prayerWall.map((p) => p.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('special_dates'))
        _deleteRemovedRows(
          'special_dates',
          db.specialDates.map((s) => s.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('family_photos'))
        _deleteRemovedRows(
          'family_photos',
          db.familyPhotos.map((p) => p.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('milestones'))
        _deleteRemovedRows(
          'milestones',
          db.milestones.map((m) => m.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('saved_places'))
        _deleteRemovedRows(
          'saved_places',
          db.savedPlaces.map((s) => s.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('user_locations'))
        _deleteRemovedRows(
          'user_locations',
          db.userLocations.map((u) => u.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('messages'))
        _deleteRemovedRows(
          'messages',
          db.messages.map((m) => m.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('health_records'))
        _deleteRemovedRows(
          'health_records',
          db.healthRecords.map((h) => h.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('period_cycles'))
        _deleteRemovedRows(
          'period_cycles',
          db.periodCycles.map((c) => c.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('period_symptoms'))
        _deleteRemovedRows(
          'period_symptoms',
          db.periodSymptoms.map((s) => s.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('external_calendars'))
        _deleteRemovedRows(
          'external_calendars',
          db.externalCalendars.map((c) => c.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('rewards'))
        _deleteRemovedRows(
          'rewards',
          db.rewards.map((r) => r.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('reading_plans'))
        _deleteRemovedRows(
          'reading_plans',
          db.readingPlans.map((r) => r.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('reading_plan_progress'))
        _deleteRemovedRows(
          'reading_plan_progress',
          db.readingPlanProgress.map((r) => r.id).toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('pantry_items'))
        _deleteRemovedRows(
          'pantry_items',
          db.pantryItems
              .where((p) => p.familyId == fid)
              .map((p) => p.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('family_activity_logs'))
        _deleteRemovedRows(
          'family_activity_logs',
          db.familyActivityLogs
              .where((a) => a.familyId == fid)
              .map((a) => a.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
      if (pick('wellness_check_ins'))
        _deleteRemovedRows(
          'wellness_check_ins',
          db.wellnessCheckIns
              .where((w) => w.familyId == fid)
              .map((w) => w.id)
              .toSet(),
          fid,
          deferOutboxDrain: true,
        ),
    ]);
    await SyncOutbox.drain();
"""

    anchor = "    ]);\n  }\n\n  /// Collapse duplicate"
    if anchor not in s:
        raise SystemExit("closing anchor not found")
    if "deferOutboxDrain: true" in s and "Outbox upserts enqueue in parallel" in s:
        raise SystemExit("file already has phased drain — abort")
    s = s.replace(anchor, "    ]);" + phase2 + "\n  }\n\n  /// Collapse duplicate", 1)

    marker = "// All other tables in parallel"
    if marker in s:
        s = s.replace(
            marker,
            "// Outbox upserts enqueue in parallel; drains + tombstones follow below",
            1,
        )

    open(PATH, "w", encoding="utf-8").write(s)
    print("wrote", PATH)


if __name__ == "__main__":
    main()
