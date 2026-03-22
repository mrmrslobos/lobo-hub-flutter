// lib/providers/app_provider.dart
// FamilyHub - Main application state provider

// ignore_for_file: avoid_catches_without_on_clauses

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, RealtimeChannel, Supabase;

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../services/field_encryption_service.dart';
import '../services/supabase_service.dart';

class AppProvider extends ChangeNotifier {
  User? _activeUser;
  Family? _activeFamily;
  AppDB _db = AppDB.empty();
  bool _isInitializing = true;
  bool _isLocked = false;
  Set<String> _unreadModules = {};
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _postgresChannel;
  bool _isSyncing = false;
  ThemeMode _themeMode = ThemeMode.light;

  // ── Getters ───────────────────────────────────────────────────────────────

  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  AppDB get db => _db;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
  bool get isSyncing => _isSyncing;
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

      if (SupabaseService.isConfigured) {
        final session = SupabaseService.currentSession;
        if (session != null) {
          await _resolveUserFromSession(
            session.user.id,
            session.user.email ?? '',
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

  Future<void> _resolveUserFromSession(String userId, String email) async {
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

    // Authenticate immediately from local data for fast startup
    if (user != null) {
      _setActiveUserFamily(user, knownFamilyId);
      if (knownFamilyId != null &&
          FieldEncryption.isReady(knownFamilyId)) {
        _db = _db.applySensitiveDecryption(knownFamilyId);
        await DatabaseService.saveLocal(_db);
      }
    }

    // If user not found locally, look up membership from cloud
    if (knownFamilyId == null && SupabaseService.isConfigured) {
      try {
        final memberships = await SupabaseService.client
            .from('family_members')
            .select()
            .eq('user_id', userId);
        final rows = SupabaseService.rowsFromSelect(memberships);
        if (rows.isNotEmpty) {
          knownFamilyId = rows.first['family_id'] as String?;
        }
      } catch (e) {
        debugPrint('[AppProvider] Error fetching cloud membership: $e');
      }
    }

    // Reconcile with cloud. We must pull family + membership whenever the local
    // DB is incomplete — not only when `user == null`. Otherwise a stale user
    // row without `family_members` / `families` (reinstall, migration, cache
    // glitch) leaves `knownFamilyId` from the cloud unused and the app shows
    // "create home" even though the account already belongs to a family.
    if (knownFamilyId != null && SupabaseService.isConfigured) {
      final mem = _db.familyMembers.firstWhereOrNull((m) => m.userId == userId);
      final fam = _db.families.firstWhereOrNull((f) => f.id == knownFamilyId);
      final needsReconcile = user == null ||
          mem == null ||
          fam == null ||
          mem.familyId != knownFamilyId;

      if (needsReconcile) {
        try {
          final famRow = await SupabaseService.client
              .from('families')
              .select('join_code')
              .eq('id', knownFamilyId)
              .maybeSingle();
          final jc = famRow != null
              ? famRow['join_code'] as String?
              : null;
          if (jc != null && jc.isNotEmpty) {
            await FieldEncryption.init(knownFamilyId, jc);
          }
          _db = await DatabaseService.reconcileCloud(_db, knownFamilyId);
          user = _db.users.firstWhereOrNull((u) => u.id == userId);
          if (user != null) {
            _setActiveUserFamily(user, knownFamilyId);
            if (FieldEncryption.isReady(knownFamilyId)) {
              _db = _db.applySensitiveDecryption(knownFamilyId);
              await DatabaseService.saveLocal(_db);
            }
          }
        } catch (e) {
          debugPrint('[AppProvider] Cloud reconciliation failed: $e');
        }
      }
      // Background pull for any remaining updates
      _pullFromCloud();
    }
  }

  void _setActiveUserFamily(User user, String? knownFamilyId) {
    final membership = _db.familyMembers.firstWhereOrNull(
      (m) => m.userId == user.id,
    );
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
      }
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  void _syncAIFlag() {
    AiService.setAIBlocked(!(_activeFamily?.hasAIAccess ?? false));
  }

  void authenticate(User user, Family family) {
    _activeUser = user;
    _activeFamily = family;
    FieldEncryption.init(family.id, family.joinCode);
    _syncAIFlag();
    // Only fall back to DatabaseService cache if _db hasn't been populated
    // (e.g. via setDb after cloud reconciliation).
    if (_db.families.isEmpty) {
      _db = DatabaseService.db;
    }
    _db = _db.applySensitiveDecryption(family.id);
    DatabaseService.saveLocal(_db);
    _startRealtimeListener();
    // Register FCM token so push notifications reach this device
    NotificationService.registerDeviceToken(family.id, user.id);
    notifyListeners();
  }

  /// Update the in-memory DB (e.g. after cloud reconciliation).
  void setDb(AppDB db) {
    _db = db;
    notifyListeners();
  }

  /// Switch the active user (for kid account switching)
  void switchActiveUser(User user) {
    _activeUser = user;
    notifyListeners();
  }

  /// All family-scoped tables that should trigger a sync on any change.
  static const _realtimeTables = [
    'tasks',
    'events',
    'recipes',
    'meal_plans',
    'lists',
    'devotionals',
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
        final senderId = payload is Map ? payload['user_id'] : null;
        if (senderId == _activeUser?.id) return;
        _pullFromCloud();
      },
    );

    // Channel 2: Postgres Realtime — listens for INSERT/UPDATE/DELETE on
    // all family-scoped tables. Catches changes from edge functions, cron
    // jobs, other clients, and direct DB edits. More reliable than
    // broadcast since it doesn't depend on clients sending notifications.
    try {
      var channel = Supabase.instance.client.channel('postgres:$familyId');
      for (final table in _realtimeTables) {
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
            debugPrint('[AppProvider] Postgres change on ${payload.table} — syncing');
            _pullFromCloud();
          },
        );
      }
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

  /// Pull latest data from cloud and merge into local state.
  Future<void> _pullFromCloud() async {
    final familyId = _activeFamily?.id;
    if (_isSyncing || familyId == null) return;
    _isSyncing = true;
    notifyListeners();
    try {
      final merged = await DatabaseService.reconcileCloud(_db, familyId);
      _db = merged;
    } catch (e) {
      debugPrint('[AppProvider] pullFromCloud error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopRealtimeListener();
    super.dispose();
  }

  /// Public method to manually refresh from cloud.
  Future<void> refreshFromCloud() => _pullFromCloud();

  Future<void> logout() async {
    _stopRealtimeListener();
    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};

    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }

    FieldEncryption.clear();
    await DatabaseService.clearLocal();
    _db = AppDB.empty();
    notifyListeners();
  }

  // ── DB mutations ──────────────────────────────────────────────────────────

  /// Update DB in-memory and persist to local storage (no cloud sync).
  void updateDb(AppDB newDb) {
    _db = newDb;
    DatabaseService.saveLocal(newDb);
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

  /// Update DB, notify listeners immediately, then persist + cloud sync.
  Future<void> saveAndSync(AppDB newDb) async {
    _db = newDb;
    notifyListeners();
    if (_activeFamily != null) {
      // Save locally (fast) then fire-and-forget the cloud sync so the
      // UI never blocks on network I/O.
      await DatabaseService.saveLocal(newDb);
      // Broadcast immediately so other devices know to pull — don't wait
      // for the full cloud sync to finish.
      _broadcastChange();
      _isSyncing = true;
      final familyId = _activeFamily!.id;
      DatabaseService.syncToCloud(newDb, familyId).then((_) {
        // Broadcast again after sync completes so other devices pick up
        // the data that's now definitely in the cloud.
        _broadcastChange();
      }).catchError((e) {
        debugPrint('[AppProvider] cloud sync error: $e');
      }).whenComplete(() {
        _isSyncing = false;
      });
    } else {
      await DatabaseService.saveLocal(newDb);
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
    await saveAndSync(_db.copyWith(
      aiHistory: [..._db.aiHistory, entry],
    ));
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
      _activeFamily = family;
      _syncAIFlag();
      notifyListeners();
    }
  }

  void updateFamily(Family family) {
    _activeFamily = family;
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

  /// Resolve a display name for a family member, preferring the User record name
  String memberDisplayName(FamilyMember member) =>
      userById(member.id)?.name ?? member.name;

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
