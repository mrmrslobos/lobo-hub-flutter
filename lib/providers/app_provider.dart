// lib/providers/app_provider.dart
// Huddle - Main application state provider

// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel, Supabase;

import '../config/cloud_sync_scope.dart';
import '../utils/app_log.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../services/field_encryption_service.dart';
import '../services/supabase_service.dart';
import '../services/purchase_service.dart';
import '../services/family_activity_service.dart';

class AppProvider extends ChangeNotifier {
  static const _notificationPrefsKey = 'lobohub_notification_prefs_v1';

  User? _activeUser;
  Family? _activeFamily;
  AppDB _db = AppDB.empty();
  bool _isInitializing = true;
  bool _isLocked = false;
  Set<String> _unreadModules = {};
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _postgresChannel;
  bool _isSyncing = false;
  /// When true, a full cloud push from [saveAndSync] is in flight (used to defer pulls).
  bool _outboundCloudSyncActive = false;
  /// Pull was requested while a push (or another blocked state) was running — flush after push completes.
  bool _deferredCloudPull = false;
  Timer? _pullDebounceTimer;
  /// Module-enter partial pulls deferred while a full pull or push is running.
  bool _deferredModulePull = false;
  final Set<String> _deferredModulePullTables = {};
  Timer? _moduleEnterPullTimer;
  final Set<String> _pendingModulePullTables = {};
  static const Duration _defaultPullDebounce = Duration(milliseconds: 450);
  /// After this long without a successful sync, [onAppResumed] triggers a cloud pull.
  static const Duration resumeSyncStaleAfter = Duration(minutes: 3);
  DateTime? _lastSuccessfulSyncAt;
  String? _lastSyncError;
  DateTime? _lastLocalPersistAt;
  ThemeMode _themeMode = ThemeMode.light;

  // ── Getters ───────────────────────────────────────────────────────────────

  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  AppDB get db => _db;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String? get lastSyncError => _lastSyncError;
  /// Bumped after local [DatabaseService.saveLocal] from [updateDb] / [saveAndSync].
  DateTime? get lastLocalPersistAt => _lastLocalPersistAt;
  ThemeMode get themeMode => _themeMode;
  Set<String> get unreadModules => _unreadModules;

  /// Returns the up-to-date Family from the DB (reflects any edits).
  Family? get currentFamily {
    if (_activeFamily == null) return null;
    return _db.families.firstWhereOrNull((f) => f.id == _activeFamily!.id) ??
        _activeFamily;
  }

  // ── Initialization ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    try {
      await _loadThemeMode();
      _db = await DatabaseService.loadLocal();
      await _loadNotificationPrefsIntoDb();

      if (SupabaseService.isConfigured) {
        final session = SupabaseService.currentSession;
        if (session != null) {
          final meta = session.user.userMetadata?['name'];
          await _resolveUserFromSession(
            session.user.id,
            session.user.email ?? '',
            meta is String ? meta : null,
          );
        }
      }
    } catch (e) {
      debugPrint('AppProvider.initialize error: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _resolveUserFromSession(
    String userId,
    String email,
    String? displayName,
  ) async {
    await SupabaseService.claimOwnedFamilies();

    var user = _db.users.firstWhereOrNull((u) => u.id == userId);

    // Determine which family this user belongs to
    var knownFamilyId = _activeFamily?.id;

    // Check local memberships first
    if (knownFamilyId == null && user != null) {
      final membership = _db.familyMembers.firstWhereOrNull(
        (m) => m.userId == userId,
      );
      knownFamilyId = membership?.familyId;
    }

    // Cloud membership (always when Supabase is on) — empty local DB after an
    // update/reinstall still has a session; we need rows before reconcile/RLS pull.
    List<Map<String, dynamic>> cloudMemberRows = [];
    if (SupabaseService.isConfigured) {
      try {
        final memberships = await SupabaseService.client
            .from('family_members')
            .select()
            .eq('user_id', userId);
        cloudMemberRows = SupabaseService.rowsFromSelect(memberships);
        if (knownFamilyId == null && cloudMemberRows.isNotEmpty) {
          knownFamilyId = cloudMemberRows.first['family_id'] as String?;
        }
      } catch (e) {
        debugPrint('[AppProvider] Error fetching cloud membership: $e');
      }
    }

    if (knownFamilyId != null) {
      await _bootstrapSessionFamilyIfNeeded(
        userId: userId,
        email: email,
        displayName: displayName,
        familyId: knownFamilyId,
        membershipRowsForUser: cloudMemberRows,
      );
      user = _db.users.firstWhereOrNull((u) => u.id == userId);
    }

    // Authenticate immediately from local data for fast startup
    if (user != null) {
      _setActiveUserFamily(user, knownFamilyId);
      if (knownFamilyId != null &&
          FieldEncryption.isReady(knownFamilyId)) {
        _db = _db.applySensitiveDecryption(knownFamilyId);
        await DatabaseService.saveLocal(_db);
      }
    }

    // Join code for field encryption, then one full pull (awaited so the first
    // dashboard frame is not stuck on an empty local DB while pull races).
    if (knownFamilyId != null && SupabaseService.isConfigured) {
      try {
        final famRow = await SupabaseService.client
            .from('families')
            .select('join_code')
            .eq('id', knownFamilyId)
            .maybeSingle();
        final jc =
            famRow != null ? famRow['join_code'] as String? : null;
        if (jc != null && jc.isNotEmpty) {
          await FieldEncryption.init(knownFamilyId, jc);
        }
      } catch (e) {
        debugPrint('[AppProvider] join_code fetch: $e');
      }

      await refreshFromCloud(familyIdOverride: knownFamilyId);

      if (DatabaseService.lastError != null) {
        _lastSyncError = DatabaseService.lastError;
        debugPrint('[AppProvider] refreshFromCloud: ${DatabaseService.lastError}');
      } else {
        user = _db.users.firstWhereOrNull((u) => u.id == userId);
        if (user != null) {
          _setActiveUserFamily(user, knownFamilyId);
          if (FieldEncryption.isReady(knownFamilyId)) {
            _db = _db.applySensitiveDecryption(knownFamilyId);
            await DatabaseService.saveLocal(_db);
          }
        }
      }
    }
  }

  /// After an empty/corrupt local DB, ensure [users], [families], and
  /// [family_members] exist so [_setActiveUserFamily] and [reconcileCloud] work.
  Future<void> _bootstrapSessionFamilyIfNeeded({
    required String userId,
    required String email,
    required String? displayName,
    required String familyId,
    required List<Map<String, dynamic>> membershipRowsForUser,
  }) async {
    if (familyId.isEmpty) return;

    var rowsForFamily = membershipRowsForUser
        .where((r) => r['family_id']?.toString() == familyId)
        .toList();
    if (rowsForFamily.isEmpty && SupabaseService.isConfigured) {
      try {
        final memberships = await SupabaseService.client
            .from('family_members')
            .select()
            .eq('user_id', userId)
            .eq('family_id', familyId);
        rowsForFamily = SupabaseService.rowsFromSelect(memberships);
      } catch (e) {
        debugPrint('[AppProvider] bootstrap family_members fetch: $e');
      }
    }
    if (rowsForFamily.isEmpty) return;

    final hasFam = _db.families.any((f) => f.id == familyId);
    final hasMem = _db.familyMembers
        .any((m) => m.userId == userId && m.familyId == familyId);
    final hasUser = _db.users.any((u) => u.id == userId);
    if (hasFam && hasMem && hasUser) return;

    try {
      Family? family;
      if (!hasFam) {
        final row = await SupabaseService.client
            .from('families')
            .select()
            .eq('id', familyId)
            .maybeSingle();
        if (row != null) {
          family = Family.fromJson(Map<String, dynamic>.from(row));
        }
      }

      User? newUser;
      if (!hasUser) {
        final name = (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : (email.isNotEmpty ? email.split('@').first : 'Member');
        newUser = User(id: userId, name: name, email: email);
      }

      final newMembers = rowsForFamily
          .map((r) => FamilyMember.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      final mergedMembers = DatabaseService.dedupeFamilyMembers([
        ..._db.familyMembers,
        ...newMembers,
      ]);

      var next = _db;
      if (family != null) {
        next = next.copyWith(families: [...next.families, family]);
      }
      if (newUser != null) {
        next = next.copyWith(users: [...next.users, newUser]);
      }
      next = next.copyWith(familyMembers: mergedMembers);
      _db = next;
      await DatabaseService.saveLocal(_db);
    } catch (e, st) {
      debugPrint('[AppProvider] _bootstrapSessionFamilyIfNeeded: $e\n$st');
    }
  }

  void _setActiveUserFamily(User user, String? knownFamilyId) {
    final membership = knownFamilyId != null
        ? _db.familyMembers.firstWhereOrNull(
            (m) => m.userId == user.id && m.familyId == knownFamilyId,
          ) ??
            _db.familyMembers.firstWhereOrNull((m) => m.userId == user.id)
        : _db.familyMembers.firstWhereOrNull((m) => m.userId == user.id);
    if (membership != null) {
      final family = _db.families.firstWhereOrNull(
        (f) => f.id == membership.familyId,
      );
      if (family != null) {
        _activeUser = user;
        _activeFamily = family;
        FieldEncryption.init(family.id, family.joinCode);
        _syncAIFlag();
        _startRealtimeListener();
        NotificationService.registerDeviceToken(family.id, user.id);
        unawaited(_repairOwnerMembershipIfNeeded());
        unawaited(PurchaseService.syncIdentity(user.id));
        unawaited(refreshStoreSubscription());
      }
    }
  }

  /// If [families.owner_id] matches the active user but [family_members.role]
  /// was downgraded (e.g. join-with-code upsert), restore OWNER and sync.
  Future<void> _repairOwnerMembershipIfNeeded() async {
    final user = _activeUser;
    final fam = _activeFamily;
    if (user == null || fam == null) return;

    var members = DatabaseService.dedupeFamilyMembers(
      List<FamilyMember>.from(_db.familyMembers),
    );
    final idx = members.indexWhere(
      (m) => m.userId == user.id && m.familyId == fam.id,
    );
    if (idx < 0) return;

    var changed = members.length != _db.familyMembers.length;
    if (fam.ownerId == user.id && members[idx].role != Role.OWNER) {
      members[idx] = members[idx].copyWith(role: Role.OWNER);
      changed = true;
    }
    if (!changed) return;

    _db = _db.copyWith(familyMembers: members);
    await DatabaseService.saveLocal(_db);
    if (SupabaseService.isConfigured) {
      try {
        await DatabaseService.syncToCloud(_db, fam.id);
      } catch (e) {
        debugPrint('[AppProvider] Owner membership repair sync failed: $e');
      }
    }
    notifyListeners();
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  void _syncAIFlag() {
    AiService.setAIBlocked(!(currentFamily?.hasAIAccess ?? false));
  }

  /// After purchase or app resume: read RevenueCat entitlements and update
  /// [Family.subscriptionTier] locally + on Supabase so [ai-proxy] matches the app.
  Future<void> refreshStoreSubscription() async {
    final fam = currentFamily;
    if (fam == null || !PurchaseService.isConfigured) return;
    try {
      final info = await Purchases.getCustomerInfo();
      final tier = PurchaseService.subscriptionTierFromCustomerInfo(info);
      if (tier == null || tier == fam.subscriptionTier) {
        _syncAIFlag();
        return;
      }
      final updated = fam.copyWith(
        subscriptionTier: tier,
        updatedAt: DateTime.now(),
      );
      _activeFamily = updated;
      _db = _db.copyWith(
        families: _db.families.map((f) => f.id == updated.id ? updated : f).toList(),
      );
      _syncAIFlag();
      notifyListeners();
      await DatabaseService.saveLocal(_db);
      if (SupabaseService.isConfigured) {
        await SupabaseService.syncFamilySubscriptionTier(
          familyId: updated.id,
          tier: tier,
        );
        await refreshFromCloud();
      }
    } catch (e) {
      debugPrint('[AppProvider] refreshStoreSubscription error: $e');
      _syncAIFlag();
    }
  }

  Future<void> authenticate(User user, Family family) async {
    _activeUser = user;
    _activeFamily = family;
    FieldEncryption.init(family.id, family.joinCode);
    _syncAIFlag();
    if (_db.families.isEmpty) {
      _db = DatabaseService.db;
    }
    _db = _db.applySensitiveDecryption(family.id);
    await DatabaseService.saveLocal(_db);
    _startRealtimeListener();
    NotificationService.registerDeviceToken(family.id, user.id);
    notifyListeners();
    unawaited(_repairOwnerMembershipIfNeeded());
    unawaited(_backfillMissingUsersIfNeeded(family.id));
    unawaited(PurchaseService.syncIdentity(user.id));
    unawaited(refreshStoreSubscription());
  }

  /// When [users] rows are missing for people in [family_members], load or stub
  /// them so chores/tasks show real names (not generic "Member").
  Future<void> _backfillMissingUsersIfNeeded(String familyId) async {
    final needs = _db.familyMembers
        .where((m) => m.familyId == familyId)
        .any((m) => !_db.users.any((u) => u.id == m.userId));
    if (!needs) return;
    try {
      final updated =
          await DatabaseService.backfillMissingUsersForFamily(_db, familyId);
      _db = updated;
      await DatabaseService.saveLocal(_db);
      notifyListeners();
    } catch (e) {
      debugPrint('[AppProvider] backfillMissingUsersIfNeeded: $e');
    }
  }

  /// Update the in-memory DB (e.g. after cloud reconciliation).
  void setDb(AppDB db) {
    _db = db;
    notifyListeners();
    final fid = _activeFamily?.id;
    if (fid != null) {
      unawaited(_backfillMissingUsersIfNeeded(fid));
    }
  }

  /// Switch the active user (for kid account switching)
  void switchActiveUser(User user) {
    _activeUser = user;
    notifyListeners();
  }

  /// Tables with `family_id` — Postgres Realtime filter `family_id = active family`.
  static const _realtimeTablesFamilyId = [
    'tasks',
    'events',
    'recipes',
    'meal_plans',
    'lists',
    'devotionals',
    'devotional_thoughts',
    'budget_categories',
    'budget_entries',
    'transactions',
    'chores',
    'chore_completions',
    'polls',
    'poll_votes',
    'reward_items',
    'reward_redemptions',
    'savings_goals',
    'prayer_wall',
    'special_dates',
    'family_photos',
    'milestones',
    'saved_places',
    'messages',
    'health_records',
    'reading_plans',
    'rewards',
    'external_calendars',
    'pantry_items',
    'family_activity_logs',
    'wellness_check_ins',
    'exercise_prs',
    // Previously missing — multi-device habits, AI history, location, fitness, period, membership
    'ai_history',
    'daily_habits',
    'family_members',
    'fitness_logs',
    'fitness_plans',
    'period_cycles',
    'period_symptoms',
    'user_locations',
    'workout_exercises',
    'workout_sessions',
    'workout_sets',
  ];

  /// Start listening for realtime changes — both from other clients
  /// (broadcast) and from server-side processes (Postgres changes).
  void _startRealtimeListener() {
    _stopRealtimeListener();
    final familyId = _activeFamily?.id;
    if (familyId == null || !SupabaseService.isConfigured) return;

    // Channel 1: Broadcast — kept for backward compatibility with clients
    // that haven't updated yet. Will be removed once all clients use
    // Postgres Realtime.
    _realtimeChannel = SupabaseService.subscribeToFamily(
      familyId,
      onBroadcast: (payload) {
        final senderId = payload['user_id'];
        if (senderId == _activeUser?.id) return;
        scheduleDebouncedPullFromCloud();
      },
    );

    // Channel 2: Postgres Realtime — listens for INSERT/UPDATE/DELETE on
    // all family-scoped tables. Catches changes from edge functions, cron
    // jobs, other clients, and direct DB edits. More reliable than
    // broadcast since it doesn't depend on clients sending notifications.
    try {
      var channel = Supabase.instance.client.channel('postgres:$familyId');
      for (final table in _realtimeTablesFamilyId) {
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
            debugPrint('[AppProvider] Postgres change on ${payload.table} — scheduling pull');
            scheduleDebouncedPullFromCloud();
          },
        );
      }
      // `families` row is keyed by `id`, not `family_id`
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
          debugPrint('[AppProvider] Postgres change on families — scheduling pull');
          scheduleDebouncedPullFromCloud();
        },
      );
      _postgresChannel = channel.subscribe();
    } catch (e) {
      debugPrint('[AppProvider] Postgres realtime subscription failed: $e');
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

  /// Coalesce rapid Postgres/broadcast events into a single [reconcileCloud].
  void scheduleDebouncedPullFromCloud([Duration debounce = _defaultPullDebounce]) {
    if (_activeFamily == null || !SupabaseService.isConfigured) return;
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = Timer(debounce, () {
      _pullDebounceTimer = null;
      unawaited(_pullFromCloudNow());
    });
  }

  /// Lighter debounce when opening modules that still benefit from a fresh pull
  /// (e.g. tables without realtime or nested user-scoped rows).
  ///
  /// Pass [pullTables] (Supabase table names, see [CloudSyncScope]) to fetch and
  /// merge only those relations; omit for a full [reconcileCloud] after 200ms.
  void scheduleModuleEnterCloudPull([Set<String>? pullTables]) {
    if (_activeFamily == null || !SupabaseService.isConfigured) return;
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
      unawaited(_pullModuleScopedFromCloudNow(scope));
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
      unawaited(_pullModuleScopedFromCloudNow(t));
    }
  }

  /// Pull latest data from cloud and merge into local state (immediate).
  ///
  /// [familyId] overrides [_activeFamily] (e.g. session restore before the
  /// home row exists locally — otherwise refresh would no-op).
  Future<void> _pullFromCloudNow({String? familyId}) async {
    final fid = familyId ?? _activeFamily?.id;
    if (fid == null || !SupabaseService.isConfigured) return;
    if (_outboundCloudSyncActive || _isSyncing) {
      _deferredCloudPull = true;
      return;
    }
    _isSyncing = true;
    notifyListeners();
    try {
      final merged = await DatabaseService.reconcileCloud(_db, fid);
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        _lastSyncError = err;
        return;
      }
      _db = merged;
      await DatabaseService.saveLocal(_db);
      await _repairOwnerMembershipIfNeeded();
      _lastSuccessfulSyncAt = DateTime.now();
      _lastSyncError = null;
    } catch (e) {
      debugPrint('[AppProvider] pullFromCloud error: $e');
      _lastSyncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
      _flushDeferredCloudPullIfNeeded();
      _flushDeferredModulePullIfNeeded();
    }
  }

  /// Merge only [tables] from Supabase (see [CloudSyncScope] keys).
  Future<void> _pullModuleScopedFromCloudNow(Set<String> tables) async {
    final familyId = _activeFamily?.id;
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
        _db,
        familyId,
        pullTables: tables,
      );
      final err = DatabaseService.lastError;
      if (err != null && err.isNotEmpty) {
        _lastSyncError = err;
        return;
      }
      _db = merged;
      await DatabaseService.saveLocal(_db);
      await _repairOwnerMembershipIfNeeded();
      _lastSuccessfulSyncAt = DateTime.now();
      _lastSyncError = null;
    } catch (e) {
      debugPrint('[AppProvider] pullModuleScopedFromCloud error: $e');
      _lastSyncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
      _flushDeferredCloudPullIfNeeded();
      _flushDeferredModulePullIfNeeded();
    }
  }

  /// Clears the last sync error banner without pulling (e.g. user acknowledges offline work).
  void clearSyncError() {
    if (_lastSyncError == null) return;
    _lastSyncError = null;
    notifyListeners();
  }

  /// When the app returns to foreground: pull only if data is stale or the last sync failed.
  void onAppResumed() {
    if (!isAuthenticated || !SupabaseService.isConfigured) return;
    final at = _lastSuccessfulSyncAt;
    final hadError = _lastSyncError != null && _lastSyncError!.isNotEmpty;
    final stale = at == null ||
        DateTime.now().difference(at) > resumeSyncStaleAfter;
    if (stale || hadError) {
      unawaited(refreshFromCloud());
    }
  }

  /// Cancel pending debounced pulls and run a full reconcile (defers if a push/pull is active).
  ///
  /// [familyIdOverride] is used when restoring a session before [_activeFamily]
  /// is set (e.g. local DB missing the `families` row until the first pull).
  Future<void> refreshFromCloud({String? familyIdOverride}) async {
    _pullDebounceTimer?.cancel();
    _pullDebounceTimer = null;
    final fid = familyIdOverride ?? _activeFamily?.id;
    if (fid == null || !SupabaseService.isConfigured) return;
    if (_outboundCloudSyncActive || _isSyncing) {
      _deferredCloudPull = true;
      scheduleDebouncedPullFromCloud(Duration.zero);
      return;
    }
    await _pullFromCloudNow(familyId: fid);
  }

  @override
  void dispose() {
    _cancelScheduledCloudPulls();
    _stopRealtimeListener();
    super.dispose();
  }

  Future<void> logout() async {
    _cancelScheduledCloudPulls();
    _stopRealtimeListener();
    _outboundCloudSyncActive = false;
    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    _lastSuccessfulSyncAt = null;
    _lastSyncError = null;
    _isSyncing = false;

    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }

    await PurchaseService.revenueCatLogOut();

    FieldEncryption.clear();
    await DatabaseService.clearLocal();
    _db = AppDB.empty();
    notifyListeners();
  }

  /// Destructive: sign out, clear all local app data (including device prefs),
  /// and return to a fresh state. Does **not** delete server-side Supabase rows.
  Future<void> resetAllLocalDataAndSignOut() async {
    _cancelScheduledCloudPulls();
    _stopRealtimeListener();
    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    _lastSuccessfulSyncAt = null;
    _lastSyncError = null;
    _isSyncing = false;
    _outboundCloudSyncActive = false;

    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }

    await PurchaseService.revenueCatLogOut();

    FieldEncryption.clear();
    AiService.setAIBlocked(false);
    await DatabaseService.wipeAllLocalStorage();
    _db = AppDB.empty();
    await _loadThemeMode();
    await _loadNotificationPrefsIntoDb();
    notifyListeners();
  }

  /// Delete the current user's account: remove cloud data, sign out, clear local.
  Future<void> deleteAccount() async {
    final userId = _activeUser?.id;
    final familyId = _activeFamily?.id;

    _cancelScheduledCloudPulls();
    _stopRealtimeListener();

    if (SupabaseService.isConfigured && userId != null) {
      try {
        if (familyId != null) {
          await SupabaseService.deleteRows('family_members', {'user_id': userId, 'family_id': familyId});
        }
        await SupabaseService.deleteRows('users', {'id': userId});
      } catch (_) {}
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }

    await PurchaseService.revenueCatLogOut();

    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    _outboundCloudSyncActive = false;
    FieldEncryption.clear();
    AiService.setAIBlocked(false);
    await DatabaseService.wipeAllLocalStorage();
    _db = AppDB.empty();
    notifyListeners();
  }

  // ── DB mutations ──────────────────────────────────────────────────────────

  /// Update DB in-memory and persist to local storage (no cloud sync).
  void updateDb(AppDB newDb) {
    _db = newDb;
    DatabaseService.saveLocal(newDb);
    _lastLocalPersistAt = DateTime.now();
    notifyListeners();
  }

  /// Await after task create/edit/delete so this family’s tasks hit Supabase
  /// (full [saveAndSync] sync can fail silently or race).
  Future<void> syncTasksNow() async {
    final fam = _activeFamily;
    if (fam == null || !SupabaseService.isConfigured) return;
    try {
      await DatabaseService.pushFamilyTasksToCloudNow(_db, fam.id);
      _broadcastChange();
    } catch (e) {
      debugPrint('[AppProvider] syncTasksNow: $e');
    }
  }

  /// Await after shopping-list edits so item checked state is in Supabase before pull.
  Future<void> syncListsNow() async {
    final fam = _activeFamily;
    if (fam == null || !SupabaseService.isConfigured) return;
    try {
      await DatabaseService.pushFamilyListsToCloudNow(_db, fam.id);
      _broadcastChange();
    } catch (e) {
      debugPrint('[AppProvider] syncListsNow: $e');
    }
  }

  /// Merge keys into [activeUser.settings] and persist (users table sync).
  Future<void> updateActiveUserSettings(Map<String, dynamic> patch) async {
    final u = _activeUser;
    if (u == null || patch.isEmpty) return;
    final next = Map<String, dynamic>.from(u.settings)..addAll(patch);
    final updated = u.copyWith(settings: next);
    _activeUser = updated;
    _db = _db.copyWith(
      users: _db.users.map((x) => x.id == u.id ? updated : x).toList(),
    );
    notifyListeners();
    await saveAndSync(_db, pushTableScope: {CloudSyncScope.users});
  }

  /// Update DB, notify listeners immediately, then persist + cloud sync.
  ///
  /// [pushTableScope] limits which Supabase tables are upserted after the
  /// identity trio (users, families, family_members), which always run first.
  /// Null means push all tables (full sync).
  Future<void> saveAndSync(AppDB newDb, {Set<String>? pushTableScope}) async {
    _db = newDb;
    notifyListeners();
    await DatabaseService.saveLocal(newDb);
    _lastLocalPersistAt = DateTime.now();
    notifyListeners();
    if (_activeFamily != null) {
      // Fire-and-forget the cloud sync so the UI never blocks on network I/O.
      // Broadcast immediately so other devices know to pull — don't wait
      // for the full cloud sync to finish.
      _broadcastChange();
      _outboundCloudSyncActive = true;
      _isSyncing = true;
      final familyId = _activeFamily!.id;
      DatabaseService.syncToCloud(newDb, familyId, tableScope: pushTableScope)
          .then((_) {
        _lastSuccessfulSyncAt = DateTime.now();
        _lastSyncError = null;
        // Broadcast again after sync completes so other devices pick up
        // the data that's now definitely in the cloud.
        _broadcastChange();
      }).catchError((e) {
        _lastSyncError = e.toString();
        AppLog.sync('cloud sync error: $e');
      }).whenComplete(() {
        _outboundCloudSyncActive = false;
        _isSyncing = false;
        notifyListeners();
        _flushDeferredCloudPullIfNeeded();
      });
    }
  }

  /// Broadcast a db_change event so other devices pull the latest data.
  void _broadcastChange() {
    if (_realtimeChannel == null || _activeFamily == null) return;
    try {
      _realtimeChannel!.sendBroadcastMessage(
        event: 'db_change',
        payload: {'user_id': _activeUser?.id, 'ts': DateTime.now().toIso8601String()},
      );
    } catch (e) {
      debugPrint('[AppProvider] broadcast error: $e');
    }
  }

  // ── AI History ──────────────────────────────────────────────────────────

  /// Save an AI interaction to history.
  Future<void> saveAiHistory({
    required String module,
    required String prompt,
    required String response,
  }) async {
    final user = _activeUser;
    final family = _activeFamily;
    if (user == null || family == null) return;
    final entry = AIHistory(
      id: const Uuid().v4(),
      userId: user.id,
      familyId: family.id,
      module: module,
      prompt: prompt,
      response: response,
      createdAt: DateTime.now(),
    );
    await saveAndSync(
      _db.copyWith(aiHistory: [..._db.aiHistory, entry]),
      pushTableScope: {CloudSyncScope.aiHistory},
    );
  }

  // ── Unread tracking ───────────────────────────────────────────────────────

  void markModuleRead(String path) {
    if (_unreadModules.contains(path)) {
      _unreadModules = Set.from(_unreadModules)..remove(path);
      notifyListeners();
    }
  }

  void markModuleUnread(String path) {
    if (!_unreadModules.contains(path)) {
      _unreadModules = Set.from(_unreadModules)..add(path);
      notifyListeners();
    }
  }

  // ── Lock ──────────────────────────────────────────────────────────────────

  void setLocked(bool locked) {
    _isLocked = locked;
    notifyListeners();
  }

  // ── Access control ────────────────────────────────────────────────────────

  /// Returns true if the active user can access the given module path.
  bool canAccess(String path) {
    if (_activeUser == null || _activeFamily == null) return false;

    // Normalize: strip leading '/' for comparison since enabledModules
    // and moduleAccess store paths without the leading slash.
    final normalized = path.startsWith('/') ? path.substring(1) : path;

    // Trial gating: if trial expired and no paid plan, restrict to free modules
    final family = currentFamily;
    if (family != null && family.isTrialExpired) {
      if (!Family.freeModules.contains(normalized)) return false;
    }

    final enabled = family?.enabledModules;
    if (enabled != null && enabled.isNotEmpty) {
      // Check both with and without leading slash for compatibility
      if (!enabled.contains(normalized) && !enabled.contains(path)) {
        return false;
      }
    }

    final membership = _db.familyMembers.firstWhereOrNull(
      (m) =>
          m.userId == _activeUser!.id && m.familyId == _activeFamily!.id,
    );

    final access = membership?.moduleAccess;
    if (access == null || access.isEmpty) return true;
    return access.contains(normalized) || access.contains(path);
  }

  // ── Family helpers ────────────────────────────────────────────────────────

  List<Family> get userFamilies {
    if (_activeUser == null) return [];
    return _db.families.where((f) {
      return _db.familyMembers.any(
        (m) => m.userId == _activeUser!.id && m.familyId == f.id,
      );
    }).toList();
  }

  void switchFamily(String familyId) {
    final family = _db.families.firstWhereOrNull((f) => f.id == familyId);
    if (family != null) {
      _stopRealtimeListener();
      _activeFamily = family;
      FieldEncryption.init(family.id, family.joinCode);
      _syncAIFlag();
      _db = _db.applySensitiveDecryption(family.id);
      _startRealtimeListener();
      if (_activeUser != null) {
        NotificationService.registerDeviceToken(family.id, _activeUser!.id);
      }
      notifyListeners();
    }
  }

  void updateFamily(Family family) {
    _activeFamily = family;
    _db = _db.copyWith(
      families: _db.families.map((f) => f.id == family.id ? family : f).toList(),
    );
    _syncAIFlag();
    notifyListeners();
  }

  /// Returns the FamilyMember record for the active user in the active family.
  FamilyMember? get activeUserMembership {
    if (_activeUser == null || _activeFamily == null) return null;
    return _db.familyMembers.firstWhereOrNull(
      (m) => m.userId == _activeUser!.id && m.familyId == _activeFamily!.id,
    );
  }

  /// Returns the Role of the active user, or MEMBER if unknown.
  Role get activeUserRole => activeUserMembership?.role ?? Role.MEMBER;

  bool get isOwner => activeUserRole == Role.OWNER;
  bool get isAdmin =>
      activeUserRole == Role.ADMIN || activeUserRole == Role.OWNER;

  /// Whether the current family's plan includes AI features.
  bool get hasAIAccess => _activeFamily?.hasAIAccess ?? false;

  /// All family members for the active family
  List<FamilyMember> get familyMembers =>
      db.familyMembers.where((m) => m.familyId == activeFamily?.id).toList();

  /// Look up a User by their ID
  User? userById(String id) =>
      db.users.firstWhereOrNull((u) => u.id == id);

  /// Display name for any [userId] in the active family (`family_members.display_name`
  /// first so admins can override raw signup names, then [User.name], then [fallback]).
  String displayNameForUserId(String userId, {String fallback = 'Member'}) {
    final fid = activeFamily?.id;
    if (fid != null) {
      for (final m in db.familyMembers) {
        if (m.userId == userId && m.familyId == fid) {
          final dn = m.displayName?.trim();
          if (dn != null && dn.isNotEmpty) return dn;
          break;
        }
      }
    }
    final u = userById(userId);
    if (u != null && u.name.trim().isNotEmpty) return u.name;
    return fallback;
  }

  /// Resolve a display name for a family member, preferring the User record name
  String memberDisplayName(FamilyMember member) =>
      displayNameForUserId(member.id, fallback: member.name);

  // ── Theme ────────────────────────────────────────────────────────────────

  static const _themePrefKey = 'lobohub_theme_mode';

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themePrefKey);
    switch (value) {
      case 'dark': _themeMode = ThemeMode.dark;
      case 'system': _themeMode = ThemeMode.system;
      default: _themeMode = ThemeMode.light;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKey, mode.name);
  }

  /// Returns total approved chore earnings (dollar value) for a given user
  double choreEarningsForUser(String userId) {
    if (_activeFamily == null) return 0;
    final completions = db.choreCompletions.where(
      (c) => c.userId == userId &&
             c.familyId == _activeFamily!.id &&
             c.approvalStatus == ApprovalStatus.APPROVED,
    );
    double total = 0;
    for (final completion in completions) {
      final chore = db.chores.firstWhereOrNull((ch) => ch.id == completion.choreId);
      total += chore?.reward ?? 0;
    }
    return total;
  }

  /// Returns total spent (approved redemptions) for a given user
  double redemptionSpentForUser(String userId) {
    if (_activeFamily == null) return 0;
    return db.rewardRedemptions
        .where((r) =>
            r.userId == userId &&
            r.familyId == _activeFamily!.id &&
            r.status == RedemptionStatus.APPROVED)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  /// Available balance = earnings - approved redemptions
  double availableBalanceForUser(String userId) {
    return choreEarningsForUser(userId) - redemptionSpentForUser(userId);
  }

  /// First saved notification prefs row, or defaults (device-local).
  NotificationPrefs get deviceNotificationPrefs {
    for (final p in _db.notificationPrefs) {
      return p;
    }
    return const NotificationPrefs();
  }

  Future<void> _loadNotificationPrefsIntoDb() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_notificationPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final p = NotificationPrefs.fromJson(j);
      _db = _db.copyWith(notificationPrefs: [p]);
    } catch (e) {
      debugPrint('[AppProvider] notification prefs load: $e');
    }
  }

  Future<void> setDeviceNotificationPrefs(NotificationPrefs prefs) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_notificationPrefsKey, jsonEncode(prefs.toJson()));
      _db = _db.copyWith(notificationPrefs: [prefs]);
      notifyListeners();
    } catch (e) {
      debugPrint('[AppProvider] notification prefs save: $e');
    }
  }

  /// Record a trust / audit event for the active family.
  Future<void> logFamilyActivity({
    required String action,
    String? detail,
    String? relatedUserId,
  }) async {
    final fam = _activeFamily;
    final uid = _activeUser?.id;
    if (fam == null || uid == null) return;
    final next = FamilyActivityService.append(
      _db,
      familyId: fam.id,
      actorUserId: uid,
      action: action,
      detail: detail,
      relatedUserId: relatedUserId,
    );
    await saveAndSync(
      next,
      pushTableScope: {CloudSyncScope.familyActivityLogs},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension: firstWhereOrNull on List
// ─────────────────────────────────────────────────────────────────────────────

extension ListWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
