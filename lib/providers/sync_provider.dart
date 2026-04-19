import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/family_activity_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'data_provider.dart';

class SyncProvider extends ChangeNotifier {
  final AuthProvider authProvider;
  final DataProvider dataProvider;

  SyncProvider({required this.authProvider, required this.dataProvider}) {
    dataProvider.onSaveAndSync = saveAndSync;
    dataProvider.onLogFamilyActivity = logFamilyActivity;
    authProvider.onRefreshFromCloud =
        ({String? familyIdOverride}) =>
            refreshFromCloud(familyIdOverride: familyIdOverride);
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
  static const Duration resumeSyncStaleAfter = Duration(minutes: 3);

  DateTime? _lastSuccessfulSyncAt;
  String? _lastSyncError;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String? get lastSyncError => _lastSyncError;

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
      
      const realtimeTables = [
        'tasks', 'events', 'recipes', 'meal_plans', 'lists', 'devotionals',
        'devotional_thoughts', 'budget_categories', 'budget_entries',
        'transactions', 'chores', 'chore_completions', 'polls', 'poll_votes',
        'reward_items', 'reward_redemptions', 'savings_goals', 'prayer_wall',
        'special_dates', 'family_photos', 'milestones', 'saved_places',
        'messages', 'health_records', 'reading_plans', 'rewards',
        'external_calendars', 'pantry_items', 'family_activity_logs',
        'wellness_check_ins', 'exercise_prs', 'ai_history', 'daily_habits',
        'family_members', 'fitness_logs', 'fitness_plans', 'period_cycles',
        'period_symptoms', 'user_locations', 'workout_exercises',
        'workout_sessions', 'workout_sets'
      ];

      for (final table in realtimeTables) {
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
            scheduleDebouncedPullFromCloud();
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
          scheduleDebouncedPullFromCloud();
        },
      );
      _postgresChannel = channel.subscribe();
    } catch (e) {
      debugPrint('[SyncProvider] Postgres realtime subscription failed: $e');
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
      return;
    }
    _isSyncing = true;
    notifyListeners();
    try {
      final merged = await DatabaseService.reconcileCloud(dataProvider.db, fid);
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        _lastSyncError = err;
        return;
      }
      dataProvider.updateDb(merged);
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
      );
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        _lastSyncError = err;
        return;
      }
      dataProvider.updateDb(merged);
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
}
