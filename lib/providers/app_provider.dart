// lib/providers/app_provider.dart
// Central state management for FamilyHub

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../config/app_config.dart';

class AppProvider extends ChangeNotifier {
  AppDB _db = AppDB.empty();
  User? _activeUser;
  Family? _activeFamily;
  bool _isLoading = false;
  String? _error;

  AppDB get db => _db;
  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;

  // ─────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────

  AppProvider() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final dbJson = prefs.getString(AppConfig.storageKey);
      final activeUserId = prefs.getString(AppConfig.activeUserKey);

      if (dbJson != null) {
        _db = AppDB.fromJsonString(dbJson);
      }

      if (activeUserId != null) {
        _activeUser = _db.users
            .cast<User?>()
            .firstWhere((u) => u?.id == activeUserId, orElse: () => null);

        if (_activeUser != null) {
          final membership = _db.familyMembers
              .cast<FamilyMember?>()
              .firstWhere(
                (m) => m?.userId == _activeUser!.id,
                orElse: () => null,
              );
          if (membership != null) {
            _activeFamily = _db.families
                .cast<Family?>()
                .firstWhere(
                  (f) => f?.id == membership.familyId,
                  orElse: () => null,
                );
          }
        }
      }
    } catch (e) {
      _error = 'Failed to load data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConfig.storageKey, _db.toJsonString());
      if (_activeUser != null) {
        await prefs.setString(AppConfig.activeUserKey, _activeUser!.id);
      }
    } catch (e) {
      _error = 'Failed to save data: $e';
    }
  }

  // ─────────────────────────────────────────────
  // Auth
  // ─────────────────────────────────────────────

  Future<void> authenticate(User user, Family family) async {
    // Upsert user in DB
    final users = List<User>.from(_db.users);
    final userIdx = users.indexWhere((u) => u.id == user.id);
    if (userIdx >= 0) {
      users[userIdx] = user;
    } else {
      users.add(user);
    }

    // Upsert family
    final families = List<Family>.from(_db.families);
    final familyIdx = families.indexWhere((f) => f.id == family.id);
    if (familyIdx >= 0) {
      families[familyIdx] = family;
    } else {
      families.add(family);
    }

    // Ensure membership exists
    final members = List<FamilyMember>.from(_db.familyMembers);
    final memberExists =
        members.any((m) => m.userId == user.id && m.familyId == family.id);
    if (!memberExists) {
      members.add(FamilyMember(
        id: '${user.id}_${family.id}',
        familyId: family.id,
        userId: user.id,
        role: family.ownerId == user.id ? 'owner' : 'member',
        joinedAt: DateTime.now(),
      ));
    }

    _db = _db.copyWith(
      users: users,
      families: families,
      familyMembers: members,
    );
    _activeUser = user;
    _activeFamily = family;

    await _saveToStorage();
    notifyListeners();
  }

  Future<void> logout() async {
    _activeUser = null;
    _activeFamily = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConfig.activeUserKey);

    notifyListeners();
  }

  // ─────────────────────────────────────────────
  // Data mutation
  // ─────────────────────────────────────────────

  Future<void> saveAndSync(AppDB newDb) async {
    _db = newDb;
    // Refresh active family reference in case modules changed
    if (_activeFamily != null) {
      final updated = _db.families
          .cast<Family?>()
          .firstWhere((f) => f?.id == _activeFamily!.id, orElse: () => null);
      if (updated != null) {
        _activeFamily = updated;
      }
    }
    await _saveToStorage();
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  // Module access control
  // ─────────────────────────────────────────────

  bool canAccess(String path) {
    if (_activeFamily == null) return false;
    final modules = _activeFamily!.enabledModules;

    const moduleMap = {
      '/chat': 'chat',
      '/tasks': 'tasks',
      '/calendar': 'calendar',
      '/chores': 'chores',
      '/lists': 'lists',
      '/polls': 'polls',
      '/birthdays': 'occasions',
      '/photos': 'photos',
      '/location': 'location',
      '/health': 'health',
      '/meals': 'meals',
      '/fitness': 'fitness',
      '/period-tracker': 'period_tracker',
      '/devotional': 'devotional',
      '/prayer-wall': 'prayer_wall',
      '/budget': 'budget',
      '/rewards': 'rewards',
    };

    final module = moduleMap[path];
    if (module == null) return true; // dashboard, auth, ai-history always accessible
    return modules.contains(module);
  }

  // ─────────────────────────────────────────────
  // Convenience helpers
  // ─────────────────────────────────────────────

  List<User> get familyMembers {
    if (_activeFamily == null) return [];
    final memberIds = _db.familyMembers
        .where((m) => m.familyId == _activeFamily!.id)
        .map((m) => m.userId)
        .toSet();
    return _db.users.where((u) => memberIds.contains(u.id)).toList();
  }

  User? userById(String id) =>
      _db.users.cast<User?>().firstWhere((u) => u?.id == id, orElse: () => null);

  int chorePointsForUser(String userId) {
    // Sum points from all completed chores for this user in active family
    // Simplified: count last completed chores assigned to user
    return _db.chores
        .where((c) =>
            c.familyId == _activeFamily?.id &&
            c.lastCompletedBy == userId)
        .fold(0, (sum, c) => sum + c.points);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
