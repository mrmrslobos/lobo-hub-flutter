import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../config/build_flags.dart';
import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/family_activity_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_echo_tracker.dart';
import '../services/sync_outbox.dart';
import 'auth_provider.dart';
import 'data_provider.dart';

/// Structured sync diagnostics — filter logs by `[CloudSync]` (see docs/sync-repro-matrix.md).
void _cloudSyncLog(String event, [Map<String, Object?> details = const {}]) {
  if (details.isEmpty) {
    debugPrint('[CloudSync] $event');
    return;
  }
  final tail =
      details.entries.map((e) => '${e.key}=${e.value}').join(' ');
  debugPrint('[CloudSync] $event $tail');
}

class SyncProvider extends ChangeNotifier {
  final AuthProvider authProvider;
  final DataProvider dataProvider;

  SyncProvider({required this.authProvider, required this.dataProvider}) {
    dataProvider.onSaveAndSync = saveAndSync;
    dataProvider.onLogFamilyActivity = logFamilyActivity;
    authProvider.registerSyncBridge(
      refreshFromCloud: ({String? familyIdOverride}) =>
          refreshFromCloud(familyIdOverride: familyIdOverride),
      startRealtimeListener: startRealtimeListener,
      stop: stop,
      notifyFamilyScopedChange: notifyFamilyScopedChange,
    );
    SyncOutbox.registerErrorSink(setSyncError);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _postgresChannel;

  bool _isSyncing = false;
  bool _outboundCloudSyncActive = false;
  bool _deferredCloudPull = false;
  Timer? _pullDebounceTimer;
  bool _deferredModulePull = false;
  final Set<String> _deferredModulePullTables = {};
  Timer? _moduleEnterPullTimer;
  final Set<String> _pendingModulePullTables = {};
  
  static const Duration _defaultPullDebounce = Duration(milliseconds: 450);
  static const Duration _fastPullDebounce = Duration(milliseconds: 175);
  static const Duration resumeSyncStaleAfter = Duration(minutes: 3);

  Duration _pullDebounceForTable(String table) =>
      CloudSyncScope.fastRealtimePullTables.contains(table)
          ? _fastPullDebounce
          : _defaultPullDebounce;

  DateTime? _lastSuccessfulSyncAt;
  String? _lastSyncError;
  DateTime? _lastIncrementalPatchAt;
  String? _lastIncrementalPatchTable;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String? get lastSyncError => _lastSyncError;
  DateTime? get lastIncrementalPatchAt => _lastIncrementalPatchAt;
  String? get lastIncrementalPatchTable => _lastIncrementalPatchTable;

  void setOutboundSyncActive(bool active) {
    _outboundCloudSyncActive = active;
    if (active) {
      _isSyncing = true;
    } else {
      _isSyncing = false;
      _flushDeferredCloudPullIfNeeded();
    }
    notifyListeners();
  }

  void setSuccessfulSync() {
    _lastSuccessfulSyncAt = DateTime.now();
    _lastSyncError = null;
    notifyListeners();
  }

  void setSyncError(String error) {
    _lastSyncError = error;
    notifyListeners();
  }

  void clearSyncError() {
    if (_lastSyncError == null) return;
    _lastSyncError = null;
    notifyListeners();
  }

  void startRealtimeListener() {
    _stopRealtimeListener();
    if (BuildFlags.photoframe) {
      return;
    }
    final familyId = authProvider.activeFamily?.id;
    if (familyId == null || !SupabaseService.isConfigured) return;

    _realtimeChannel = SupabaseService.subscribeToFamily(
      familyId,
      onBroadcast: (payload) {
        final senderId = payload['user_id'];
        if (senderId == authProvider.activeUser?.id) return;
        scheduleDebouncedPullFromCloud();
      },
    );

    try {
      var channel = Supabase.instance.client.channel('postgres:$familyId');

      for (final table in CloudSyncScope.realtimeFamilyScopedTables) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            if (_isPostgresSelfEcho(payload)) return;
            _maybeTombstoneFromSoftDelete(payload);
            if (_tryApplyIncrementalRealtime(payload)) return;
            scheduleDebouncedPullFromCloud(_pullDebounceForTable(payload.table));
          },
        );
      }

      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'families',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: familyId,
        ),
        callback: (payload) {
          if (_isPostgresSelfEcho(payload)) return;
          scheduleDebouncedPullFromCloud();
        },
      );
      for (final member in authProvider.familyMembers) {
        final uid = member.userId;
        if (uid.isEmpty) continue;
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: CloudSyncScope.users,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) {
            if (_isPostgresSelfEcho(payload)) return;
            if (_tryApplyIncrementalRealtime(payload)) return;
            scheduleModuleEnterCloudPull({CloudSyncScope.users});
          },
        );
      }

      _postgresChannel = channel.subscribe();
    } catch (e) {
      debugPrint('[SyncProvider] Postgres realtime subscription failed: $e');
    }
  }

  /// Phase 3: patch [tasks] / [messages] / [lists] from realtime payload (no full pull).
  bool _tryApplyIncrementalRealtime(PostgresChangePayload payload) {
    if (!CloudSyncScope.incrementalRealtimeApplyTables
        .contains(payload.table)) {
      return false;
    }
    if (_outboundCloudSyncActive || _isSyncing) return false;
    final familyId = authProvider.activeFamily?.id;
    if (familyId == null) return false;

    final merged = DatabaseService.applyRealtimeRowChange(
      local: dataProvider.db,
      table: payload.table,
      familyId: familyId,
      eventType: payload.eventType,
      newRecord: Map<String, dynamic>.from(payload.newRecord),
      oldRecord: Map<String, dynamic>.from(payload.oldRecord),
    );
    if (merged == null) return false;

    unawaited(_commitIncrementalMerge(merged, payload.table));
    return true;
  }

  Future<void> _commitIncrementalMerge(AppDB merged, String table) async {
    try {
      await dataProvider.updateDb(merged);
      _lastSuccessfulSyncAt = DateTime.now();
      _lastIncrementalPatchAt = _lastSuccessfulSyncAt;
      _lastIncrementalPatchTable = table;
      _lastSyncError = null;
      _cloudSyncLog('realtime_patch_applied', {'table': table});
    } catch (e) {
      debugPrint('[SyncProvider] incremental merge save failed: $e');
      scheduleDebouncedPullFromCloud(_pullDebounceForTable(table));
    } finally {
      notifyListeners();
    }
  }

  /// After profile / member row changes: nudge other devices to pull scoped tables.
  void notifyFamilyScopedChange(Set<String> tables) {
    if (authProvider.activeFamily == null || !SupabaseService.isConfigured) {
      return;
    }
    if (tables.isEmpty) return;
    sendLocalChangeBroadcast();
    scheduleModuleEnterCloudPull(tables);
  }

  /// If the realtime event is an UPDATE that set `deleted_at`, record a
  /// tombstone so the next reconcile drops the row from local state too.
  /// Without this, the post-pull merge keeps B's stale local copy after A
  /// soft-deletes the row (the fetch filter hides it from B's pull).
  void _maybeTombstoneFromSoftDelete(PostgresChangePayload payload) {
    try {
      if (payload.eventType == PostgresChangeEvent.delete) return;
      if (!CloudSyncScope.softDeleteTables.contains(payload.table)) return;
      final row = payload.newRecord;
      final deletedAt = row['deleted_at'];
      if (deletedAt == null || (deletedAt is String && deletedAt.isEmpty)) {
        return;
      }
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) return;
      DatabaseService.markTombstone(id);
    } on Object {
      // Best-effort; the pull still runs.
    }
  }

  /// Drop postgres-change events that echo a row this device just upserted.
  /// Falls back to triggering a pull on any parse failure (safer to over-sync
  /// than miss an event).
  bool _isPostgresSelfEcho(PostgresChangePayload payload) {
    try {
      if (payload.eventType == PostgresChangeEvent.delete) return false;
      final row = payload.newRecord;
      if (row.isEmpty) return false;
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) return false;
      final updatedRaw = row['updated_at'];
      DateTime? updated;
      if (updatedRaw is String && updatedRaw.isNotEmpty) {
        updated = DateTime.tryParse(updatedRaw);
      } else if (updatedRaw is DateTime) {
        updated = updatedRaw;
      }
      if (updated == null) return false;
      return SyncEchoTracker.isSelfEcho(payload.table, id, updated);
    } on Object {
      return false;
    }
  }

  void _stopRealtimeListener() {
    if (_realtimeChannel != null) {
      SupabaseService.unsubscribe(_realtimeChannel!);
      _realtimeChannel = null;
    }
    if (_postgresChannel != null) {
      SupabaseService.unsubscribe(_postgresChannel!);
      _postgresChannel = null;
    }
  }

  void stop() {
    _cancelScheduledCloudPulls();
    _stopRealtimeListener();
  }

  void _cancelScheduledCloudPulls() {
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    _deferredCloudPull = false;
    _moduleEnterPullTimer?.cancel();
    _moduleEnterPullTimer = null;
    _pendingModulePullTables.clear();
    _deferredModulePull = false;
    _deferredModulePullTables.clear();
  }

  void scheduleDebouncedPullFromCloud([Duration debounce = _defaultPullDebounce]) {
    if (authProvider.activeFamily == null || !SupabaseService.isConfigured) return;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = Timer(debounce, () {
      _pullDebounceTimer = null;
      _pullFromCloudNow();
    });
  }

  void scheduleModuleEnterCloudPull([Set<String>? pullTables]) {
    if (authProvider.activeFamily == null || !SupabaseService.isConfigured) return;
    if (pullTables == null || pullTables.isEmpty) {
      scheduleDebouncedPullFromCloud(const Duration(milliseconds: 200));
      return;
    }
    _pendingModulePullTables.addAll(pullTables);
    _moduleEnterPullTimer?.cancel();
    _moduleEnterPullTimer = Timer(const Duration(milliseconds: 200), () {
      _moduleEnterPullTimer = null;
      final scope = Set<String>.from(_pendingModulePullTables);
      _pendingModulePullTables.clear();
      _pullModuleScopedFromCloudNow(scope);
    });
  }

  void _flushDeferredCloudPullIfNeeded() {
    if (!_deferredCloudPull) return;
    _deferredCloudPull = false;
    _cloudSyncLog('pull_flush_deferred');
    scheduleDebouncedPullFromCloud();
  }

  void _flushDeferredModulePullIfNeeded() {
    if (!_deferredModulePull) return;
    _deferredModulePull = false;
    final t = Set<String>.from(_deferredModulePullTables);
    _deferredModulePullTables.clear();
    if (t.isNotEmpty) {
      _pullModuleScopedFromCloudNow(t);
    }
  }

  Future<void> _pullFromCloudNow({String? familyId}) async {
    final fid = familyId ?? authProvider.activeFamily?.id;
    if (fid == null || !SupabaseService.isConfigured) return;
    if (_outboundCloudSyncActive || _isSyncing) {
      _deferredCloudPull = true;
      _cloudSyncLog('pull_deferred', {
        'reason': 'outbound_or_pull_active',
        'familyId': fid,
      });
      return;
    }
    _isSyncing = true;
    notifyListeners();
    try {
      final merged = await DatabaseService.reconcileCloud(
        dataProvider.db,
        fid,
        getLocalAfterFetch: () => dataProvider.db,
      );
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        _lastSyncError = err;
        final snippet = err.length > 240 ? '${err.substring(0, 240)}…' : err;
        _cloudSyncLog('reconcile_error', {'detail': snippet});
        return;
      }
      await dataProvider.updateDb(merged);
      await authProvider.repairOwnerMembershipIfNeeded();
      await authProvider.backfillMissingUsersIfNeeded(
        authProvider.activeFamily?.id ?? fid,
      );
      _lastSuccessfulSyncAt = DateTime.now();
      _lastSyncError = null;
    } catch (e) {
      debugPrint('[SyncProvider] pullFromCloud error: $e');
      _lastSyncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
      _flushDeferredCloudPullIfNeeded();
      _flushDeferredModulePullIfNeeded();
    }
  }

  Future<void> _pullModuleScopedFromCloudNow(Set<String> tables) async {
    final familyId = authProvider.activeFamily?.id;
    if (familyId == null || !SupabaseService.isConfigured || tables.isEmpty) {
      return;
    }
    if (_outboundCloudSyncActive || _isSyncing) {
      _deferredModulePullTables.addAll(tables);
      _deferredModulePull = true;
      _cloudSyncLog('module_pull_deferred', {
        'tables': tables.join(','),
        'familyId': familyId,
      });
      return;
    }
    _isSyncing = true;
    notifyListeners();
    try {
      final merged = await DatabaseService.reconcileCloud(
        dataProvider.db,
        familyId,
        pullTables: tables,
        getLocalAfterFetch: () => dataProvider.db,
      );
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        _lastSyncError = err;
        final snippet = err.length > 240 ? '${err.substring(0, 240)}…' : err;
        _cloudSyncLog('reconcile_error', {'detail': snippet, 'scoped': true});
        return;
      }
      await dataProvider.updateDb(merged);
      await authProvider.repairOwnerMembershipIfNeeded();
      await authProvider.backfillMissingUsersIfNeeded(familyId);
      _lastSuccessfulSyncAt = DateTime.now();
      _lastSyncError = null;
    } catch (e) {
      debugPrint('[SyncProvider] pullModuleScopedFromCloud error: $e');
      _lastSyncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
      _flushDeferredCloudPullIfNeeded();
      _flushDeferredModulePullIfNeeded();
    }
  }

  void onAppResumed() {
    if (!authProvider.isAuthenticated || !SupabaseService.isConfigured) return;
    // Flush any queued writes before pulling so they appear in the next pull.
    unawaited(SyncOutbox.drain());
    final at = _lastSuccessfulSyncAt;
    final hadError = _lastSyncError != null && _lastSyncError!.isNotEmpty;
    final stale = at == null || DateTime.now().difference(at) > resumeSyncStaleAfter;
    if (stale || hadError) {
      refreshFromCloud();
    }
  }

  Future<void> refreshFromCloud({String? familyIdOverride}) async {
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    final fid = familyIdOverride ?? authProvider.activeFamily?.id;
    if (fid == null || !SupabaseService.isConfigured) return;
    if (_outboundCloudSyncActive || _isSyncing) {
      _deferredCloudPull = true;
      _cloudSyncLog('refresh_deferred', {'familyId': fid});
      scheduleDebouncedPullFromCloud(Duration.zero);
      return;
    }
    await _pullFromCloudNow(familyId: fid);
  }

  Future<void> saveAndSync(AppDB newDb, {Set<String>? pushTableScope}) async {
    await dataProvider.updateDb(newDb);
    final fam = authProvider.activeFamily;
    if (fam != null) {
      await syncToCloud(newDb, fam.id, tableScope: pushTableScope);
    }
  }

  Future<void> syncToCloud(AppDB newDb, String familyId, {Set<String>? tableScope}) async {
    final sw = Stopwatch()..start();
    setOutboundSyncActive(true);
    _broadcastChange();
    try {
      await DatabaseService.syncToCloud(newDb, familyId, tableScope: tableScope);
      setSuccessfulSync();
      _broadcastChange();
    } catch (e) {
      setSyncError(e.toString());
      _cloudSyncLog('outbound_error', {'error': e.toString(), 'familyId': familyId});
    } finally {
      sw.stop();
      _cloudSyncLog('outbound_done', {
        'ms': sw.elapsedMilliseconds,
        'familyId': familyId,
        'scopedTables': tableScope == null || tableScope.isEmpty
            ? 'full'
            : tableScope.join(','),
      });
      setOutboundSyncActive(false);
      // Drain any outbox records (e.g. queued soft-deletes from
      // _deleteRemovedRows) so a successful sync also flushes the queue.
      unawaited(SyncOutbox.drain());
    }
  }

  void _broadcastChange() {
    if (_realtimeChannel == null) return;
    try {
      _realtimeChannel!.sendBroadcastMessage(
        event: 'db_change',
        payload: {'user_id': authProvider.activeUser?.id, 'ts': DateTime.now().toIso8601String()},
      );
    } catch (_) {}
  }

  /// After a focused table push (tasks / lists) so other devices pull.
  void sendLocalChangeBroadcast() => _broadcastChange();

  Future<void> logFamilyActivity({
    required String action,
    String? detail,
    String? relatedUserId,
  }) async {
    final fam = authProvider.activeFamily;
    final uid = authProvider.activeUser?.id;
    if (fam == null || uid == null) return;
    final next = FamilyActivityService.append(
      dataProvider.db,
      familyId: fam.id,
      actorUserId: uid,
      action: action,
      detail: detail,
      relatedUserId: relatedUserId,
    );
    await dataProvider.updateDb(next);
    await syncToCloud(next, fam.id, tableScope: {CloudSyncScope.familyActivityLogs});
  }
}
