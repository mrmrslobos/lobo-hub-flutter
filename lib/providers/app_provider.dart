// lib/providers/app_provider.dart
// Facade over [DataProvider], [AuthProvider], [SyncProvider], [ThemeProvider].
// Screens keep using `AppProvider` while state lives in the split providers.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../models/models.dart';
import '../services/ai_service.dart';
import '../background/background_task_scheduler.dart';
import '../services/daily_devotional_service.dart';
import '../services/database_service.dart';
import '../services/field_encryption_service.dart';
import '../services/purchase_service.dart';
import '../services/supabase_service.dart';

import 'auth_provider.dart';
import 'data_provider.dart';
import 'sync_provider.dart';
import 'theme_provider.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({
    required DataProvider dataProvider,
    required AuthProvider authProvider,
    required SyncProvider syncProvider,
    required ThemeProvider themeProvider,
  })  : _data = dataProvider,
        _auth = authProvider,
        _sync = syncProvider,
        _theme = themeProvider {
    void relay() => notifyListeners();
    _data.addListener(relay);
    _auth.addListener(relay);
    _sync.addListener(relay);
    _theme.addListener(relay);
    _relay = relay;
  }

  late final void Function() _relay;

  final DataProvider _data;
  final AuthProvider _auth;
  final SyncProvider _sync;
  final ThemeProvider _theme;

  DataProvider get dataProvider => _data;
  AuthProvider get authProvider => _auth;
  SyncProvider get syncProvider => _sync;
  ThemeProvider get themeProvider => _theme;

  AppDB get db => _data.db;

  User? get activeUser => _auth.activeUser;
  Family? get activeFamily => _auth.activeFamily;

  bool get isInitializing => _auth.isInitializing;
  bool get isLocked => _auth.isLocked;
  bool get isAuthenticated => _auth.isAuthenticated;

  bool get isSyncing => _sync.isSyncing;
  DateTime? get lastSuccessfulSyncAt => _sync.lastSuccessfulSyncAt;
  String? get lastSyncError => _sync.lastSyncError;
  DateTime? get lastIncrementalPatchAt => _sync.lastIncrementalPatchAt;
  String? get lastIncrementalPatchTable => _sync.lastIncrementalPatchTable;

  DateTime? get lastLocalPersistAt => _data.lastLocalPersistAt;

  ThemeMode get themeMode => _theme.themeMode;

  Set<String> get unreadModules => _auth.unreadModules;

  Family? get currentFamily => _auth.currentFamily;

  Future<void> initialize() async {
    await _theme.initialize();
    await _data.initialize();
    await _auth.initialize();
  }

  /// After Supabase [AuthChangeEvent.signedIn] when the user already has a JWT.
  /// Reloading the entire local DB here races with in-flight email-password login
  /// ([AuthScreen._login] still running [DatabaseService.reconcileCloud]) and can
  /// desync [DataProvider.db] from what [reconcileCloud] just wrote to disk.
  /// Cold start is handled by [initialize] before the user can sign in interactively.
  Future<void> resumeAuthAfterSupabaseSignIn() async {
    if (!_data.completedInitialHydration) return;
    await _auth.initialize();
  }

  Future<void> refreshStoreSubscription() =>
      _auth.refreshStoreSubscription();

  void switchActiveUser(User user) => _auth.switchActiveUser(user);

  /// Memory-only DB update + backfill missing user rows for the active family.
  void setDb(AppDB db) {
    _data.setDbMemory(db);
    final fid = activeFamily?.id;
    if (fid != null) {
      unawaited(_auth.backfillMissingUsersIfNeeded(fid));
    }
  }

  Future<void> authenticate(User user, Family family) async {
    await _auth.authenticate(user, family);
    unawaited(prepareDailyDevotionalAndSchedule());
  }

  Future<void> logout() async {
    await BackgroundTaskScheduler.clearOnLogout();
    await _auth.logout();
  }

  Future<void> resetAllLocalDataAndSignOut() async {
    _sync.stop();
    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }
    await PurchaseService.revenueCatLogOut();
    FieldEncryption.clear();
    AiService.setAIBlocked(false);
    await DatabaseService.wipeAllLocalStorage();
    await _theme.initialize();
    await _data.initialize();
    _auth.forceClearSession();
  }

  Future<void> deleteAccount() => _auth.deleteAccount();

  Future<void> updateDb(AppDB newDb) => _data.updateDb(newDb);

  Future<void> syncTasksNow() async {
    final fam = activeFamily;
    if (fam == null) return;
    await _data.syncTasksNow(fam.id);
    _sync.sendLocalChangeBroadcast();
  }

  Future<void> syncListsNow() async {
    final fam = activeFamily;
    if (fam == null) return;
    await _data.syncListsNow(fam.id);
    _sync.sendLocalChangeBroadcast();
  }

  Future<void> syncListItemsNow() async {
    final fam = activeFamily;
    if (fam == null) return;
    await _data.syncListItemsNow(fam.id);
    _sync.sendLocalChangeBroadcast();
  }

  Future<void> syncTablesNow(Set<String> tables) async {
    final fam = activeFamily;
    if (fam == null || tables.isEmpty) return;
    try {
      await _data.syncTablesNow(fam.id, tables);
      _sync.sendLocalChangeBroadcast();
    } catch (e) {
      _sync.setSyncError(e.toString());
    }
  }

  Future<void> updateActiveUserSettings(Map<String, dynamic> patch) =>
      _auth.updateActiveUserSettings(patch);

  Future<void> saveAndSync(AppDB newDb, {Set<String>? pushTableScope}) =>
      _sync.saveAndSync(newDb, pushTableScope: pushTableScope);

  Future<void> saveAiHistory({
    required String module,
    required String prompt,
    required String response,
  }) =>
      _auth.saveAiHistory(module: module, prompt: prompt, response: response);

  void markModuleRead(String path) => _auth.markModuleRead(path);

  void markModuleUnread(String path) => _auth.markModuleUnread(path);

  void setLocked(bool locked) => _auth.setLocked(locked);

  bool canAccess(String path) => _auth.canAccess(path);

  List<Family> get userFamilies => _auth.userFamilies;

  void switchFamily(String familyId) => _auth.switchFamily(familyId);

  void updateFamily(Family family) => _auth.updateFamily(family);

  FamilyMember? get activeUserMembership => _auth.activeUserMembership;

  Role get activeUserRole => _auth.activeUserRole;

  bool get isOwner => _auth.isOwner;

  bool get isAdmin => _auth.isAdmin;

  bool get hasAIAccess => _auth.hasAIAccess;

  List<FamilyMember> get familyMembers => _auth.familyMembers;

  User? userById(String id) => _auth.userById(id);

  String displayNameForUserId(String userId, {String fallback = 'Member'}) =>
      _auth.displayNameForUserId(userId, fallback: fallback);

  String memberDisplayName(FamilyMember member) =>
      _auth.memberDisplayName(member);

  Future<void> setThemeMode(ThemeMode mode) => _theme.setThemeMode(mode);

  double choreEarningsForUser(String userId) {
    final fid = activeFamily?.id;
    if (fid == null) return 0;
    return _data.choreEarningsForUser(userId, fid);
  }

  double redemptionSpentForUser(String userId) {
    final fid = activeFamily?.id;
    if (fid == null) return 0;
    return _data.redemptionSpentForUser(userId, fid);
  }

  double availableBalanceForUser(String userId) {
    final fid = activeFamily?.id;
    if (fid == null) return 0;
    return _data.availableBalanceForUser(userId, fid);
  }

  NotificationPrefs get deviceNotificationPrefs =>
      _data.deviceNotificationPrefs;

  Future<void> setDeviceNotificationPrefs(NotificationPrefs prefs) =>
      _data.setDeviceNotificationPrefs(prefs);

  Future<void> logFamilyActivity({
    required String action,
    String? detail,
    String? relatedUserId,
  }) =>
      _sync.logFamilyActivity(
        action: action,
        detail: detail,
        relatedUserId: relatedUserId,
      );

  void scheduleDebouncedPullFromCloud([
    Duration debounce = const Duration(milliseconds: 450),
  ]) =>
      _sync.scheduleDebouncedPullFromCloud(debounce);

  void scheduleModuleEnterCloudPull([Set<String>? pullTables]) =>
      _sync.scheduleModuleEnterCloudPull(pullTables);

  Future<void> refreshFromCloud({String? familyIdOverride}) =>
      _sync.refreshFromCloud(familyIdOverride: familyIdOverride);

  void clearSyncError() => _sync.clearSyncError();

  void notifyFamilyScopedChange(Set<String> tables) =>
      _sync.notifyFamilyScopedChange(tables);

  void onAppResumed() {
    _sync.onAppResumed();
    unawaited(prepareDailyDevotionalAndSchedule());
  }

  /// Foreground: ensure today's devotional exists and sync platform background prep.
  Future<void> prepareDailyDevotionalAndSchedule() async {
    await DailyDevotionalService.prepareOnAppActive(this);
    await BackgroundTaskScheduler.syncDailyDevotionalSchedule(this);
  }

  @override
  void dispose() {
    _data.removeListener(_relay);
    _auth.removeListener(_relay);
    _sync.removeListener(_relay);
    _theme.removeListener(_relay);
    super.dispose();
  }
}
