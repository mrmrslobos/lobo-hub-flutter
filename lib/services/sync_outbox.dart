import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'local_sembast_store.dart';
import 'supabase_service.dart';

/// Operations the outbox can replay.
enum OutboxOp { upsert, softDelete, hardDelete }

/// A single queued write. Coalesced by `(table, rowKey, op)` so a rapid
/// stream of updates to the same row collapses to the latest payload.
class OutboxRecord {
  OutboxRecord({
    required this.id,
    required this.table,
    required this.rowKey,
    required this.op,
    required this.payload,
    required this.queuedAt,
    required this.nextAttemptAt,
    this.onConflict,
    this.attempts = 0,
    this.lastError,
  });

  final String id; // outbox-internal uuid
  final String table; // supabase relation
  final String rowKey; // row PK value (or composite key string)
  final OutboxOp op;
  final Map<String, dynamic> payload;
  final String? onConflict;
  int attempts;
  String? lastError;
  final DateTime queuedAt;
  DateTime nextAttemptAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'rowKey': rowKey,
        'op': op.name,
        'payload': payload,
        'onConflict': onConflict,
        'attempts': attempts,
        'lastError': lastError,
        'queuedAt': queuedAt.toUtc().toIso8601String(),
        'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
      };

  static OutboxRecord? fromJson(Map<String, dynamic> j) {
    try {
      return OutboxRecord(
        id: j['id'] as String,
        table: j['table'] as String,
        rowKey: j['rowKey'] as String,
        op: OutboxOp.values.firstWhere(
          (o) => o.name == (j['op']?.toString() ?? 'upsert'),
          orElse: () => OutboxOp.upsert,
        ),
        payload: Map<String, dynamic>.from(j['payload'] as Map? ?? const {}),
        onConflict: j['onConflict'] as String?,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['lastError'] as String?,
        queuedAt: DateTime.tryParse(j['queuedAt']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        nextAttemptAt:
            DateTime.tryParse(j['nextAttemptAt']?.toString() ?? '') ??
                DateTime.now().toUtc(),
      );
    } on Object {
      return null;
    }
  }
}

/// Persistent per-row push queue with exponential backoff.
///
/// Why: the legacy bulk `syncToCloud` upserts everything in scope. If one
/// row's push fails (RLS, transient 5xx) there's no per-row retry — the
/// next sync re-tries the world implicitly, and we can't tell which rows
/// are actually stuck. The outbox provides:
///   - per-row retry with exponential backoff (1s, 4s, 16s, … cap 1h)
///   - persistence across crashes / restarts
///   - coalescing: rapid edits to the same row collapse to the latest payload
///   - explicit failure reporting via `lastError`
///
/// v1 scope: only soft-deletes route through here. Bulk upserts still use
/// the legacy path. Future PRs can migrate more paths incrementally.
class SyncOutbox {
  SyncOutbox._();

  static const _uuid = Uuid();

  /// Backoff schedule per attempt index (0 = first retry). Capped at 1h.
  static const List<Duration> _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 4),
    Duration(seconds: 16),
    Duration(seconds: 64),
    Duration(seconds: 256),
    Duration(minutes: 17),
    Duration(hours: 1),
  ];

  static final List<OutboxRecord> _records = [];
  static bool _hydrated = false;
  static bool _draining = false;
  static Timer? _scheduledDrain;
  static void Function(String error)? _onError;

  /// Wire an error callback (e.g. SyncProvider.setSyncError) so terminal
  /// failures surface in the UI.
  static void registerErrorSink(void Function(String error) sink) {
    _onError = sink;
  }

  static Future<void> _hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final raw = await LocalSembastStore.readOutbox();
      _records.clear();
      for (final j in raw) {
        final r = OutboxRecord.fromJson(j);
        if (r != null) _records.add(r);
      }
    } on Object catch (e, st) {
      debugPrint('[SyncOutbox] hydrate failed: $e\n$st');
    }
  }

  static Future<void> _persist() async {
    try {
      await LocalSembastStore.writeOutbox(
        _records.map((r) => r.toJson()).toList(),
      );
    } on Object catch (e, st) {
      debugPrint('[SyncOutbox] persist failed: $e\n$st');
    }
  }

  /// Add or coalesce a record. Same `(table, rowKey, op)` replaces the
  /// existing payload (most recent wins) and resets backoff.
  static Future<void> enqueue({
    required String table,
    required String rowKey,
    required OutboxOp op,
    required Map<String, dynamic> payload,
    String? onConflict,
  }) async {
    await _hydrate();
    final now = DateTime.now().toUtc();
    _records.removeWhere(
      (r) => r.table == table && r.rowKey == rowKey && r.op == op,
    );
    _records.add(OutboxRecord(
      id: _uuid.v4(),
      table: table,
      rowKey: rowKey,
      op: op,
      payload: payload,
      onConflict: onConflict,
      queuedAt: now,
      nextAttemptAt: now,
    ));
    await _persist();
  }

  /// How many records are currently queued.
  static Future<int> pendingCount() async {
    await _hydrate();
    return _records.length;
  }

  /// Drain all due records. Each gets a single network attempt; failures
  /// schedule a backoff. Successive calls are safe — only one drain runs
  /// at a time, and a drain in progress causes new calls to no-op.
  static Future<void> drain() async {
    await _hydrate();
    if (_draining) return;
    if (!SupabaseService.isConfigured) return;
    _draining = true;
    try {
      final now = DateTime.now().toUtc();
      final due = _records
          .where((r) => !r.nextAttemptAt.isAfter(now))
          .toList(growable: false);
      for (final rec in due) {
        if (!_records.contains(rec)) continue; // removed by a parallel enqueue
        final ok = await _attempt(rec);
        if (ok) {
          _records.removeWhere((r) => r.id == rec.id);
        } else {
          // Backoff in place; _attempt already updated rec.nextAttemptAt.
        }
      }
      await _persist();
      // If any records are still due (e.g. failed and scheduled for soon),
      // arm a timer so we re-drain without waiting for the next external
      // trigger.
      _scheduleNextDrain();
    } finally {
      _draining = false;
    }
  }

  static Future<bool> _attempt(OutboxRecord rec) async {
    try {
      switch (rec.op) {
        case OutboxOp.upsert:
          await SupabaseService.upsertTable(
            rec.table,
            [rec.payload],
            onConflict: rec.onConflict ?? 'id',
          );
          break;
        case OutboxOp.softDelete:
          final filters = <String, String>{
            for (final e in rec.payload.entries) e.key: e.value.toString(),
          };
          await SupabaseService.softDeleteRows(rec.table, filters);
          break;
        case OutboxOp.hardDelete:
          final filters = <String, String>{
            for (final e in rec.payload.entries) e.key: e.value.toString(),
          };
          await SupabaseService.deleteRows(rec.table, filters);
          break;
      }
      return true;
    } on Object catch (e) {
      final msg = e.toString();
      // PGRST205: table not in schema. Treat as success-equivalent so the
      // record drops out of the queue (same as legacy path's silent skip).
      if (msg.contains('PGRST205') ||
          msg.contains('Could not find the table')) {
        return true;
      }
      rec.attempts += 1;
      rec.lastError = msg;
      final idx = math.min(rec.attempts - 1, _backoff.length - 1);
      final delay = _backoff[idx];
      rec.nextAttemptAt = DateTime.now().toUtc().add(delay);
      _onError?.call(
        'Outbox: ${rec.table}/${rec.rowKey} retry in ${delay.inSeconds}s ($msg)',
      );
      return false;
    }
  }

  static void _scheduleNextDrain() {
    _scheduledDrain?.cancel();
    if (_records.isEmpty) return;
    final now = DateTime.now().toUtc();
    DateTime? nextDue;
    for (final r in _records) {
      if (nextDue == null || r.nextAttemptAt.isBefore(nextDue)) {
        nextDue = r.nextAttemptAt;
      }
    }
    if (nextDue == null) return;
    final delay = nextDue.difference(now);
    if (delay.isNegative) {
      // Something is due now; drain on next tick to avoid synchronous reentry.
      _scheduledDrain = Timer(Duration.zero, drain);
    } else {
      _scheduledDrain = Timer(delay, drain);
    }
  }

  /// Clear the outbox (logout / wipe).
  static Future<void> clear() async {
    _scheduledDrain?.cancel();
    _scheduledDrain = null;
    _records.clear();
    _hydrated = true;
    await _persist();
  }
}
