// lib/providers/app_provider.dart
// FamilyHub - Main application state provider

// ignore_for_file: avoid_catches_without_on_clauses

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/database_service.dart';
import '../services/supabase_service.dart';

class AppProvider extends ChangeNotifier {
  User? _activeUser;
  Family? _activeFamily;
  AppDB _db = AppDB.empty();
  bool _isInitializing = true;
  bool _isLocked = false;
  Set<String> _unreadModules = {};

  // ── Getters ───────────────────────────────────────────────────────────────

  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  AppDB get db => _db;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
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

    if (user == null) {
      // Try to get the current active family from local state and reconcile
      var knownFamilyId = _activeFamily?.id;

      // If no local family known, try looking up membership from cloud
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

      if (knownFamilyId != null) {
        _db = await DatabaseService.reconcileCloud(_db, knownFamilyId);
        user = _db.users.firstWhereOrNull((u) => u.id == userId);
      }
    }

    if (user != null) {
      final membership = _db.familyMembers.firstWhereOrNull(
        (m) => m.userId == user!.id,
      );
      if (membership != null) {
        final family = _db.families.firstWhereOrNull(
          (f) => f.id == membership.familyId,
        );
        if (family != null) {
          _activeUser = user;
          _activeFamily = family;
        }
      }
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  void authenticate(User user, Family family) {
    _activeUser = user;
    _activeFamily = family;
    _db = DatabaseService.db;
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

  Future<void> logout() async {
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
      await DatabaseService.saveAndSync(newDb, _activeFamily!.id);
    } else {
      await DatabaseService.saveLocal(newDb);
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
    if (_activeUser == null || _activeFamily == null) return true;

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
