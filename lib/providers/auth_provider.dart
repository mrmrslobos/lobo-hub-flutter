import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/cloud_sync_scope.dart';
import '../models/models.dart';
import '../background/background_session_store.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../services/field_encryption_service.dart';
import '../services/supabase_service.dart';
import '../services/purchase_service.dart';
import 'data_provider.dart';

class AuthProvider extends ChangeNotifier {
  User? _activeUser;
  Family? _activeFamily;
  bool _isInitializing = true;
  bool _isLocked = false;
  Set<String> _unreadModules = {};

  final DataProvider dataProvider;

  Future<void> Function({String? familyIdOverride})? onRefreshFromCloud;

  Future<void> Function({String? familyIdOverride})? _syncRefreshFromCloud;
  void Function()? _syncStartRealtime;
  void Function()? _syncStop;
  void Function(Set<String> tables)? _syncNotifyFamilyScopedChange;

  /// Notified when [activeUser] and [activeFamily] are both set (bootstrap, login, family switch).
  void Function()? onSessionReady;

  AuthProvider(this.dataProvider);

  /// Wired by [SyncProvider] after construction (avoids circular imports).
  void registerSyncBridge({
    required Future<void> Function({String? familyIdOverride}) refreshFromCloud,
    required void Function() startRealtimeListener,
    required void Function() stop,
    void Function(Set<String> tables)? notifyFamilyScopedChange,
  }) {
    _syncRefreshFromCloud = refreshFromCloud;
    _syncStartRealtime = startRealtimeListener;
    _syncStop = stop;
    _syncNotifyFamilyScopedChange = notifyFamilyScopedChange;
    onRefreshFromCloud = refreshFromCloud;
  }

  User? get activeUser => _activeUser;
  Family? get activeFamily => _activeFamily;
  bool get isInitializing => _isInitializing;
  bool get isLocked => _isLocked;
  bool get isAuthenticated => _activeUser != null && _activeFamily != null;
  Set<String> get unreadModules => _unreadModules;

  Family? get currentFamily {
    if (_activeFamily == null) return null;
    return dataProvider.db.families.firstWhereOrNull((f) => f.id == _activeFamily!.id) ??
        _activeFamily;
  }

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    try {
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
      debugPrint('[AuthProvider] initialize error: $e');
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
    unawaited(SupabaseService.claimOwnedFamilies());

    var user = dataProvider.db.users.firstWhereOrNull((u) => u.id == userId);

    var knownFamilyId = _activeFamily?.id;

    if (knownFamilyId == null && user != null) {
      final membership = dataProvider.db.familyMembers.firstWhereOrNull(
        (m) => m.userId == userId,
      );
      knownFamilyId = membership?.familyId;
    }

    List<Map<String, dynamic>> cloudMemberRows = [];
    final dbSnapshot = dataProvider.db;
    final bool localLooksComplete = user != null &&
        knownFamilyId != null &&
        dbSnapshot.families.any((f) => f.id == knownFamilyId) &&
        dbSnapshot.familyMembers
            .any((m) => m.userId == userId && m.familyId == knownFamilyId);

    if (!localLooksComplete && SupabaseService.isConfigured) {
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
        debugPrint('[AuthProvider] Error fetching cloud membership: $e');
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
      user = dataProvider.db.users.firstWhereOrNull((u) => u.id == userId);
    }

    if (user != null) {
      _setActiveUserFamily(user, knownFamilyId);
      if (knownFamilyId != null && FieldEncryption.isReady(knownFamilyId)) {
        await dataProvider.updateDb(dataProvider.db.applySensitiveDecryption(knownFamilyId));
      }
    }

    if (knownFamilyId != null && SupabaseService.isConfigured) {
      try {
        final famLocal =
            dataProvider.db.families.firstWhereOrNull((f) => f.id == knownFamilyId);
        final jcLocal = famLocal?.joinCode;
        if (jcLocal != null && jcLocal.isNotEmpty) {
          await FieldEncryption.init(knownFamilyId, jcLocal);
        } else {
          final famRow = await SupabaseService.client
              .from('families')
              .select('join_code')
              .eq('id', knownFamilyId)
              .maybeSingle();
          final jc = famRow != null ? famRow['join_code'] as String? : null;
          if (jc != null && jc.isNotEmpty) {
            await FieldEncryption.init(knownFamilyId, jc);
          }
        }
      } catch (e) {
        debugPrint('[AuthProvider] join_code fetch: $e');
      }

      // Do not await full cloud reconcile here — it blocks [main]/[runApp] for
      // tens of seconds on large families. Local DB + session are already applied;
      // merge results when the pull completes.
      if (_syncRefreshFromCloud != null) {
        final familyIdForPull = knownFamilyId;
        unawaited(
          _syncRefreshFromCloud!(familyIdOverride: familyIdForPull).then((_) async {
            if (DatabaseService.lastError != null) {
              debugPrint(
                  '[AuthProvider] refreshFromCloud: ${DatabaseService.lastError}');
              return;
            }
            final mergedUser =
                dataProvider.db.users.firstWhereOrNull((u) => u.id == userId);
            if (mergedUser != null) {
              _setActiveUserFamily(mergedUser, familyIdForPull);
              if (FieldEncryption.isReady(familyIdForPull)) {
                await dataProvider.updateDb(
                  dataProvider.db.applySensitiveDecryption(familyIdForPull),
                );
              }
            }
          }),
        );
      }
    }
  }

  Future<void> _bootstrapSessionFamilyIfNeeded({
    required String userId,
    required String email,
    required String? displayName,
    required String familyId,
    required List<Map<String, dynamic>> membershipRowsForUser,
  }) async {
    if (familyId.isEmpty) return;

    final db = dataProvider.db;
    final hasFam = db.families.any((f) => f.id == familyId);
    final hasMem =
        db.familyMembers.any((m) => m.userId == userId && m.familyId == familyId);
    final hasUser = db.users.any((u) => u.id == userId);
    if (hasFam && hasMem && hasUser) return;

    var rowsForFamily =
        membershipRowsForUser.where((r) => r['family_id']?.toString() == familyId).toList();
    if (rowsForFamily.isEmpty && SupabaseService.isConfigured) {
      try {
        final memberships = await SupabaseService.client
            .from('family_members')
            .select()
            .eq('user_id', userId)
            .eq('family_id', familyId);
        rowsForFamily = SupabaseService.rowsFromSelect(memberships);
      } catch (e) {
        debugPrint('[AuthProvider] bootstrap family_members fetch: $e');
      }
    }
    if (rowsForFamily.isEmpty) return;

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

      final newMembers =
          rowsForFamily.map((r) => FamilyMember.fromJson(Map<String, dynamic>.from(r))).toList();
      final mergedMembers = DatabaseService.dedupeFamilyMembers([
        ...db.familyMembers,
        ...newMembers,
      ]);

      var next = db;
      if (family != null) {
        next = next.copyWith(families: [...next.families, family]);
      }
      if (newUser != null) {
        next = next.copyWith(users: [...next.users, newUser]);
      }
      next = next.copyWith(familyMembers: mergedMembers);
      await dataProvider.updateDb(next);
    } catch (e, st) {
      debugPrint('[AuthProvider] _bootstrapSessionFamilyIfNeeded: $e\n$st');
    }
  }

  void _setActiveUserFamily(User user, String? knownFamilyId) {
    final db = dataProvider.db;
    final membership = knownFamilyId != null
        ? db.familyMembers.firstWhereOrNull(
            (m) => m.userId == user.id && m.familyId == knownFamilyId,
          ) ??
            db.familyMembers.firstWhereOrNull((m) => m.userId == user.id)
        : db.familyMembers.firstWhereOrNull((m) => m.userId == user.id);
    if (membership != null) {
      final family = db.families.firstWhereOrNull(
        (f) => f.id == membership.familyId,
      );
      if (family != null) {
        _activeUser = user;
        _activeFamily = family;
        unawaited(BackgroundSessionStore.saveActiveSession(
          userId: user.id,
          familyId: family.id,
        ));
        FieldEncryption.init(family.id, family.joinCode);
        _syncAIFlag();
        _syncStartRealtime?.call();
        NotificationService.registerDeviceToken(family.id, user.id);
        unawaited(repairOwnerMembershipIfNeeded());
        unawaited(PurchaseService.syncIdentity(user.id));
        unawaited(refreshStoreSubscription());
        notifyListeners();
        onSessionReady?.call();
      }
    }
  }

  Future<void> repairOwnerMembershipIfNeeded() async {
    final user = _activeUser;
    final fam = _activeFamily;
    if (user == null || fam == null) return;

    var members = DatabaseService.dedupeFamilyMembers(
      List<FamilyMember>.from(dataProvider.db.familyMembers),
    );
    final idx = members.indexWhere(
      (m) => m.userId == user.id && m.familyId == fam.id,
    );
    if (idx < 0) return;

    var changed = members.length != dataProvider.db.familyMembers.length;
    if (fam.ownerId == user.id && members[idx].role != Role.OWNER) {
      members[idx] = members[idx].copyWith(role: Role.OWNER);
      changed = true;
    }
    if (!changed) return;

    await dataProvider.updateDb(dataProvider.db.copyWith(familyMembers: members));
    if (SupabaseService.isConfigured) {
      try {
        await DatabaseService.syncToCloud(dataProvider.db, fam.id);
      } catch (e) {
        debugPrint('[AuthProvider] Owner membership repair sync failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> backfillMissingUsersIfNeeded(String familyId) async {
    final db = dataProvider.db;
    final needs = db.familyMembers
        .where((m) => m.familyId == familyId)
        .any((m) => !db.users.any((u) => u.id == m.userId));
    if (!needs) return;
    try {
      final updated = await DatabaseService.backfillMissingUsersForFamily(db, familyId);
      await dataProvider.updateDb(updated);
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] backfillMissingUsersIfNeeded: $e');
    }
  }

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
      await dataProvider.updateDb(
        dataProvider.db.copyWith(
          families: dataProvider.db.families
              .map((f) => f.id == updated.id ? updated : f)
              .toList(),
        ),
      );
      _syncAIFlag();
      notifyListeners();
      if (SupabaseService.isConfigured) {
        await SupabaseService.syncFamilySubscriptionTier(
          familyId: updated.id,
          tier: tier,
        );
        await onRefreshFromCloud?.call(familyIdOverride: updated.id);
      }
    } catch (e) {
      debugPrint('[AuthProvider] refreshStoreSubscription error: $e');
      _syncAIFlag();
    }
  }

  void _syncAIFlag() {
    AiService.setAIBlocked(!(currentFamily?.hasAIAccess ?? false));
  }

  Future<void> authenticate(User user, Family family, {bool isSignup = false}) async {
    _syncStop?.call();

    _activeUser = user;
    _activeFamily = family;
    FieldEncryption.init(family.id, family.joinCode);
    _syncAIFlag();

    var db = dataProvider.db;
    if (db.families.isEmpty) {
      db = DatabaseService.db;
    }
    if (!db.users.any((u) => u.id == user.id)) {
      db = db.copyWith(users: [...db.users, user]);
    }
    if (!db.families.any((f) => f.id == family.id)) {
      db = db.copyWith(families: [...db.families, family]);
    }

    await dataProvider.updateDb(db.applySensitiveDecryption(family.id));
    NotificationService.registerDeviceToken(family.id, user.id);
    notifyListeners();

    _syncStartRealtime?.call();
    unawaited(repairOwnerMembershipIfNeeded());
    unawaited(backfillMissingUsersIfNeeded(family.id));
    unawaited(PurchaseService.syncIdentity(user.id));
    unawaited(refreshStoreSubscription());
    onSessionReady?.call();
  }

  Future<void> logout() async {
    _syncStop?.call();

    if (SupabaseService.isConfigured) {
      try {
        await SupabaseService.signOut();
      } catch (_) {}
    }
    await PurchaseService.revenueCatLogOut();

    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    FieldEncryption.clear();
    AiService.setAIBlocked(false);

    await dataProvider.wipeData();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final userId = _activeUser?.id;
    final familyId = _activeFamily?.id;

    _syncStop?.call();

    if (SupabaseService.isConfigured && userId != null) {
      try {
        if (familyId != null) {
          await SupabaseService.deleteRows(
              'family_members', {'user_id': userId, 'family_id': familyId});
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
    FieldEncryption.clear();
    AiService.setAIBlocked(false);

    await dataProvider.wipeData();
    notifyListeners();
  }

  void switchActiveUser(User user) {
    _activeUser = user;
    notifyListeners();
  }

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

  void setLocked(bool locked) {
    _isLocked = locked;
    notifyListeners();
  }

  bool canAccess(String path) {
    if (_activeUser == null || _activeFamily == null) return false;

    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final family = currentFamily;

    if (family != null && family.isTrialExpired) {
      if (!Family.freeModules.contains(normalized)) return false;
    }

    final enabled = family?.enabledModules;
    if (enabled != null && enabled.isNotEmpty) {
      if (!enabled.contains(normalized) && !enabled.contains(path)) {
        return false;
      }
    }

    final membership = dataProvider.db.familyMembers.firstWhereOrNull(
      (m) => m.userId == _activeUser!.id && m.familyId == _activeFamily!.id,
    );

    final access = membership?.moduleAccess;
    if (access == null || access.isEmpty) return true;
    return access.contains(normalized) || access.contains(path);
  }

  List<Family> get userFamilies {
    if (_activeUser == null) return [];
    return dataProvider.db.families.where((f) {
      return dataProvider.db.familyMembers.any(
        (m) => m.userId == _activeUser!.id && m.familyId == f.id,
      );
    }).toList();
  }

  void switchFamily(String familyId) {
    final family = dataProvider.db.families.firstWhereOrNull((f) => f.id == familyId);
    if (family != null) {
      _syncStop?.call();
      _activeFamily = family;
      FieldEncryption.init(family.id, family.joinCode);
      _syncAIFlag();
      unawaited(
        dataProvider.updateDb(dataProvider.db.applySensitiveDecryption(family.id)),
      );
      if (_activeUser != null) {
        NotificationService.registerDeviceToken(family.id, _activeUser!.id);
      }
      _syncStartRealtime?.call();
      notifyListeners();
      onSessionReady?.call();
    }
  }

  void updateFamily(Family family) {
    _activeFamily = family;
    unawaited(
      dataProvider.updateDb(dataProvider.db.copyWith(
        families: dataProvider.db.families.map((f) => f.id == family.id ? family : f).toList(),
      )),
    );
    _syncAIFlag();
    notifyListeners();
  }

  FamilyMember? get activeUserMembership {
    if (_activeUser == null || _activeFamily == null) return null;
    return dataProvider.db.familyMembers.firstWhereOrNull(
      (m) => m.userId == _activeUser!.id && m.familyId == _activeFamily!.id,
    );
  }

  Role get activeUserRole => activeUserMembership?.role ?? Role.MEMBER;
  bool get isOwner => activeUserRole == Role.OWNER;
  bool get isAdmin => activeUserRole == Role.ADMIN || activeUserRole == Role.OWNER;
  bool get hasAIAccess => _activeFamily?.hasAIAccess ?? false;

  List<FamilyMember> get familyMembers =>
      dataProvider.db.familyMembers.where((m) => m.familyId == activeFamily?.id).toList();

  User? userById(String id) => dataProvider.db.users.firstWhereOrNull((u) => u.id == id);

  String displayNameForUserId(String userId, {String fallback = 'Member'}) {
    final fid = activeFamily?.id;
    if (fid != null) {
      for (final m in dataProvider.db.familyMembers) {
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

  String memberDisplayName(FamilyMember member) =>
      displayNameForUserId(member.id, fallback: member.name);

  Future<void> updateActiveUserSettings(Map<String, dynamic> patch) async {
    final u = _activeUser;
    if (u == null || patch.isEmpty) return;
    final next = Map<String, dynamic>.from(u.settings)..addAll(patch);
    final updated = u.copyWith(settings: next);
    _activeUser = updated;
    await dataProvider.updateDb(dataProvider.db.copyWith(
      users: dataProvider.db.users.map((x) => x.id == u.id ? updated : x).toList(),
    ));
    notifyListeners();
    if (SupabaseService.isConfigured && _activeFamily != null) {
      await DatabaseService.syncToCloud(dataProvider.db, _activeFamily!.id,
          tableScope: {CloudSyncScope.users});
      _syncNotifyFamilyScopedChange?.call({CloudSyncScope.users});
    }
  }

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
    await dataProvider.updateDb(dataProvider.db.copyWith(aiHistory: [...dataProvider.db.aiHistory, entry]));
    if (SupabaseService.isConfigured) {
      await DatabaseService.syncToCloud(dataProvider.db, family.id,
          tableScope: {CloudSyncScope.aiHistory});
    }
  }

  /// Clears auth/session fields after a destructive local wipe (reset path).
  void forceClearSession() {
    _activeUser = null;
    _activeFamily = null;
    _isLocked = false;
    _unreadModules = {};
    notifyListeners();
  }
}
