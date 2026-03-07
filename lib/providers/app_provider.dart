// lib/providers/app_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../config/app_config.dart';
import '../services/supabase_service.dart';

class AppProvider extends ChangeNotifier {
  AppDB _db = AppDB.empty();
  User? _activeUser;
  Family? _activeFamily;
  bool _isLoading = true;
  String? _error;
  
  // Realtime
  RealtimeChannel? _realtimeChannel;
  
  // Subscription tier cache
  bool _hasAI = false;
  bool _hasBase = false;
  bool _isInTrial = false;

  // Getters
  AppDB get db => _db;
  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
  bool get hasAI => _hasAI;
  bool get hasBase => _hasBase || _isInTrial;
  bool get isInTrial => _isInTrial;

  AppProvider() {
    _loadFromStorage();
  }

  // ─── Init ────────────────────────────────────────────────────────────────

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
        _activeUser = _db.users.cast<User?>().firstWhere(
          (u) => u?.id == activeUserId, orElse: () => null);
        if (_activeUser != null) {
          final membership = _db.familyMembers.cast<FamilyMember?>().firstWhere(
            (m) => m?.userId == _activeUser!.id, orElse: () => null);
          if (membership != null) {
            _activeFamily = _db.families.cast<Family?>().firstWhere(
              (f) => f?.id == membership.familyId, orElse: () => null);
          }
        }
      }

      // If already authenticated, subscribe to realtime
      if (isAuthenticated) {
        _subscribeRealtime();
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
      debugPrint('[AppProvider] save failed: $e');
    }
  }

  // ─── Auth ────────────────────────────────────────────────────────────────

  Future<void> authenticate(User user, Family family) async {
    // Upsert user
    final users = List<User>.from(_db.users);
    final userIdx = users.indexWhere((u) => u.id == user.id);
    if (userIdx >= 0) users[userIdx] = user; else users.add(user);

    // Upsert family
    final families = List<Family>.from(_db.families);
    final familyIdx = families.indexWhere((f) => f.id == family.id);
    if (familyIdx >= 0) families[familyIdx] = family; else families.add(family);

    // Ensure membership
    final members = List<FamilyMember>.from(_db.familyMembers);
    if (!members.any((m) => m.userId == user.id && m.familyId == family.id)) {
      members.add(FamilyMember(
        id: '${user.id}_${family.id}',
        familyId: family.id,
        userId: user.id,
        role: family.ownerId == user.id ? 'owner' : 'member',
        joinedAt: DateTime.now(),
      ));
    }

    _db = _db.copyWith(users: users, families: families, familyMembers: members);
    _activeUser = user;
    _activeFamily = family;

    await _saveToStorage();
    _subscribeRealtime();
    notifyListeners();
  }

  Future<void> logout() async {
    await _unsubscribeRealtime();
    _activeUser = null;
    _activeFamily = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConfig.activeUserKey);
    notifyListeners();
  }

  // ─── Data mutation ───────────────────────────────────────────────────────

  Future<void> saveAndSync(AppDB newDb) async {
    _db = newDb;
    if (_activeFamily != null) {
      final updated = _db.families.cast<Family?>().firstWhere(
        (f) => f?.id == _activeFamily!.id, orElse: () => null);
      if (updated != null) _activeFamily = updated;
    }
    await _saveToStorage();
    _broadcastChange();
    notifyListeners();
  }

  // ─── Realtime ────────────────────────────────────────────────────────────

  void _subscribeRealtime() {
    if (_activeFamily == null) return;
    // Safely check Supabase is configured
    if (!SupabaseService.isConfigured) return;

    _unsubscribeRealtime();
    
    _realtimeChannel = SupabaseService.subscribeFamilyChannel(
      _activeFamily!.id,
      onBroadcast: (payload) {
        // Another device changed the DB — re-fetch from cloud
        _fetchFromCloud();
      },
    );
  }

  Future<void> _unsubscribeRealtime() async {
    if (_realtimeChannel != null) {
      await SupabaseService.unsubscribeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  void _broadcastChange() {
    // Broadcast to family channel so other devices update
    _realtimeChannel?.sendBroadcastMessage(
      event: 'db_change',
      payload: {'userId': _activeUser?.id, 'ts': DateTime.now().millisecondsSinceEpoch},
    );
  }

  Future<void> _fetchFromCloud() async {
    if (!SupabaseService.isConfigured || _activeFamily == null) return;
    try {
      // Upsert key tables from Supabase — simplified: just re-save local state
      // In production, fetch each table and merge
      debugPrint('[AppProvider] Received realtime broadcast, refreshing...');
      notifyListeners();
    } catch (e) {
      debugPrint('[AppProvider] fetchFromCloud failed: $e');
    }
  }

  // ─── Module access ───────────────────────────────────────────────────────

  bool canAccess(String path) {
    if (_activeFamily == null) return false;
    final enabledModules = _activeFamily!.enabledModules;
    if (enabledModules.isEmpty) return true;
    if (!enabledModules.contains(path)) return false;
    
    // Check user-level module access (parental controls)
    if (_activeUser != null) {
      final membership = _db.familyMembers.cast<FamilyMember?>().firstWhere(
        (m) => m?.userId == _activeUser!.id && m?.familyId == _activeFamily!.id,
        orElse: () => null,
      );
      if (membership?.moduleAccess != null) {
        return membership!.moduleAccess!.contains(path);
      }
    }
    return true;
  }

  // ─── Subscription ────────────────────────────────────────────────────────

  void setEntitlements({required bool hasBase, required bool hasAI, required bool isInTrial}) {
    _hasBase = hasBase;
    _hasAI = hasAI;
    _isInTrial = isInTrial;
    notifyListeners();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  List<User> get familyMembers {
    if (_activeFamily == null) return [];
    final memberIds = _db.familyMembers
        .where((m) => m.familyId == _activeFamily!.id)
        .map((m) => m.userId)
        .toSet();
    return _db.users.where((u) => memberIds.contains(u.id)).toList();
  }

  FamilyMember? membershipFor(String userId) =>
    _db.familyMembers.cast<FamilyMember?>().firstWhere(
      (m) => m?.userId == userId && m?.familyId == _activeFamily?.id,
      orElse: () => null,
    );

  User? userById(String id) =>
      _db.users.cast<User?>().firstWhere((u) => u?.id == id, orElse: () => null);

  int chorePointsForUser(String userId) {
    return _db.chores
        .where((c) => c.familyId == _activeFamily?.id && c.lastCompletedBy == userId)
        .fold(0, (sum, c) => sum + c.points);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribeRealtime();
    super.dispose();
  }
}
