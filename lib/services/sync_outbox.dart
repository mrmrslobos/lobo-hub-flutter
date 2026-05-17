import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'cloud_upsert_sanitize.dart';
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
/// Family bulk sync (`_syncToCloud`) enqueues most table upserts here, then awaits
/// `drain()` in phases so parallel work only queues (no racy nested drains). Tasks
/// still include a direct bulk `upsert` path in that flow; tombstones and targeted
/// pushes (e.g. `pushFamilyListsToCloudNow`) also use the outbox.
///
/// **Batching:** consecutive due [OutboxOp.upsert] rows for the same `(table,
/// onConflict)` are sent as a single PostgREST upsert (up to [_maxBatchUpsert]).
/// On any batch failure, drain falls back to per-row attempts so RLS/validation
/// errors still map to specific rows.
class SyncOutbox {
  SyncOutbox._();

  static const _uuid = Uuid();

  /// Limit PostgREST upsert payload size per request; larger backlogs are chunked.
  static const int _maxBatchUpsert = 75;

  static dynamic _canonicalJsonValue(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return <String, dynamic>{
        for (final k in keys) k: _canonicalJsonValue(v[k]),
      };
    }
    if (v is List) {
      return v.map(_canonicalJsonValue).toList();
    }
    return v;
  }

  /// Stable equality for coalesce checks (JSON-shaped maps only).
  static bool _payloadMapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    return jsonEncode(_canonicalJsonValue(a)) == jsonEncode(_canonicalJsonValue(b));
  }

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

  /// [_syncToCloud] enqueues many tables in parallel ([Future.wait]); without a
  /// single-writer discipline, overlapping [_persist] calls could snapshot and
  /// flush stale `_records` lists and overwrite newer Sembast state.
  static Future<void> _persistTail = Future<void>.value();

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

  static Future<void> _persist() {
    _persistTail = _persistTail.then((_) async {
      try {
        await LocalSembastStore.writeOutbox(
          _records.map((r) => r.toJson()).toList(),
        );
      } on Object catch (e, st) {
        debugPrint('[SyncOutbox] persist failed: $e\n$st');
      }
    });
    return _persistTail;
  }

  /// Debug/diagnostic: queued row counts grouped by Supabase table name.
  static Future<Map<String, int>> pendingCountsByTable() async {
    await _hydrate();
    final out = <String, int>{};
    for (final r in _records) {
      out[r.table] = (out[r.table] ?? 0) + 1;
    }
    return out;
  }

  /// Add or coalesce a record. Same `(table, rowKey, op)` replaces the
  /// existing payload (most recent wins) and resets backoff.
  ///
  /// If an identical record already exists with the same payload, this is a no-op
  /// so repeated pushes do not churn the queue.
  static Future<void> enqueue({
    required String table,
    required String rowKey,
    required OutboxOp op,
    required Map<String, dynamic> payload,
    String? onConflict,
  }) async {
    await _hydrate();
    for (final r in _records) {
      if (r.table == table && r.rowKey == rowKey && r.op == op) {
        if (_payloadMapsEqual(r.payload, payload)) {
          return;
        }
        break;
      }
    }
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

  /// Drain all due records. Upserts for the same `(table, onConflict)` may be
  /// batched; deletes stay per-row. Failures apply per-row backoff via [_attempt].
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
      var i = 0;
      while (i < due.length) {
        final rec = due[i];
        if (!_records.any((r) => r.id == rec.id)) {
          i++;
          continue;
        }
        if (rec.op == OutboxOp.upsert) {
          final table = rec.table;
          final conflictKey = rec.onConflict ?? 'id';
          final batch = <OutboxRecord>[rec];
          var j = i + 1;
          while (j < due.length && batch.length < _maxBatchUpsert) {
            final next = due[j];
            if (next.op != OutboxOp.upsert ||
                next.table != table ||
                (next.onConflict ?? 'id') != conflictKey) {
              break;
            }
            batch.add(next);
            j++;
          }
          await _flushUpsertBatch(batch);
          i = j;
        } else {
          if (_records.any((r) => r.id == rec.id)) {
            final ok = await _attempt(rec);
            if (ok) {
              _records.removeWhere((r) => r.id == rec.id);
            }
          }
          i++;
        }
      }
      await _persist();
      if (kDebugMode && _records.isNotEmpty) {
        final byTable = <String, int>{};
        for (final r in _records) {
          byTable[r.table] = (byTable[r.table] ?? 0) + 1;
        }
        final dueNow = _records
            .where((r) => !r.nextAttemptAt.isAfter(now))
            .length;
        debugPrint(
          '[SyncOutbox] drain pass finished: ${_records.length} pending '
          '($dueNow due now); by table: $byTable',
        );
      }
      // If any records are still due (e.g. failed and scheduled for soon),
      // arm a timer so we re-drain without waiting for the next external
      // trigger.
      _scheduleNextDrain();
    } finally {
      _draining = false;
    }
  }

  static Future<void> _flushUpsertBatch(List<OutboxRecord> batch) async {
    final present =
        batch.where((r) => _records.any((x) => x.id == r.id)).toList();
    if (present.isEmpty) return;
    final table = present.first.table;
    final onConflict = present.first.onConflict ?? 'id';
    try {
      final payloads = present
          .map((r) => Map<String, dynamic>.from(r.payload))
          .toList(growable: false);
      final sanitized = sanitizeRowsForCloudUpsert(payloads, table);
      await SupabaseService.upsertTable(
        table,
        sanitized,
        onConflict: onConflict,
      );
      for (final r in present) {
        _records.removeWhere((x) => x.id == r.id);
      }
    } on Object {
      for (final r in present) {
        if (!_records.any((x) => x.id == r.id)) continue;
        final ok = await _attempt(r);
        if (ok) {
          _records.removeWhere((x) => x.id == r.id);
        }
      }
    }
  }

  static Future<bool> _attempt(OutboxRecord rec) async {
    try {
      switch (rec.op) {
        case OutboxOp.upsert:
          final sanitized = sanitizeRowsForCloudUpsert(
            [Map<String, dynamic>.from(rec.payload)],
            rec.table,
          );
          await SupabaseService.upsertTable(
            rec.table,
            sanitized,
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
