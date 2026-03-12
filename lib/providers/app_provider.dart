// lib/providers/app_provider.dart
// FamilyHub - Main application state provider

// ignore_for_file: avoid_catches_without_on_clauses

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

class AppProvider extends ChangeNotifier {
  User? _activeUser;
  Family? _activeFamily;
  AppDB _db = AppDB.empty();
  bool _isInitializing = true;
  bool _isLocked = false;
  Set<String> _unreadModules = {};
  RealtimeChannel? _realtimeChannel;
  bool _isSyncing = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  AppDB get db => _db;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
  bool get isSyncing => _isSyncing;
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
    }

    // If user not found locally, look up membership from cloud
    if (knownFamilyId == null && SupabaseService.isConfigured) {
      try {
        final memberships = await SupabaseService.client
            .from('family_members')
            .select()
            .eq('userId', userId);
        if (memberships is List && memberships.isNotEmpty) {
          knownFamilyId = (memberships.first['familyId'] ??
              memberships.first['family_id']) as String?;
        }
      } catch (_) {}
    }

    // Reconcile with cloud in the background (non-blocking)
    if (knownFamilyId != null && SupabaseService.isConfigured) {
      final fid = knownFamilyId;
      _pullFromCloud();
    } else if (user == null && knownFamilyId != null) {
      // User not in local DB — must wait for cloud sync
      try {
        _db = await DatabaseService.reconcileCloud(_db, knownFamilyId);
        user = _db.users.firstWhereOrNull((u) => u.id == userId);
        if (user != null) _setActiveUserFamily(user, knownFamilyId);
      } catch (e) {
        debugPrint('[AppProvider] Cloud reconciliation failed: $e');
      }
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
        _startRealtimeListener();
        NotificationService.registerDeviceToken(family.id, user.id);
      }
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  void authenticate(User user, Family family) {
    _activeUser = user;
    _activeFamily = family;
    // Only fall back to DatabaseService cache if _db hasn't been populated
    // (e.g. via setDb after cloud reconciliation).
    if (_db.families.isEmpty) {
      _db = DatabaseService.db;
    }
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

  /// Start listening for realtime changes from other family members.
  void _startRealtimeListener() {
    _stopRealtimeListener();
    final familyId = _activeFamily?.id;
    if (familyId == null || !SupabaseService.isConfigured) return;

    _realtimeChannel = SupabaseService.subscribeToFamily(
      familyId,
      onBroadcast: (payload) {
        // Ignore our own broadcasts to avoid race condition where we pull
        // stale cloud data before our own sync has propagated.
        final senderId = payload is Map ? payload['userId'] : null;
        if (senderId == _activeUser?.id) return;
        _pullFromCloud();
      },
    );
  }

  void _stopRealtimeListener() {
    if (_realtimeChannel != null) {
      SupabaseService.unsubscribe(_realtimeChannel!);
      _realtimeChannel = null;
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

  /// Update DB, notify listeners immediately, then persist + cloud sync.
  Future<void> saveAndSync(AppDB newDb) async {
    _db = newDb;
    notifyListeners();
    if (_activeFamily != null) {
      // Block _pullFromCloud during save to prevent stale cloud data
      // from overwriting local changes before sync propagates.
      _isSyncing = true;
      try {
        await DatabaseService.saveAndSync(newDb, _activeFamily!.id);
        // Broadcast change to other family members via realtime channel
        _broadcastChange();
      } finally {
        _isSyncing = false;
      }
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
        payload: {'userId': _activeUser?.id, 'ts': DateTime.now().toIso8601String()},
      );
    } catch (e) {
      debugPrint('[AppProvider] broadcast error: $e');
    }
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

    final family = currentFamily;
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
      notifyListeners();
    }
  }

  void updateFamily(Family family) {
    _activeFamily = family;
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

  /// All family members for the active family
  List<FamilyMember> get familyMembers =>
      db.familyMembers.where((m) => m.familyId == activeFamily?.id).toList();

  /// Look up a User by their ID
  User? userById(String id) =>
      db.users.firstWhereOrNull((u) => u.id == id);

  /// Resolve a display name for a family member, preferring the User record name
  String memberDisplayName(FamilyMember member) =>
      userById(member.id)?.name ?? member.name;

  /// Returns total approved chore points for a given user in the active family
  int chorePointsForUser(String userId) {
    if (_activeFamily == null) return 0;
    final completions = db.choreCompletions.where(
      (c) => c.userId == userId &&
             c.familyId == _activeFamily!.id &&
             c.approvalStatus == ApprovalStatus.APPROVED,
    );
    int total = 0;
    for (final completion in completions) {
      final chore = db.chores.firstWhereOrNull((ch) => ch.id == completion.choreId);
      total += chore?.points ?? 0;
    }
    return total;
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
