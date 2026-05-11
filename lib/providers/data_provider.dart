import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/database_service.dart';

class DataProvider extends ChangeNotifier {
  static const _notificationPrefsKey = 'lobohub_notification_prefs_v1';
  
  AppDB _db = AppDB.empty();
  DateTime? _lastLocalPersistAt;
  bool _completedInitialHydration = false;

  AppDB get db => _db;
  DateTime? get lastLocalPersistAt => _lastLocalPersistAt;
  bool get completedInitialHydration => _completedInitialHydration;

  void updateDb(AppDB newDb) {
    _db = newDb;
    DatabaseService.saveLocal(newDb);
    _lastLocalPersistAt = DateTime.now();
    notifyListeners();
  }

  /// Same as [updateDb] (compat with call sites that merged DB from cloud).
  void setDb(AppDB db) => updateDb(db);

  /// In-memory update only (no disk write). Used mid–auth-flow before persist.
  void setDbMemory(AppDB db) {
    _db = db;
    notifyListeners();
  }

  Future<void> initialize() async {
    _db = await DatabaseService.loadLocal();
    await _loadNotificationPrefsIntoDb();
    _completedInitialHydration = true;
    notifyListeners();
  }

  Future<void> wipeData() async {
    await DatabaseService.wipeAllLocalStorage();
    _db = AppDB.empty();
    await _loadNotificationPrefsIntoDb();
    _completedInitialHydration = true;
    notifyListeners();
  }

  Future<void> syncTasksNow(String familyId) async {
    try {
      await DatabaseService.pushFamilyTasksToCloudNow(_db, familyId);
    } catch (e) {
      debugPrint('[DataProvider] syncTasksNow: $e');
    }
  }

  Future<void> syncListsNow(String familyId) async {
    try {
      await DatabaseService.pushFamilyListsToCloudNow(_db, familyId);
    } catch (e) {
      debugPrint('[DataProvider] syncListsNow: $e');
    }
  }

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
      debugPrint('[DataProvider] notification prefs load: $e');
    }
  }

  Future<void> setDeviceNotificationPrefs(NotificationPrefs prefs) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_notificationPrefsKey, jsonEncode(prefs.toJson()));
      _db = _db.copyWith(notificationPrefs: [prefs]);
      notifyListeners();
    } catch (e) {
      debugPrint('[DataProvider] notification prefs save: $e');
    }
  }

  double choreEarningsForUser(String userId, String familyId) {
    final completions = db.choreCompletions.where(
      (c) => c.userId == userId &&
             c.familyId == familyId &&
             c.approvalStatus == ApprovalStatus.APPROVED,
    );
    double total = 0;
    for (final completion in completions) {
      final chore = db.chores.firstWhereOrNull((ch) => ch.id == completion.choreId);
      total += chore?.reward ?? 0;
    }
    return total;
  }

  double redemptionSpentForUser(String userId, String familyId) {
    return db.rewardRedemptions
        .where((r) =>
            r.userId == userId &&
            r.familyId == familyId &&
            r.status == RedemptionStatus.APPROVED)
        .fold(0.0, (sum, r) => sum + r.amount);
  }

  double availableBalanceForUser(String userId, String familyId) {
    return choreEarningsForUser(userId, familyId) - redemptionSpentForUser(userId, familyId);
  }

  Future<void> Function(AppDB db, {Set<String>? pushTableScope})? onSaveAndSync;
  Future<void> Function({required String action, String? detail, String? relatedUserId})? onLogFamilyActivity;

  Future<void> saveAndSync(AppDB newDb, {Set<String>? pushTableScope}) async {
    updateDb(newDb);
    if (onSaveAndSync != null) {
      await onSaveAndSync!(newDb, pushTableScope: pushTableScope);
    }
  }

  Future<void> logFamilyActivity({
    required String action,
    String? detail,
    String? relatedUserId,
  }) async {
    if (onLogFamilyActivity != null) {
      await onLogFamilyActivity!(
        action: action,
        detail: detail,
        relatedUserId: relatedUserId,
      );
    }
  }
}
