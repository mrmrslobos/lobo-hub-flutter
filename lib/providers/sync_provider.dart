import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../config/build_flags.dart';
import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/family_activity_service.dart';
import '../services/field_encryption_service.dart';
import '../services/pending_cloud_sync_hints.dart';
import '../services/supabase_service.dart';
import '../services/sync_echo_tracker.dart';
import '../services/sync_outbox.dart';
import 'auth_provider.dart';
import 'data_provider.dart';

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
    );
    SyncOutbox.registerErrorSink(setSyncError);
    unawaited(_refreshPendingOutboxCount());
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
  Timer? _realtimePullCoalesceTimer;
  final Set<String> _pendingRealtimePullTables = {};

  /// Default debounce for manual / broadcast-driven pulls (coalesce bursts).
  static const Duration _defaultPullDebounce = Duration(milliseconds: 450);
  /// Tighter coalescing for postgres_changes (still batches multi-table bursts).
  static const Duration _postgresRealtimePullDebounce = Duration(milliseconds: 120);
  static const Duration _broadcastPullDebounce = Duration(milliseconds: 450);
  /// After inbound work was deferred during outbound sync, flush without another long wait.
  static const Duration _deferredFlushDebounce = Duration(milliseconds: 50);
  static const Duration resumeSyncStaleAfter = Duration(minutes: 3);

  DateTime? _lastSuccessfulSyncAt;
  String? _lastSyncError;

  int _pendingOutboxCount = 0;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String? get lastSyncError => _lastSyncError;

  /// Best-effort count of queued outbox rows (includes soft-deletes and migrated upserts).
  ///
  /// Refreshed when [notifyListeners] runs and after [syncToCloud] flushes the outbox.
  int get pendingOutboxCount => _pendingOutboxCount;

  Future<void> _refreshPendingOutboxCount() async {
    final n = await SyncOutbox.pendingCount();
    if (_pendingOutboxCount == n) return;
    _pendingOutboxCount = n;
    super.notifyListeners();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    unawaited(_refreshPendingOutboxCount());
  }

  /// Best-effort flush of the durable outbox + refresh [pendingOutboxCount].
  Future<void> flushOutboxNow() async {
    await SyncOutbox.drain();
    await _refreshPendingOutboxCount();
  }

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

    if (kDebugMode) {
      debugPrint(
        '[SyncProvider] startRealtimeListener: family=$familyId (AuthProvider bridge)',
      );
    }

    _realtimeChannel = SupabaseService.subscribeToFamily(
      familyId,
      onDbChange: (payload) {
        final senderId = payload['user_id'];
        if (senderId == authProvider.activeUser?.id) return;
        scheduleDebouncedPullFromCloud(_broadcastPullDebounce);
      },
      onActivityHint: _onFamilyActivityHintBroadcast,
    );

    unawaited(_consumePendingPrefetchHints());

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
          callback: _onFamilyScopedPostgresChange,
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
        callback: _onFamilyScopedPostgresChange,
      );
      _postgresChannel = channel.subscribe((status, error) {
        if (!kDebugMode) return;
        if (status == RealtimeSubscribeStatus.subscribed) {
          final n = CloudSyncScope.realtimeFamilyScopedTables.length;
          debugPrint(
            '[SyncProvider] Postgres realtime subscribed for family $familyId '
            '($n family-scoped tables + families). '
            'Publication must list these tables; RLS gates delivery — see migrations '
            '(e.g. 28_realtime_publication_expand.sql, 20260514130000_messages_realtime_publication.sql).',
          );
        } else if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('[SyncProvider] Postgres realtime subscribe error: $error');
        }
      });
    } catch (e) {
      debugPrint('[SyncProvider] Postgres realtime subscription failed: $e');
    }
  }

  Future<void> _consumePendingPrefetchHints() async {
    if (!SupabaseService.isConfigured || authProvider.activeFamily == null) {
      return;
    }
    final load = await PendingCloudSyncHints.consumeDevotionalPrefetchHint();
    if (!load) return;
    scheduleModuleEnterCloudPull(CloudSyncScope.devotionalBundle);
  }

  /// Lightweight realtime spike: scoped pulls from `activity_hint` payloads
  /// `{ table: "tasks" }` or `{ tables: ["tasks","lists"] }` — alternative to
  /// subscribing to many `postgres_changes` bindings at scale.
  void _onFamilyActivityHintBroadcast(Map<String, dynamic> payload) {
    try {
      final senderId = payload['user_id'];
      if (senderId == authProvider.activeUser?.id) return;
      final tables = <String>{};
      final one = payload['table']?.toString();
      if (one != null && one.isNotEmpty) tables.add(one);
      final list = payload['tables'];
      if (list is List) {
        for (final x in list) {
          final s = x?.toString();
          if (s != null && s.isNotEmpty) tables.add(s);
        }
      }
      if (tables.isEmpty) {
        scheduleDebouncedPullFromCloud(_broadcastPullDebounce);
      } else {
        _scheduleDebouncedRealtimeTablesPull(tables);
      }
    } on Object catch (e) {
      debugPrint('[SyncProvider] activity_hint broadcast: $e');
    }
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

  void _onFamilyScopedPostgresChange(PostgresChangePayload payload) {
    if (_isPostgresSelfEcho(payload)) return;
    _maybeTombstoneFromSoftDelete(payload);
    if (!_outboundCloudSyncActive && !_isSyncing) {
      if (_tryMergeRealtimeMessagesRow(payload)) return;
    }
    _scheduleDebouncedRealtimeTablePull(payload.table);
  }

  void _scheduleDebouncedRealtimeTablePull(String? table) {
    if (table == null || table.isEmpty) {
      if (authProvider.activeFamily == null || !SupabaseService.isConfigured) {
        return;
      }
      scheduleDebouncedPullFromCloud(_postgresRealtimePullDebounce);
      return;
    }
    _scheduleDebouncedRealtimeTablesPull({table});
  }

  void _scheduleDebouncedRealtimeTablesPull(Set<String> tables) {
    if (authProvider.activeFamily == null || !SupabaseService.isConfigured) {
      return;
    }
    if (tables.isEmpty) {
      scheduleDebouncedPullFromCloud(_postgresRealtimePullDebounce);
      return;
    }
    _pendingRealtimePullTables.addAll(tables);
    _realtimePullCoalesceTimer?.cancel();
    _realtimePullCoalesceTimer = Timer(_postgresRealtimePullDebounce, () {
      _realtimePullCoalesceTimer = null;
      final merged = Set<String>.from(_pendingRealtimePullTables);
      _pendingRealtimePullTables.clear();
      if (merged.isEmpty) return;
      _pullModuleScopedFromCloudNow(merged);
    });
  }

  /// Hot path for chat: merge one row locally (reconcile stays the backstop).
  bool _tryMergeRealtimeMessagesRow(PostgresChangePayload payload) {
    if (payload.table != CloudSyncScope.messages) return false;
    final familyId = authProvider.activeFamily?.id;
    if (familyId == null || !FieldEncryption.isReady(familyId)) return false;

    try {
      final db = dataProvider.db;
      if (payload.eventType == PostgresChangeEvent.delete) {
        final id = payload.oldRecord['id']?.toString();
        if (id == null || id.isEmpty) return false;
        final existing = db.messages.firstWhereOrNull((m) => m.id == id);
        if (existing == null) return true;
        dataProvider.updateDb(db.copyWith(
          messages: db.messages.where((m) => m.id != id).toList(),
        ));
        return true;
      }

      final raw = payload.newRecord;
      if (raw.isEmpty) return false;
      if (raw['family_id']?.toString() != familyId) return false;

      final incoming = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
      if (incoming.id.isEmpty) return false;

      final existing = db.messages.firstWhereOrNull((m) => m.id == incoming.id);
      final incomingAt = incoming.editedAt ?? incoming.createdAt;
      if (existing != null) {
        final existingAt = existing.editedAt ?? existing.createdAt;
        if (existingAt.isAfter(incomingAt)) return true;
      }

      dataProvider.updateDb(db.copyWith(
        messages: [...db.messages.where((m) => m.id != incoming.id), incoming],
      ));
      return true;
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
    _realtimePullCoalesceTimer?.cancel();
    _realtimePullCoalesceTimer = null;
    _pendingRealtimePullTables.clear();
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

  /// When an inbound pull was skipped because outbound [syncToCloud] held
  /// `_outboundCloudSyncActive` / `_isSyncing`, flush without the long default
  /// debounce so we do not stack ~450ms on top of the outbound window. We still
  /// avoid concurrent reconcile vs push: shared code paths expect a coherent
  /// local snapshot without overlapping full merges.
  void _flushDeferredCloudPullIfNeeded() {
    if (!_deferredCloudPull) return;
    _deferredCloudPull = false;
    scheduleDebouncedPullFromCloud(_deferredFlushDebounce);
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
        return;
      }
      dataProvider.updateDb(merged);
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
        return;
      }
      dataProvider.updateDb(merged);
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
    unawaited(_consumePendingPrefetchHints());
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
      scheduleDebouncedPullFromCloud(Duration.zero);
      return;
    }
    await _pullFromCloudNow(familyId: fid);
  }

  Future<void> saveAndSync(AppDB newDb, {Set<String>? pushTableScope}) async {
    dataProvider.updateDb(newDb);
    final fam = authProvider.activeFamily;
    if (fam != null) {
      await syncToCloud(newDb, fam.id, tableScope: pushTableScope);
    }
  }

  Future<void> syncToCloud(AppDB newDb, String familyId, {Set<String>? tableScope}) async {
    setOutboundSyncActive(true);
    _broadcastChange();
    try {
      await DatabaseService.syncToCloud(newDb, familyId, tableScope: tableScope);
      setSuccessfulSync();
      _broadcastChange();
    } catch (e) {
      setSyncError(e.toString());
    } finally {
      setOutboundSyncActive(false);
      try {
        await SyncOutbox.drain();
      } finally {
        await _refreshPendingOutboxCount();
      }
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
    dataProvider.updateDb(next);
    await syncToCloud(next, fam.id, tableScope: {CloudSyncScope.familyActivityLogs});
  }

  /// Wait until [syncToCloud]/pull is not holding the sync lock (or [timeout]).
  Future<void> waitForSyncIdle(
      {Duration timeout = const Duration(seconds: 25)}) async {
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      if (!_outboundCloudSyncActive && !_isSyncing) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  /// Like [refreshFromCloud] but waits for a pull slot so notification opens
  /// see freshly merged rows (never returns early while another sync is busy
  /// without at least scheduling [Duration.zero] pull as last resort).
  Future<void> refreshFromCloudAwaitable({String? familyIdOverride}) async {
    final fid = familyIdOverride ?? authProvider.activeFamily?.id;
    if (fid == null || !SupabaseService.isConfigured) return;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    await waitForSyncIdle();
    var activeFid = authProvider.activeFamily?.id ?? fid;
    for (var i = 0; i < 40; i++) {
      if (!_outboundCloudSyncActive && !_isSyncing) {
        await _pullFromCloudNow(familyId: activeFid);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      activeFid = authProvider.activeFamily?.id ?? activeFid;
    }
    _deferredCloudPull = true;
    scheduleDebouncedPullFromCloud(Duration.zero);
  }

  /// Foreground FCM — warm `devotionals` + `devotional_thoughts` before the user taps.
  void prefetchDevotionalTablesForeground() {
    if (authProvider.activeFamily == null || !SupabaseService.isConfigured) return;
    unawaited(() async {
      await waitForSyncIdle(timeout: const Duration(seconds: 5));
      final fam = authProvider.activeFamily;
      if (fam == null) return;
      await _pullModuleScopedFromCloudNow(
          Set<String>.from(CloudSyncScope.devotionalBundle));
    }());
  }
}
